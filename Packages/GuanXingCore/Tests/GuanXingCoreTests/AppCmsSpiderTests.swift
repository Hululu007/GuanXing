import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif
import XCTest
@testable import GuanXingCore

final class AppCmsSpiderTests: XCTestCase {

    func testAESDecryptMatchesJavaPKCS7() throws {
        // 用 Java 端同款 AES/CBC/PKCS7 加密一段固定明文再解回来
        let key = "0123456789abcdef"
        let iv = "fedcba9876543210"
        let plain = #"{"list":[{"vod_id":1}]}"#
        let cipher = try encrypt(plain, key: key, iv: iv)
        let decoded = try AppCmsCrypto.aesDecrypt(cipher, key: key, iv: iv)
        XCTAssertEqual(decoded, plain)
    }

    func testMD5HexMatchesKnownValue() {
        // MD5("abc") = 900150983cd24fb0d6963f7d28e17f72
        XCTAssertEqual(AppCmsCrypto.md5Hex("abc"), "900150983cd24fb0d6963f7d28e17f72")
    }

    func testKindDetectionRequiresRootAndKey() {
        let full: [String: Any] = [
            "url": "https://app.95112475.xyz",
            "dataKey": "0123456789abcdef",
            "dataIv": "fedcba9876543210",
            "version": "4"
        ]
        XCTAssertEqual(AppCmsSpider.kind(forAPIName: "csp_AppGet", ext: full), .appGet)

        var missingKey = full
        missingKey.removeValue(forKey: "dataKey")
        XCTAssertNil(AppCmsSpider.kind(forAPIName: "csp_AppGet", ext: missingKey))

        // 本地相对路径不算可直连
        XCTAssertNil(AppCmsSpider.kind(forAPIName: "csp_AppGet", ext: ["url": "./lib/9.txt"]))

        XCTAssertEqual(
            AppCmsSpider.kind(forAPIName: "csp_AppRJ", ext: ["url": "http://v.rbotv.cn"]),
            .appRJ
        )
    }

    func testConfigParsesExt() throws {
        let ext: [String: Any] = [
            "url": "https://app.95112475.xyz/",
            "dataKey": "0123456789abcdef",
            "dataIv": "fedcba9876543210",
            "deviceId": "abc",
            "version": "4"
        ]
        let config = try XCTUnwrap(AppCmsConfig(ext: ext))
        XCTAssertEqual(config.root, "https://app.95112475.xyz")
        XCTAssertEqual(config.deviceID, "abc")
        XCTAssertEqual(config.version, "4")
    }

    func testPlayListParsing() {
        let source = VodSource(id: "s1", name: "测试", api: "https://example.com")
        let spider = AppCmsSpider(
            source: source,
            kind: .appGet,
            config: AppCmsConfig(root: "https://example.com", dataKey: "", dataIv: "")
        )
        let raw: [[String: Any]] = [
            [
                "player_info": ["show": "BF线路"],
                "urls": [
                    ["name": "第01集", "url": "https://x.com/1.m3u8"],
                    ["name": "第02集", "url": "https://x.com/2.m3u8"]
                ]
            ],
            [
                "player_info": ["show": "备用"],
                "urls": [["name": "正片", "url": "https://x.com/3.m3u8"]]
            ]
        ]
        let lines = spider.parsePlayList(raw)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].name, "BF线路")
        XCTAssertEqual(lines[0].episodes.count, 2)
        XCTAssertEqual(lines[0].episodes[0].url, "https://x.com/1.m3u8")
        XCTAssertEqual(lines[1].episodes.first?.name, "正片")
    }

    func testRJListParsingPrefersPoster() {
        let source = VodSource(id: "s2", name: "热播", api: "http://v.rbotv.cn")
        let spider = AppCmsSpider(
            source: source,
            kind: .appRJ,
            config: AppCmsConfig(root: "http://v.rbotv.cn", dataKey: "", dataIv: "")
        )
        let raw: [[String: Any]] = [[
            "vod_id": 54444,
            "vod_name": "庆余年 第二季",
            "vod_pic": "https://a/pic.jpg",
            "vod_pic_thumb": "https://b/thumb.jpg",
            "vod_remarks": "全36集"
        ]]
        let items = spider.parseRJList(raw)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].vodID, "54444")
        XCTAssertEqual(items[0].pic, "https://a/pic.jpg")
        XCTAssertEqual(items[0].remarks, "全36集")
    }

    func testBindingResolverRejectsUnknownSpider() {
        XCTAssertNil(SpiderBindingResolver.resolve(api: "csp_Mogg", ext: ["site": "https://x.com"], type: 3))
        XCTAssertNil(SpiderBindingResolver.resolve(api: "csp_AppGet", ext: "https://x.com", type: 3))
        XCTAssertNotNil(SpiderBindingResolver.resolve(
            api: "csp_AppGet",
            ext: ["url": "https://x.com", "dataKey": "a", "dataIv": "b"] as [String: Any],
            type: 3
        ))
    }

    func testRuleBindingFromInlineRules() {
        let ext: [String: Any] = [
            "数组": "class=\"box\"&&</a",
            "标题": "title=\"&&\"",
            "播放列表": "href=\"&&\""
        ]
        let binding = SpiderBindingResolver.resolve(api: "csp_XBPQ", ext: ext, type: 3)
        XCTAssertEqual(binding?.kind, .rule)
    }

    func testAPIValidationKeepsHTTPScheme() {
        XCTAssertEqual(SpiderBindingResolver.apiRoot(api: "./lib/9.txt", binding: SpiderBinding(kind: .appGet, payload: #"{"url":"https://x.com"}"#)), "https://x.com")
        XCTAssertNil(SpiderBindingResolver.apiRoot(api: "https://x.com", binding: SpiderBinding(kind: .appGet, payload: "{}")))
    }

    // MARK: - helpers

    private func encrypt(_ text: String, key: String, iv: String) throws -> String {
        #if canImport(CommonCrypto)
        let keyData = Data(key.utf8)
        let ivData = Data(iv.utf8)
        let input = Data(text.utf8)
        var output = Data(count: input.count + 16)
        var written = 0
        let status = output.withUnsafeMutableBytes { outBytes -> CCCryptorStatus in
            guard let outBase = outBytes.baseAddress else { return CCCryptorStatus(kCCMemoryFailure) }
            return input.withUnsafeBytes { inBytes in
                keyData.withUnsafeBytes { keyBytes in
                    ivData.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyData.count,
                            ivBytes.baseAddress,
                            inBytes.baseAddress, input.count,
                            outBase, output.count,
                            &written
                        )
                    }
                }
            }
        }
        XCTAssertEqual(status, CCCryptorStatus(kCCSuccess))
        output.removeSubrange(written..<output.count)
        return output.base64EncodedString()
        #else
        throw XCTSkip("当前平台没有 CommonCrypto")
        #endif
    }
}
