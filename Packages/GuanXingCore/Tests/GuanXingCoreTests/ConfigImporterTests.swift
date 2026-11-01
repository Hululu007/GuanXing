import XCTest
@testable import GuanXingCore

final class ConfigImporterTests: XCTestCase {
    func testTVBoxConfigWithCommentsAndArtifacts() throws {
        let json = """
        {
          // TVBox 兼容配置
          "name": "测试仓库",
          "sites": [
            {"key":"cms1","name":"影视一","type":1,"api":"https://example.com/api.php/provide/vod/","searchable":1},
            {"key":"spider","name":"爬虫","type":3,"api":"csp_AppYs"},
            {"key":"bad","name":"坏源","type":1,"api":"ftp://bad"},
          ],
          "lives": [
            {"name":"央视","type":0,"url":"https://example.com/live.m3u","epg":"https://example.com/epg.xml"},
            {"name":"单仓","type":1,"url":"https://example.com/live.json"}
          ],
          "parses": [
            {"name":"解析一","type":1,"url":"https://parser.example.com/?url="}
          ],
          "urls": ["https://repo.example.com/index.json"]
        }
        """

        let config = try ImportedConfigParser.parse(text: json)

        XCTAssertEqual(config.name, "测试仓库")
        XCTAssertEqual(config.sources.count, 1)
        XCTAssertEqual(config.sources.first?.name, "影视一")
        XCTAssertEqual(config.sources.first?.api, "https://example.com/api.php/provide/vod")
        XCTAssertEqual(config.liveSources.count, 1)
        XCTAssertEqual(config.parsers.count, 1)
        XCTAssertEqual(config.repositoryURLs.count, 1)
        XCTAssertEqual(config.report.format, "TVBox")
        XCTAssertGreaterThanOrEqual(config.report.skipped, 3)
    }

    func testLibreTVSourceList() throws {
        let json = """
        {"name":"LibreTV 示例","sources":[
          {"name":"非凡","url":"https://cj.ffzyapi.com/api.php/provide/vod/"},
          {"name":"重复","url":"https://cj.ffzyapi.com/api.php/provide/vod"}
        ],"liveSources":[
          {"name":"IPTV","url":"https://iptv-org.github.io/iptv/countries/cn.m3u"}
        ]}
        """
        let config = try ImportedConfigParser.parse(text: json)

        XCTAssertEqual(config.sources.count, 1)
        XCTAssertEqual(config.liveSources.count, 1)
        XCTAssertEqual(config.report.format, "LibreTV")
    }

    func testSourceCatalog() throws {
        let json = """
        [
          {"name":"启用源","baseUrl":"https://a.example.com/api.php/provide/vod"},
          {"name":"停用源","baseUrl":"https://b.example.com/api.php/provide/vod","enabled":false},
          {"name":"直播","baseUrl":"https://c.example.com/live.m3u"}
        ]
        """
        let config = try ImportedConfigParser.parse(text: json)

        XCTAssertEqual(config.sources.count, 1)
        XCTAssertEqual(config.liveSources.count, 1)
        XCTAssertEqual(config.report.format, "接口目录")
        XCTAssertEqual(config.report.skipped, 1)
    }

    func testBase64ImageConfig() throws {
        let payload = #"{"sites":[{"key":"a","name":"源A","type":1,"api":"https://a.example.com/api.php/provide/vod"}]}"#
        let base64 = Data(payload.utf8).base64EncodedString()
        let config = try ImportedConfigParser.parse(text: "data:image/png;base64,\(base64)")

        XCTAssertEqual(config.sources.count, 1)
        XCTAssertEqual(config.sources.first?.name, "源A")
    }
}

final class M3UParserTests: XCTestCase {
    func testParseAttributesAndGroups() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="CCTV1" tvg-logo="https://img.example.com/1.png" group-title="央视",CCTV-1 综合
        #EXTVLCOPT:http-user-agent=ExamplePlayer
        https://live.example.com/cctv1.m3u8
        #EXTINF:-1 group-title="卫视",湖南卫视
        http://live.example.com/hunan.m3u8
        """

        let channels = M3UParser.parse(text, sourceID: "src", sourceName: "测试")

        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].name, "CCTV-1 综合")
        XCTAssertEqual(channels[0].group, "央视")
        XCTAssertEqual(channels[0].tvgID, "CCTV1")
        XCTAssertEqual(channels[0].headers["User-Agent"], "ExamplePlayer")
        let groups = M3UParser.groupChannels(channels)
        XCTAssertEqual(groups.map(\.0), ["央视", "卫视"])
    }

    func testLoadLocalFilePlaylist() async throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 group-title="测试",频道一
        https://example.com/one.m3u8
        #EXTINF:-1 group-title="测试",频道二
        https://example.com/two.m3u8
        """
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("guanxing-\(UUID().uuidString).m3u")
        try text.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let source = LiveSource(id: "local", name: "本地", url: file.absoluteString)
        let channels = try await LiveService.load(source: source)

        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].name, "频道一")
        XCTAssertEqual(channels[0].group, "测试")
    }
}

final class LivePlaylistTests: XCTestCase {
    func testDetectTXTWithGenreMarkers() {
        let text = """
        央视,#genre#
        CCTV-1,http://live.example.com/cctv1.m3u8
        CCTV-2 财经,http://live.example.com/cctv2.m3u8
        卫视,#genre#
        湖南卫视,http://live.example.com/hunan.m3u8
        """
        XCTAssertEqual(LivePlaylist.detect(text), .txt)
        let result = LivePlaylist.parse(text, sourceID: "src", sourceName: "TXT")

        XCTAssertEqual(result?.format, .txt)
        XCTAssertEqual(result?.channels.count, 3)
        XCTAssertEqual(result?.channels.first?.group, "央视")
        XCTAssertEqual(result?.channels[0].name, "CCTV-1")
        XCTAssertEqual(result?.channels.last?.group, "卫视")
        XCTAssertEqual(result?.skippedLineCount, 0)
        let groups = M3UParser.groupChannels(result?.channels ?? [])
        XCTAssertEqual(groups.map(\.0), ["央视", "卫视"])
    }

    func testTXTWithoutGroupAndWithComments() {
        let text = """
        # 我的频道表
        频道一,http://a.example.com/1.m3u8
        频道二,http://a.example.com/2.m3u8,http://a.example.com/2-backup.m3u8
        说明文字,不是地址
        """
        let result = LivePlaylist.parse(text, sourceID: "src", sourceName: "TXT")

        XCTAssertEqual(result?.channels.count, 2)
        XCTAssertNil(result?.channels.first?.group)
        XCTAssertEqual(result?.alternateURLCount, 1)
        XCTAssertEqual(result?.skippedLineCount, 1)
    }

    func testTXTKeepsDuplicateNameDifferentURL() {
        let text = """
        央视频道,#genre#
        CCTV-1,http://a.example.com/1.m3u8
        CCTV-1,http://b.example.com/1.m3u8
        CCTV-1,http://a.example.com/1.m3u8
        """
        let result = LivePlaylist.parse(text, sourceID: "src", sourceName: "TXT")

        XCTAssertEqual(result?.channels.count, 2)
    }

    func testParseJSONChannelTable() {
        let json = """
        {
          "name": "示例直播",
          "groups": [
            {"name":"央视","channels":[
              {"name":"CCTV-1","url":"http://live.example.com/1.m3u8","logo":"https://img.example.com/1.png"},
              {"name":"CCTV-5","url":"http://live.example.com/5.m3u8","group":"体育"}
            ]},
            {"name":"卫视","channels":[
              {"title":"湖南卫视","playUrl":"http://live.example.com/hn.m3u8"}
            ]}
          ]
        }
        """
        XCTAssertEqual(LivePlaylist.detect(json), .json)
        let result = LivePlaylist.parse(json, sourceID: "src", sourceName: "JSON")

        XCTAssertEqual(result?.format, .json)
        XCTAssertEqual(result?.channels.count, 3)
        XCTAssertEqual(result?.channels[0].group, "央视")
        XCTAssertEqual(result?.channels[1].group, "体育")
        XCTAssertEqual(result?.channels[2].group, "卫视")
        XCTAssertEqual(result?.channels[2].name, "湖南卫视")
        XCTAssertEqual(result?.channels[0].logo, "https://img.example.com/1.png")
    }

    func testParseJSONFlatArray() {
        let json = """
        [{"name":"频道A","url":"http://a.example.com/a.m3u8"},
         {"name":"频道B","url":"http://a.example.com/b.flv"}]
        """
        let result = LivePlaylist.parse(json, sourceID: "src", sourceName: "JSON")

        XCTAssertEqual(result?.channels.count, 2)
        XCTAssertEqual(result?.channels[1].isLikelyPlayable, false)
    }

    func testTVBoxConfigIsNotMistakenForLiveJSON() {
        let json = """
        {"sites":[
          {"key":"cms","name":"影视","type":1,"api":"https://a.example.com/api.php/provide/vod"}
        ]}
        """
        XCTAssertNil(LivePlaylist.detect(json))

        let catalog = """
        [{"name":"源","baseUrl":"https://b.example.com/api.php/provide/vod"}]
        """
        XCTAssertNil(LivePlaylist.detect(catalog))
    }

    func testSingleLiveSubscriptionJSONStillParses() {
        let subscription = """
        [{"name":"订阅一","url":"https://cdn.example.com/live/list.m3u"}]
        """
        XCTAssertNil(LivePlaylist.detect(subscription))

        let channels = """
        [{"name":"频道","url":"https://cdn.example.com/live/channel.m3u8"}]
        """
        XCTAssertEqual(LivePlaylist.detect(channels), .json)
    }

    func testImportLocalTXTPlaylistThroughService() async throws {
        let text = """
        央视,#genre#
        CCTV-1 综合,http://live.example.com/cctv1.m3u8
        卫视,#genre#
        湖南卫视,http://live.example.com/hunan.m3u8
        """
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("guanxing-\(UUID().uuidString).txt")
        try text.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let source = LiveSource(id: "local-txt", name: "本地 TXT", url: file.absoluteString)
        let channels = try await LiveService.load(source: source)

        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].group, "央视")
        XCTAssertEqual(channels[1].name, "湖南卫视")
    }

    func testImportJSONPlaylistThroughService() async throws {
        let json = """
        {"groups":[{"name":"测试","channels":[
          {"name":"频道一","url":"http://live.example.com/one.m3u8"}
        ]}]}
        """
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("guanxing-\(UUID().uuidString).json")
        try json.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let source = LiveSource(id: "local-json", name: "本地 JSON", url: file.absoluteString)
        let channels = try await LiveService.load(source: source)

        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].group, "测试")
    }

    func testRejectsUnknownPlaylistFormat() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("guanxing-\(UUID().uuidString).txt")
        try "这不是播放列表".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let source = LiveSource(id: "bad", name: "坏文件", url: file.absoluteString)
        do {
            _ = try await LiveService.load(source: source)
            XCTFail("应当抛出格式错误")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("M3U"))
        }
    }

    func testTextDecoderFallsBackToLatin1() throws {
        let data = Data([0x41, 0xFF, 0x42])
        XCTAssertNotNil(TextDecoder.decode(data))
        let utf8 = Data("#EXTM3U\n#EXTINF:-1,A\nhttp://a/b.m3u8".utf8)
        XCTAssertEqual(TextDecoder.decode(utf8)?.hasPrefix("#EXTM3U"), true)
    }
}

final class TitleGrouperTests: XCTestCase {
    func testGroupsSameTitleFromDifferentSources() {
        let items = [
            VodItem(sourceID: "s1", sourceName: "源一", vodID: "1", name: "庆余年", score: "9.0"),
            VodItem(sourceID: "s2", sourceName: "源二", vodID: "2", name: "庆余年", score: "8.0"),
            VodItem(sourceID: "s3", sourceName: "源三", vodID: "3", name: "繁花"),
            VodItem(sourceID: "s1", sourceName: "源一", vodID: "4", name: "庆余年 第二季")
        ]
        let groups = TitleGrouper.group(items)

        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.first?.title, "庆余年")
        XCTAssertEqual(groups.first?.sourceCount, 2)
        XCTAssertEqual(groups.first?.primary?.score, "9.0")
        XCTAssertEqual(groups.last?.title, "繁花")
    }

    func testGroupsSameSourceMultipleEntries() {
        let items = [
            VodItem(sourceID: "s1", sourceName: "源一", vodID: "1", name: "流浪地球"),
            VodItem(sourceID: "s1", sourceName: "源一", vodID: "2", name: "流浪地球2")
        ]
        let groups = TitleGrouper.group(items)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].sourceCount, 1)
    }

    func testIgnoresEmptyTitles() {
        let items = [VodItem(sourceID: "s", sourceName: "源", vodID: "1", name: "   ")]
        XCTAssertTrue(TitleGrouper.group(items).isEmpty)
    }
}

final class TextAndURLTests: XCTestCase {
    func testURLNormalization() {
        XCTAssertEqual(
            URLNormalizer.normalized(" https://example.com/api.php/provide/vod/ "),
            "https://example.com/api.php/provide/vod"
        )
        XCTAssertNil(URLNormalizer.normalized("ftp://example.com/vod"))
        XCTAssertEqual(
            URLNormalizer.appendQuery(to: "https://example.com/api.php/provide/vod", items: [("ac", "videolist"), ("wd", "庆余年")]),
            "https://example.com/api.php/provide/vod?ac=videolist&wd=%E5%BA%86%E4%BD%99%E5%B9%B4"
        )
    }

    func testHTMLSanitizer() {
        let html = "<p>第一段</p><p>第二段&nbsp;&amp;&nbsp;更多</p><script>bad()</script>"
        XCTAssertEqual(TextSanitizer.plainText(fromHTML: html), "第一段\n第二段 & 更多")
    }
}
