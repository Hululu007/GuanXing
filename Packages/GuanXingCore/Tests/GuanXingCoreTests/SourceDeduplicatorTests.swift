import XCTest
@testable import GuanXingCore

final class SourceDeduplicatorTests: XCTestCase {

    private func source(_ name: String, _ api: String) -> VodSource {
        VodSource(id: "t_" + name, name: name, api: api, origin: .imported)
    }

    func testFingerprintIgnoresSchemeAndTrailingSlash() {
        let a = SourceDeduplicator.fingerprint(for: "https://a.com/api.php/provide/vod/")
        let b = SourceDeduplicator.fingerprint(for: "http://a.com/api.php/provide/vod")
        XCTAssertEqual(a, b)
    }

    func testFingerprintIgnoresQuery() {
        let a = SourceDeduplicator.fingerprint(for: "https://a.com/api.php/provide/vod?ac=list")
        let b = SourceDeduplicator.fingerprint(for: "https://a.com/api.php/provide/vod")
        XCTAssertEqual(a, b)
    }

    func testFingerprintNormalizesXMLAndFromVariants() {
        let canonical = SourceDeduplicator.fingerprint(for: "https://a.com/api.php/provide/vod")
        XCTAssertEqual(canonical, SourceDeduplicator.fingerprint(for: "https://a.com/api.php/provide/vod/at/xml/"))
        XCTAssertEqual(canonical, SourceDeduplicator.fingerprint(for: "https://a.com/api.php/provide/vod/from/kuaikan/"))
    }

    func testFingerprintDropsDefaultPort() {
        let a = SourceDeduplicator.fingerprint(for: "https://a.com:443/api.php/provide/vod")
        let b = SourceDeduplicator.fingerprint(for: "https://a.com/api.php/provide/vod")
        XCTAssertEqual(a, b)
    }

    func testDifferentHostsStayDistinct() {
        XCTAssertNotEqual(
            SourceDeduplicator.fingerprint(for: "https://a.com/api.php/provide/vod"),
            SourceDeduplicator.fingerprint(for: "https://b.com/api.php/provide/vod")
        )
    }

    func testMergeSkipsDuplicatesAgainstExisting() {
        let existing = [source("老源", "https://a.com/api.php/provide/vod")]
        let incoming = [
            source("同源不同写法", "http://a.com/api.php/provide/vod/"),
            source("新源", "https://b.com/api.php/provide/vod")
        ]
        let result = SourceDeduplicator.merge(incoming: incoming, existing: existing)
        XCTAssertEqual(result.added.count, 1)
        XCTAssertEqual(result.added.first?.name, "新源")
        XCTAssertEqual(result.duplicates, 1)
    }

    func testMergeDedupesInsideBatch() {
        let incoming = [
            source("甲", "https://a.com/api.php/provide/vod"),
            source("甲的副本", "https://a.com/api.php/provide/vod/?ac=list"),
            source("乙", "https://b.com/api.php/provide/vod")
        ]
        let result = SourceDeduplicator.merge(incoming: incoming, existing: [])
        XCTAssertEqual(result.added.count, 2)
        XCTAssertEqual(result.duplicates, 1)
    }

    func testMergeOnEmptyIsNoop() {
        let result = SourceDeduplicator.merge(incoming: [], existing: [])
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.duplicates, 0)
    }

    func testRepositoryParserReadsNameAndURL() throws {
        let json = try JSONC.parse("""
        {"urls":[
          {"name":"线路甲","url":"https://a.com/one.json"},
          {"name":"线路乙","url":"http://b.com/two"},
          "https://c.com/three.json"
        ]}
        """)
        let entries = RepositoryParser.entries(from: json, parentName: "多仓")
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].name, "线路甲")
        XCTAssertEqual(entries[1].url, "http://b.com/two")
        XCTAssertEqual(entries[2].name, "c.com")
        XCTAssertEqual(entries[0].parentName, "多仓")
    }

    func testRepositoryParserIgnoresDuplicateURLs() throws {
        let json = try JSONC.parse("""
        {"urls":[
          {"name":"甲","url":"https://a.com/one.json"},
          {"name":"甲的别名","url":"https://a.com/one.json"}
        ]}
        """)
        XCTAssertEqual(RepositoryParser.entries(from: json, parentName: "多仓").count, 1)
    }

    func testRepositoryParserReturnsEmptyForSingleSourceConfig() throws {
        let json = try JSONC.parse("""
        {"sites":[{"key":"a","name":"A","type":1,"api":"https://a.com/api.php/provide/vod"}]}
        """)
        XCTAssertTrue(RepositoryParser.entries(from: json, parentName: "单仓").isEmpty)
    }
}
