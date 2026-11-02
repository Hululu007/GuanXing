import XCTest
@testable import GuanXingCore

final class RuleDSLTests: XCTestCase {

    // MARK: - 基础截取

    func testPickBetweenMarkers() {
        let html = "<a title=\"庆余年\" href=\"/d/1.html\">"
        XCTAssertEqual(RuleDSL.pick(html, "title=\"&&\""), "庆余年")
    }

    func testPickFallsBackToSecondBranch() {
        let html = "<a href=\"/d/1.html\">"
        XCTAssertEqual(RuleDSL.pick(html, "title=\"&&\"||href=\"&&\""), "/d/1.html")
    }

    func testPickReturnsNilWhenNoMatch() {
        XCTAssertNil(RuleDSL.pick("<div></div>", "title=\"&&\""))
    }

    func testPickWithEmptyRuleReturnsNil() {
        XCTAssertNil(RuleDSL.pick("<div></div>", nil))
        XCTAssertNil(RuleDSL.pick("<div></div>", ""))
    }

    func testAfterOnlyMarker() {
        let html = "prefix<script>var a = 1;</script>"
        XCTAssertEqual(RuleDSL.pick(html, "<script>&&"), "var a = 1;</script>")
    }

    // MARK: - 拼接与 JSON

    func testConcatenationGluesSegments() {
        let html = "{\"id\":\"12345\"}"
        let value = RuleDSL.pick(html, "https://x.com/v/✚j:id✚.html")
        XCTAssertEqual(value, "https://x.com/v/12345.html")
    }

    func testJSONPathRoot() {
        let json = "{\"data\":{\"name\":\"测试\"}}"
        XCTAssertEqual(RuleDSL.pick(json, "j:data.name"), "测试")
    }

    func testJSONPathArrayIndex() {
        let json = "{\"list\":[{\"name\":\"第一\"},{\"name\":\"第二\"}]}"
        XCTAssertEqual(RuleDSL.pick(json, "j:list[1].name"), "第二")
    }

    func testJSONPathMissingReturnsNil() {
        XCTAssertNil(RuleDSL.pick("{\"a\":1}", "j:b.c"))
    }

    // MARK: - 后置处理

    func testReplaceProcessor() {
        let html = "<a title=\"奇异视频\">"
        XCTAssertEqual(RuleDSL.pick(html, "title=\"&&\"[替换:奇异视频>>黑狐一线]"), "黑狐一线")
    }

    func testReplaceProcessorMultiplePairs() {
        let html = "<a title=\"优酷视频\">"
        XCTAssertEqual(
            RuleDSL.pick(html, "title=\"&&\"[替换:奇异视频>>黑狐一线#优酷视频>>黑狐二线]"),
            "黑狐二线"
        )
    }

    func testContainsProcessorPicksNth() {
        let html = "<i>HD$更新至12集</i>"
        XCTAssertEqual(RuleDSL.pick(html, "<i>&&</i>[含序号:2]"), "更新至12集")
    }

    func testExcludeProcessorFiltersOut() {
        let html = "<a href=\"/hls/play.m3u8\">"
        XCTAssertNil(RuleDSL.pick(html, "href=\"&&\"[不包含:/hls/]"))
    }

    // MARK: - 多条匹配

    func testMatchesExtractsAllBlocks() {
        let html = """
        <div class="box">A</div><div class="box">B</div><div class="box">C</div>
        """
        let blocks = RuleDSL.matches(in: html, rule: "class=\"box\">&&</div>")
        XCTAssertEqual(blocks, ["A", "B", "C"])
    }

    func testMatchesReturnsEmptyWhenNoMatch() {
        XCTAssertTrue(RuleDSL.matches(in: "<p>x</p>", rule: "class=\"box\">&&</div>").isEmpty)
    }

    // MARK: - ID 提取

    func testExtractIDFromQuery() {
        XCTAssertEqual(RuleDSL.extractID("https://a.com/detail?id=9988", fallback: "名"), "9988")
    }

    func testExtractIDFromPath() {
        XCTAssertEqual(RuleDSL.extractID("https://a.com/detail/12345.html", fallback: "名"), "12345")
    }

    func testExtractIDFallsBackToName() {
        XCTAssertEqual(RuleDSL.extractID("https://a.com/about", fallback: "备用名"), "备用名")
    }
}

final class RuleSpiderTests: XCTestCase {

    private func makeSource() -> VodSource {
        VodSource(id: "rule_test", name: "规则源", api: "https://demo.com", origin: .imported)
    }

    private func makeConfig() -> RuleConfig {
        var config = RuleConfig()
        config.homeURL = "https://demo.com"
        config.listArray = "class=\"box\">&&</div>"
        config.title = "title=\"&&\""
        config.link = "href=\"&&\""
        config.pic = "data-src=\"&&\""
        config.subtitle = "ep\">&&<"
        config.categoryURL = "https://demo.com/list/{cateId}/{catePg}.html"
        config.playArray = "class=\"playlist\">&&</ul>"
        config.playList = "<a&&</a>"
        config.playTitle = ">&&<"
        config.playLink = "href=\"&&\""
        return config
    }

    func testParseListProducesItems() {
        let html = """
        <div class="box"><a title="甲" href="/d/1.html" data-src="https://i/a.jpg"><i ep="HD"></i></a></div>
        <div class="box"><a title="乙" href="/d/2.html" data-src="https://i/b.jpg"><i ep="12集"></i></a></div>
        """
        let spider = RuleSpider(config: makeConfig(), source: makeSource())
        let page = spider.parseList(html: html, page: 1)
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.items[0].name, "甲")
        XCTAssertEqual(page.items[0].pic, "https://i/a.jpg")
        XCTAssertEqual(page.items[0].remarks, "HD")
        XCTAssertEqual(page.items[1].name, "乙")
    }

    func testParseListResolvesRelativeLinks() {
        let html = "<div class=\"box\"><a title=\"甲\" href=\"/d/9.html\"></a></div>"
        let spider = RuleSpider(config: makeConfig(), source: makeSource())
        let page = spider.parseList(html: html, page: 1)
        XCTAssertEqual(page.items.first?.vodID, "9")
    }

    func testParseDetailBuildsEpisodes() {
        let html = """
        <div class="playlist"><a href="/p/1.m3u8">第1集</a><a href="/p/2.m3u8">第2集</a></div>
        """
        let item = VodItem(sourceID: "rule_test", sourceName: "规则源", vodID: "1", name: "甲")
        let spider = RuleSpider(config: makeConfig(), source: makeSource())
        let detail = spider.parseDetail(html: html, item: item)
        XCTAssertEqual(detail.lines.count, 1)
        XCTAssertEqual(detail.lines[0].episodes.count, 2)
        XCTAssertEqual(detail.lines[0].episodes[0].name, "第1集")
    }

    func testNeedsSniffingForDirectMedia() {
        let spider = RuleSpider(config: makeConfig(), source: makeSource())
        XCTAssertFalse(spider.needsSniffing("https://a.com/v/1.m3u8"))
        XCTAssertTrue(spider.needsSniffing("https://a.com/play/123.html"))
    }

    func testNoSniffFlagDisablesSniffing() {
        var config = makeConfig()
        config.noSniff = "1"
        let spider = RuleSpider(config: config, source: makeSource())
        XCTAssertFalse(spider.needsSniffing("https://a.com/play/123.html"))
    }
}

final class RuleConfigParserTests: XCTestCase {

    func testClassifyInlineRuleObject() throws {
        let json = try JSONC.parse("""
        {"数组":"class=\\"box\\"&&</div>","标题":"title=\\"&&\\"","链接":"href=\\"&&\\""}
        """)
        guard case .rule(let config) = RuleConfigParser.classify(api: "csp_XBPQ", ext: json) else {
            return XCTFail("应识别为规则型")
        }
        XCTAssertEqual(config.listArray, "class=\"box\"&&</div>")
        XCTAssertEqual(config.title, "title=\"&&\"")
    }

    func testClassifyJavaSpiderIsUnsupported() {
        guard case .unsupported(let reason) = RuleConfigParser.classify(api: "csp_Bili", ext: nil) else {
            return XCTFail("csp_Bili 需要 JVM，应标记不支持")
        }
        XCTAssertTrue(reason.contains("Spider"))
    }

    func testClassifyRuleFileIsUnsupported() {
        guard case .unsupported = RuleConfigParser.classify(api: "csp_XBPQ", ext: "./XBPQ/a.json") else {
            return XCTFail("外部规则文件应标记为不支持")
        }
    }

    func testParseCategories() {
        let pairs = RuleConfigParser.parseCategories("电影$movie#电视剧$tv")
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].0, "movie")
        XCTAssertEqual(pairs[0].1, "电影")
    }

    func testDecodeSniffWords() throws {
        let json = try JSONC.parse("""
        {"数组":"a&&b","嗅探词":".m3u8#.mp4","免嗅":"0","过滤词":"/hls/#php"}
        """)
        guard case .rule(let config) = RuleConfigParser.classify(api: "csp_XBPQ", ext: json) else {
            return XCTFail("应识别")
        }
        XCTAssertEqual(config.sniffWords, ".m3u8#.mp4")
        XCTAssertEqual(config.noSniff, "0")
        XCTAssertEqual(config.filterWords, ["/hls/", "php"])
    }
}
