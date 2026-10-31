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
