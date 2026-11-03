import XCTest
@testable import GuanXingCore

final class BuiltinCatalogTests: XCTestCase {

    func testCatalogIsNotEmptyAndAllBuiltin() {
        XCTAssertFalse(BuiltinSources.vod.isEmpty)
        XCTAssertEqual(BuiltinSources.vod.count, 47)
        XCTAssertTrue(BuiltinSources.vod.allSatisfy { $0.origin == .builtin })
        XCTAssertTrue(BuiltinSources.vod.allSatisfy { $0.isEnabled })
        XCTAssertTrue(BuiltinSources.vod.allSatisfy { !$0.isAdult })
    }

    func testEveryEntryIsAnAppleCMSJSONEndpoint() {
        for source in BuiltinSources.vod {
            XCTAssertTrue(source.api.lowercased().hasPrefix("http"), source.name)
            if source.spider != nil { continue }
            let api = source.api.lowercased()
            XCTAssertTrue(
                api.contains("/api.php/provide/vod") || api.contains("/api/provide/vod"),
                source.name + " is not an Apple CMS endpoint: " + source.api
            )
        }
    }

    /// APP 采集型源必须带可还原的协议配置，否则导入后会打不开。
    func testAppCmsEntriesCarrySpiderBinding() {
        for source in BuiltinSources.vod where source.spider != nil {
            let payload = source.spider?.dictionary ?? [:]
            let root = (payload["url"] as? String) ?? (payload["site"] as? String) ?? ""
            XCTAssertTrue(root.lowercased().hasPrefix("http"), source.name)
        }
    }

    func testIDsAndAPIsAreUnique() {
        let ids = BuiltinSources.vod.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate ids in builtin catalog")

        let apis = BuiltinSources.vod.map { $0.api.lowercased() }
        XCTAssertEqual(apis.count, Set(apis).count, "duplicate apis in builtin catalog")
    }

    func testHostsAreMostlyDistinct() {
        let hosts = BuiltinSources.vod.map { $0.host.lowercased() }
        XCTAssertGreaterThanOrEqual(Set(hosts).count, BuiltinSources.vod.count / 2)
    }

    /// 直播源目录只放实测能打开的列表，且必须覆盖国内与多地区。
    func testLiveCatalogEntriesLookValid() {
        for source in BuiltinSources.live {
            XCTAssertTrue(source.url.lowercased().hasPrefix("https://"), source.name)
            XCTAssertTrue(
                source.url.lowercased().hasSuffix(".m3u")
                    || source.url.lowercased().hasSuffix(".m3u8")
                    || source.url.lowercased().hasSuffix(".txt"),
                source.name + " 不是可识别的播放列表地址: " + source.url
            )
        }
        XCTAssertTrue(BuiltinSources.live.contains { $0.name.contains("中国") })
    }

    /// 删除内置直播源后，「更新内置源」不能把它重新加回来。
    func testDeletedBuiltinLiveSourceIsNotRestored() {
        let target = BuiltinSources.live[0]
        let blocked = Set([target.id])
        var live = BuiltinSources.live.filter { !blocked.contains($0.id) }
        for source in BuiltinSources.live where !blocked.contains(source.id) {
            if !live.contains(where: { $0.url == source.url }) { live.append(source) }
        }
        XCTAssertFalse(live.contains { $0.id == target.id })
        XCTAssertEqual(live.count, BuiltinSources.live.count - 1)
    }

    func testLiveCatalogIsBroadAndUnique() {
        XCTAssertGreaterThanOrEqual(BuiltinSources.live.count, 20)
        XCTAssertFalse(BuiltinSources.live.isEmpty)
        XCTAssertTrue(BuiltinSources.live.allSatisfy { $0.origin == .builtin })
        let urls = BuiltinSources.live.map(\.url)
        XCTAssertEqual(urls.count, Set(urls).count)
    }

    func testIsDuplicateMatchesByAPIAndID() {
        let sample = BuiltinSources.vod[0]
        XCTAssertTrue(BuiltinSources.isDuplicate(sample, in: BuiltinSources.vod))

        let sameAPI = VodSource(id: "other-id", name: "same api", api: sample.api.uppercased())
        XCTAssertTrue(BuiltinSources.isDuplicate(sameAPI, in: [sample]))

        let sameID = VodSource(id: sample.id, name: "same id", api: "https://example.com/api.php/provide/vod")
        XCTAssertTrue(BuiltinSources.isDuplicate(sameID, in: [sample]))

        let distinct = VodSource(id: "fresh", name: "fresh", api: "https://fresh.example.com/api.php/provide/vod")
        XCTAssertFalse(BuiltinSources.isDuplicate(distinct, in: BuiltinSources.vod))
    }

    func testCanonicalLookup() {
        let sample = BuiltinSources.vod[3]
        XCTAssertEqual(BuiltinSources.canonical(id: sample.id)?.api, sample.api)
        XCTAssertNil(BuiltinSources.canonical(id: "does-not-exist"))
    }

    func testCatalogVersionMatchesVerifiedDate() {
        XCTAssertEqual(BuiltinSources.verifiedAt, "2026-11-03")
        XCTAssertEqual(BuiltinSources.catalogVersion, "2026.11.03.1")
        XCTAssertGreaterThanOrEqual(BuiltinSources.verifiedAvailableCount, BuiltinSources.vod.count)
        XCTAssertGreaterThanOrEqual(BuiltinSources.verifiedCandidateCount, BuiltinSources.verifiedAvailableCount)
    }
}

final class AppSettingsCompatibilityTests: XCTestCase {

    func testDecodingLegacySettingsUsesDefaults() throws {
        let legacy = """
        {"autoNext":false,"rememberProgress":true,"autoPlay":true,"defaultSpeed":1.5,"preferHighCompatibility":false}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertFalse(settings.autoNext)
        XCTAssertEqual(settings.defaultSpeed, 1.5)
        XCTAssertEqual(settings.removedBuiltinSourceIDs, [])
        XCTAssertEqual(settings.builtinCatalogVersion, BuiltinSources.catalogVersion)
    }

    func testDecodingEmptyObjectUsesDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.autoNext)
        XCTAssertTrue(settings.rememberProgress)
        XCTAssertEqual(settings.defaultSpeed, 1.0)
        XCTAssertEqual(settings.removedBuiltinSourceIDs, [])
    }

    func testRoundTripKeepsRemovalList() throws {
        var settings = AppSettings()
        settings.removedBuiltinSourceIDs = ["builtin_ffzy"]
        settings.builtinCatalogVersion = "2026.10.01"
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }
}

final class BuiltinCatalogReconciliationTests: XCTestCase {

    /// 模拟 AppModel.restoreBuiltinSources 的合并规则：去重、尊重删除、清理失效条目。
    private func reconcile(
        current: [VodSource],
        removedIDs: Set<String>,
        includeDeleted: Bool
    ) -> (list: [VodSource], added: Int, removed: Int) {
        let blocked = includeDeleted ? Set<String>() : removedIDs
        var list = current
        var added = 0
        for source in BuiltinSources.vod where !blocked.contains(source.id) {
            guard !BuiltinSources.isDuplicate(source, in: list) else { continue }
            list.append(source)
            added += 1
        }
        let catalogIDs = Set(BuiltinSources.vod.map(\.id))
        let catalogAPIs = Set(BuiltinSources.vod.map { $0.api.lowercased() })
        let stale = list.filter { source in
            guard source.origin == .builtin else { return false }
            return !catalogIDs.contains(source.id) && !catalogAPIs.contains(source.api.lowercased())
        }
        list.removeAll { source in stale.contains(where: { $0.id == source.id }) }
        return (list, added, stale.count)
    }

    func testEmptyListRestoresWholeCatalog() {
        let result = reconcile(current: [], removedIDs: [], includeDeleted: false)
        XCTAssertEqual(result.list.count, BuiltinSources.vod.count)
        XCTAssertEqual(result.added, BuiltinSources.vod.count)
        XCTAssertEqual(result.removed, 0)
    }

    func testDeletedBuiltinStaysDeletedUntilIncludeDeleted() {
        let target = BuiltinSources.vod[2]
        let result = reconcile(current: [], removedIDs: [target.id], includeDeleted: false)
        XCTAssertFalse(result.list.contains { $0.id == target.id })
        XCTAssertEqual(result.list.count, BuiltinSources.vod.count - 1)

        let restored = reconcile(current: [], removedIDs: [target.id], includeDeleted: true)
        XCTAssertTrue(restored.list.contains { $0.id == target.id })
        XCTAssertEqual(restored.list.count, BuiltinSources.vod.count)
    }

    func testSecondRunIsIdempotent() {
        let first = reconcile(current: [], removedIDs: [], includeDeleted: false)
        let second = reconcile(current: first.list, removedIDs: [], includeDeleted: false)
        XCTAssertEqual(second.added, 0)
        XCTAssertEqual(second.removed, 0)
        XCTAssertEqual(second.list.count, first.list.count)
    }

    func testUserEditedBuiltinIsNotDuplicated() {
        var edited = BuiltinSources.vod[0]
        edited.name = "我自己的名字"
        edited.api = "https://mirror.example.com/api.php/provide/vod"
        let result = reconcile(current: [edited], removedIDs: [], includeDeleted: false)
        // 改过地址后 ID 仍在目录里，不应被当成失效条目删掉，也不会被重复添加。
        XCTAssertTrue(result.list.contains { $0.id == edited.id })
        XCTAssertEqual(result.removed, 0)
        XCTAssertEqual(result.list.filter { $0.id == edited.id }.count, 1)
    }

    func testStaleBuiltinIsCleanedUp() {
        let stale = VodSource(
            id: "builtin_gone_forever",
            name: "已失效的旧源",
            api: "https://gone.example.com/api.php/provide/vod",
            origin: .builtin
        )
        let result = reconcile(current: [stale], removedIDs: [], includeDeleted: false)
        XCTAssertFalse(result.list.contains { $0.id == stale.id })
        XCTAssertEqual(result.removed, 1)
        XCTAssertEqual(result.list.count, BuiltinSources.vod.count)
    }

    func testManualSourceIsNeverTouched() {
        let manual = VodSource(
            id: "manual_keep",
            name: "我的源",
            api: "https://mine.example.com/api.php/provide/vod",
            origin: .manual
        )
        let result = reconcile(current: [manual], removedIDs: [], includeDeleted: false)
        XCTAssertTrue(result.list.contains { $0.id == manual.id })
        XCTAssertEqual(result.removed, 0)
    }
}
