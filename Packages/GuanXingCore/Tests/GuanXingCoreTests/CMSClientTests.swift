import XCTest
@testable import GuanXingCore

final class CMSClientTests: XCTestCase {
    func testPlayLineParsingThroughLiveSource() async throws {
        let source = VodSource(
            id: "test",
            name: "测试源",
            api: "https://api.guangsuapi.com/api.php/provide/vod"
        )
        let detail = try await CMSClient(source: source, timeout: 25).detail(vodID: "113846")

        XCTAssertFalse(detail.lines.isEmpty)
        XCTAssertFalse(detail.lines[0].episodes.isEmpty)
        XCTAssertTrue(detail.lines[0].episodes[0].url.contains("v.gsuus.com"))
    }

    func testPlaybackResolverExtractsWebPage() async throws {
        let resolved = await PlaybackResolver.resolve(
            episodeURL: "https://v.gsuus.com/play/kazVzrma",
            source: VodSource(id: "test", name: "测试", api: "https://api.guangsuapi.com/api.php/provide/vod")
        )
        XCTAssertTrue(resolved.url.contains(".m3u8"))
    }
}
