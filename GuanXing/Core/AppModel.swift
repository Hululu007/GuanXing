import Foundation
import Observation
import GuanXingCore

@MainActor
@Observable
final class AppModel {
    var sources: [VodSource]
    var liveSources: [LiveSource]
    var parsers: [ParseEndpoint]
    var favorites: [FavoriteItem]
    var history: [HistoryEntry]
    var favoriteChannels: [FavoriteChannel]
    var settings: AppSettings
    var health: [String: SourceHealth]
    var repositoryURLs: [String]

    var isReady = false
    var importMessage: ImportAlert?
    var isRefreshingHealth = false

    private let store: PersistenceStore

    init(store: PersistenceStore = PersistenceStore()) {
        self.store = store
        let snapshot = store.load()
        self.sources = snapshot.sources
        self.liveSources = snapshot.liveSources
        self.parsers = snapshot.parsers
        self.favorites = snapshot.favorites
        self.history = snapshot.history
        self.favoriteChannels = snapshot.favoriteChannels
        self.settings = snapshot.settings
        self.health = snapshot.health
        self.repositoryURLs = snapshot.repositoryURLs
        self.isReady = true
    }

    var enabledSources: [VodSource] {
        sources.filter { $0.isEnabled && !$0.isAdult }
    }

    var enabledLiveSources: [LiveSource] {
        liveSources.filter(\.isEnabled)
    }

    func save() {
        store.save(PersistenceStore.Snapshot(
            sources: sources,
            liveSources: liveSources,
            parsers: parsers,
            favorites: favorites,
            history: history,
            favoriteChannels: favoriteChannels,
            settings: settings,
            health: health,
            repositoryURLs: repositoryURLs
        ))
    }

    func toggleSource(_ source: VodSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index].isEnabled.toggle()
        save()
    }

    func toggleLiveSource(_ source: LiveSource) {
        guard let index = liveSources.firstIndex(where: { $0.id == source.id }) else { return }
        liveSources[index].isEnabled.toggle()
        save()
    }

    func addSource(name: String, api: String, detail: String? = nil) throws {
        guard let normalized = URLNormalizer.normalized(api) else {
            throw ImportError.invalidURL
        }
        if sources.contains(where: { $0.api == normalized }) {
            throw ImportError.duplicate
        }
        sources.append(VodSource(
            id: StableID.make("manual", normalized),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? URLNormalizer.host(of: normalized) : name,
            api: normalized,
            detailURL: URLNormalizer.normalized(detail),
            origin: .manual
        ))
        save()
    }

    func addLiveSource(name: String, url: String, epg: String? = nil) throws {
        guard let normalized = URLNormalizer.normalized(url, trimTrailingSlash: false) else {
            throw ImportError.invalidURL
        }
        if liveSources.contains(where: { $0.url == normalized }) {
            throw ImportError.duplicate
        }
        liveSources.append(LiveSource(
            id: StableID.make("live", normalized),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? URLNormalizer.host(of: normalized) : name,
            url: normalized,
            epg: URLNormalizer.normalized(epg, trimTrailingSlash: false),
            origin: .manual
        ))
        save()
    }

    func importLocalPlaylist(text: String, name: String) throws {
        guard let format = LivePlaylist.detect(text) else {
            throw GuanXingError.decode("文件不是 M3U / TXT / JSON 直播列表")
        }
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = root.appendingPathComponent("GuanXing/Playlists", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileStem = StableID.make("playlist", text)
        let fileURL = folder.appendingPathComponent(fileStem + "." + format.fileExtension)
        if liveSources.contains(where: { $0.url == fileURL.absoluteString }) {
            throw ImportError.duplicate
        }
        let sourceID = StableID.make("live", fileURL.absoluteString)
        let sourceTitle = displayName.isEmpty ? "本地列表" : displayName
        let result = LivePlaylist.parse(
            text,
            sourceID: sourceID,
            sourceName: sourceTitle
        )
        guard let channels = result?.channels, !channels.isEmpty else {
            throw ImportError.noUsableSource
        }
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let source = LiveSource(
            id: sourceID,
            name: sourceTitle,
            url: fileURL.absoluteString,
            origin: .manual
        )
        liveSources.append(source)
        save()
        var detail = [format.title]
        if let alternates = result?.alternateURLCount, alternates > 0 {
            detail.append("忽略 \(alternates) 个备用地址")
        }
        if let skipped = result?.skippedLineCount, skipped > 0 {
            detail.append("跳过 \(skipped) 行")
        }
        importMessage = ImportAlert(
            title: "已导入",
            message: "本地直播列表已加入源管理，共 \(channels.count) 个频道。",
            detail: detail.joined(separator: " · ")
        )
    }

    func deleteSource(_ source: VodSource) {
        sources.removeAll { $0.id == source.id }
        health[source.id] = nil
        if BuiltinSources.vod.contains(where: { $0.id == source.id }),
           !settings.removedBuiltinSourceIDs.contains(source.id) {
            settings.removedBuiltinSourceIDs.append(source.id)
        }
        save()
    }

    /// 修改已有源的名字与接口地址。内置源也能改成其他可用接口，
    /// 改完后仍显示为内置来源，但不会被“更新内置源”覆盖。
    func updateSource(
        id: String,
        name: String,
        api: String,
        detail: String? = nil
    ) throws {
        guard let index = sources.firstIndex(where: { $0.id == id }) else {
            throw ImportError.noUsableSource
        }
        guard let normalized = URLNormalizer.normalized(api) else {
            throw ImportError.invalidURL
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sources[index].name = trimmedName.isEmpty ? URLNormalizer.host(of: normalized) : trimmedName
        sources[index].api = normalized
        sources[index].detailURL = URLNormalizer.normalized(detail)
        // 手动改成别的地址后，原来的私有协议绑定就不再适用
        sources[index].spider = nil
        save()
    }

    /// 把内置源恢复成目录里的官方名字与地址。
    @discardableResult
    func restoreBuiltinSource(id: String) -> Bool {
        guard let canonical = BuiltinSources.canonical(id: id) else { return false }
        guard let index = sources.firstIndex(where: { $0.id == id }) else {
            sources.append(canonical)
            save()
            return true
        }
        sources[index].name = canonical.name
        sources[index].api = canonical.api
        sources[index].detailURL = canonical.detailURL
        sources[index].isAdult = canonical.isAdult
        sources[index].spider = canonical.spider
        save()
        return true
    }

    /// 内置源是否被改过名字或地址。
    func isBuiltinSourceModified(_ source: VodSource) -> Bool {
        guard let canonical = BuiltinSources.canonical(id: source.id) else { return false }
        return source.api.lowercased() != canonical.api.lowercased() || source.name != canonical.name
    }

    func deleteLiveSource(_ source: LiveSource) {
        liveSources.removeAll { $0.id == source.id }
        if source.url.hasPrefix("file://"), let url = URL(string: source.url) {
            try? FileManager.default.removeItem(at: url)
        }
        // 内置直播源删除后同样记一笔，避免「更新内置源」又把它加回来。
        if BuiltinSources.live.contains(where: { $0.id == source.id }),
           !settings.removedBuiltinSourceIDs.contains(source.id) {
            settings.removedBuiltinSourceIDs.append(source.id)
        }
        save()
    }

    func moveSources(from offsets: IndexSet, to destination: Int) {
        sources.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    /// 内置源目录是否有比当前更新的一版。
    var hasBuiltinCatalogUpdate: Bool {
        settings.builtinCatalogVersion != BuiltinSources.catalogVersion
    }

    var builtinSourceCount: Int {
        sources.filter { $0.origin == .builtin }.count
    }

    /// 把内置源恢复成目录里的最新一版。
    /// - Parameter includeDeleted: 为 true 时连之前手动删掉的内置源一起恢复。
    /// - Returns: 新增与被移出的条数，用于提示。
    @discardableResult
    func restoreBuiltinSources(includeDeleted: Bool = false) -> (added: Int, removed: Int) {
        if includeDeleted {
            settings.removedBuiltinSourceIDs.removeAll()
        }
        let allowed = Set(settings.removedBuiltinSourceIDs)

        var added = 0
        for source in BuiltinSources.vod where !allowed.contains(source.id) {
            guard !BuiltinSources.isDuplicate(source, in: sources) else { continue }
            sources.append(source)
            added += 1
        }

        // 目录里已经被剔除的内置源（仍标记为 builtin）一并移出，避免留下失效条目。
        let catalogIDs = Set(BuiltinSources.vod.map(\.id))
        let catalogAPIs = Set(BuiltinSources.vod.map { $0.api.lowercased() })
        let stale = sources.filter { source in
            guard source.origin == .builtin else { return false }
            return !catalogIDs.contains(source.id) && !catalogAPIs.contains(source.api.lowercased())
        }
        for source in stale {
            sources.removeAll { $0.id == source.id }
            health[source.id] = nil
        }

        var liveExisting = Set(liveSources.map(\.url))
        for source in BuiltinSources.live where !allowed.contains(source.id) {
            guard !liveExisting.contains(source.url) else { continue }
            liveSources.append(source)
            liveExisting.insert(source.url)
        }
        // 目录里下线的内置直播源一并移出，避免留下一打开就报错的条目。
        let liveCatalogIDs = Set(BuiltinSources.live.map(\.id))
        liveSources.removeAll { source in
            source.origin == .builtin
                && !liveCatalogIDs.contains(source.id)
                && !source.url.hasPrefix("file://")
        }

        settings.builtinCatalogVersion = BuiltinSources.catalogVersion
        save()
        return (added, stale.count)
    }

    func resetAllData() {
        sources = BuiltinSources.vod
        liveSources = BuiltinSources.live
        parsers = []
        favorites = []
        history = []
        favoriteChannels = []
        health = [:]
        repositoryURLs = []
        settings = AppSettings()
        save()
    }

    /// 恢复出厂：清空所有数据，内置源回到目录最新版。
    func factoryReset() {
        resetAllData()
        settings.removedBuiltinSourceIDs = []
        settings.builtinCatalogVersion = BuiltinSources.catalogVersion
        save()
    }

    func source(for id: String) -> VodSource? {
        sources.first { $0.id == id }
    }

    func merge(_ config: ImportedConfig) {
        let result = applyMerge(config)
        save()
        var detail = config.report.summary
        if result.duplicates > 0 {
            detail += "\n已跳过 \(result.duplicates) 个重复源"
            if !result.duplicateNames.isEmpty {
                detail += "：" + result.duplicateNames.prefix(6).joined(separator: "、")
                if result.duplicateNames.count > 6 { detail += " 等" }
            }
        }
        importMessage = ImportAlert(
            title: "导入完成",
            message: "\(config.report.format)：新增 \(result.addedSources) 个点播源、\(result.addedLives) 个直播源"
                + (config.report.skipped > 0 ? "，跳过 \(config.report.skipped) 条" : ""),
            detail: detail
        )
    }

    /// 真正做合并的部分：按指纹去重，不落盘。
    @discardableResult
    func applyMerge(_ config: ImportedConfig) -> (addedSources: Int, addedLives: Int, duplicates: Int, duplicateNames: [String]) {
        let merged = SourceDeduplicator.merge(incoming: config.sources, existing: sources)
        sources.append(contentsOf: merged.added)

        let liveURLs = Set(liveSources.map(\.url))
        var addedLives = 0
        for source in config.liveSources where !liveURLs.contains(source.url) {
            liveSources.append(source)
            addedLives += 1
        }

        let parserURLs = Set(parsers.map(\.url))
        for parser in config.parsers where !parserURLs.contains(parser.url) {
            parsers.append(parser)
        }
        for url in config.repositoryURLs where !repositoryURLs.contains(url) {
            repositoryURLs.append(url)
        }
        return (merged.added.count, addedLives, merged.duplicates, merged.duplicateNames)
    }

    func importConfig(text: String, name: String? = nil) throws {
        let config = try ImportedConfigParser.parse(text: text, fallbackName: name)
        guard !config.sources.isEmpty || !config.liveSources.isEmpty else {
            throw ImportError.noUsableSource
        }
        merge(config)
    }

    func importRemote(urlString: String) async {
        do {
            let config = try await ConfigLoader.load(urlString: urlString)
            guard !config.sources.isEmpty || !config.liveSources.isEmpty else {
                throw ImportError.noUsableSource
            }
            merge(config)
        } catch {
            importMessage = ImportAlert(
                title: "导入失败",
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                detail: "请检查地址，或确认配置为 TVBox / LibreTV JSON 格式。"
            )
        }
    }

    /// 批量导入：一次吃下多个单仓 / 多仓地址。
    ///
    /// - 多仓（urls 数组）会自动展开成里面的每个单仓再拉一遍，最多两层。
    /// - 全部结果按指纹去重，重复的不会进列表。
    /// - 单个地址失败不影响其它地址，最后汇总报告。
    func importBatch(_ rawText: String) async {
        let candidates = rawText
            .components(separatedBy: CharacterSet(charactersIn: "\n\r,，;； \t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !candidates.isEmpty else {
            importMessage = ImportAlert(title: "没有可导入的地址", message: "每行填一个配置地址，或直接粘贴整份 multi-repo JSON。")
            return
        }

        // 直接贴一整份多仓 JSON 的情况
        if candidates.count == 1, candidates[0].hasPrefix("{") {
            do {
                try importConfig(text: candidates[0], name: "多仓配置")
            } catch {
                importMessage = ImportAlert(
                    title: "解析失败",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
            return
        }

        var totalAdded = 0
        var totalDuplicates = 0
        var totalSkipped = 0
        var failed: [String] = []
        var duplicateNames: [String] = []
        var expandedCount = 0

        // 第一层：用户给的单仓 / 多仓
        for url in candidates {
            let level1 = await loadLoose(url)
            guard let config = level1 else {
                failed.append(URLNormalizer.host(of: url))
                continue
            }

            // 如果是多仓，展开后继续拉
            if config.sources.isEmpty, !config.repositoryURLs.isEmpty {
                for repoURL in config.repositoryURLs {
                    expandedCount += 1
                    guard let sub = await loadLoose(repoURL) else {
                        failed.append(URLNormalizer.host(of: repoURL))
                        continue
                    }
                    let merged = applyMerge(sub)
                    totalAdded += merged.addedSources + merged.addedLives
                    totalDuplicates += merged.duplicates
                    duplicateNames.append(contentsOf: merged.duplicateNames)
                    totalSkipped += sub.report.skipped
                }
                // 多仓本身也记进仓库列表，方便以后刷新
                for repoURL in config.repositoryURLs where !repositoryURLs.contains(repoURL) {
                    repositoryURLs.append(repoURL)
                }
                continue
            }

            let merged = applyMerge(config)
            totalAdded += merged.addedSources + merged.addedLives
            totalDuplicates += merged.duplicates
            duplicateNames.append(contentsOf: merged.duplicateNames)
            totalSkipped += config.report.skipped
        }

        save()

        var lines: [String] = []
        lines.append("共处理 \(candidates.count) 个地址" + (expandedCount > 0 ? "，展开 \(expandedCount) 个多仓子项" : ""))
        lines.append("新增 \(totalAdded) 个源")
        if totalDuplicates > 0 {
            lines.append("跳过重复 \(totalDuplicates) 个")
            if !duplicateNames.isEmpty {
                lines.append("重复项：" + duplicateNames.prefix(8).joined(separator: "、"))
            }
        }
        if totalSkipped > 0 { lines.append("解析时跳过 \(totalSkipped) 条不支持的类型") }
        if !failed.isEmpty {
            lines.append("无法访问：" + failed.prefix(8).joined(separator: "、") + (failed.count > 8 ? " 等 \(failed.count) 个" : ""))
        }

        importMessage = ImportAlert(
            title: totalAdded > 0 ? "批量导入完成" : "没有新增源",
            message: lines.joined(separator: "\n")
        )
    }

    /// 拉一个地址，不管它是单仓还是多仓，都尽量解析出能用的部分。
    private func loadLoose(_ url: String) async -> ImportedConfig? {
        guard let normalized = URLNormalizer.normalized(url, trimTrailingSlash: false) else { return nil }
        if let config = try? await ConfigLoader.load(urlString: normalized) {
            return config
        }
        // 退一步：直接当裸 JSON 抓，支持多仓 / 带注释 / 图片藏配置
        guard let text = try? await GuanXingHTTP.getText(normalized, timeout: 15) else { return nil }
        return try? ImportedConfigParser.parse(text: text, fallbackName: URLNormalizer.host(of: normalized))
    }

    func checkAllHealth() async {
        guard !isRefreshingHealth else { return }
        isRefreshingHealth = true
        defer { isRefreshingHealth = false }
        let snapshot = enabledSources
        for source in snapshot {
            health[source.id] = SourceHealth(state: .checking)
        }
        await withTaskGroup(of: (String, SourceHealth).self) { group in
            for source in snapshot {
                group.addTask {
                    (source.id, await SourceClient(source: source, timeout: 10).healthCheck())
                }
            }
            for await (id, result) in group {
                health[id] = result
            }
        }
        save()
    }

    func isFavorite(_ item: VodItem) -> Bool {
        favorites.contains { $0.item.id == item.id }
    }

    func toggleFavorite(_ item: VodItem) {
        if let index = favorites.firstIndex(where: { $0.item.id == item.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(FavoriteItem(item: item), at: 0)
        }
        save()
    }

    func isFavoriteChannel(_ channel: LiveChannel) -> Bool {
        favoriteChannels.contains { $0.channel.id == channel.id }
    }

    func toggleFavoriteChannel(_ channel: LiveChannel) {
        if let index = favoriteChannels.firstIndex(where: { $0.channel.id == channel.id }) {
            favoriteChannels.remove(at: index)
        } else {
            favoriteChannels.insert(FavoriteChannel(channel: channel), at: 0)
        }
        save()
    }

    func recordProgress(
        item: VodItem,
        line: PlayLine,
        episodeIndex: Int,
        position: Double,
        duration: Double
    ) {
        guard settings.rememberProgress, duration.isFinite, duration > 0 else { return }
        let episode = line.episodes.indices.contains(episodeIndex) ? line.episodes[episodeIndex] : nil
        let entry = HistoryEntry(
            item: item,
            lineName: line.name,
            episodeIndex: episodeIndex,
            episodeName: episode?.name ?? "第 \(episodeIndex + 1) 集",
            position: position,
            duration: duration,
            updatedAt: Date()
        )
        history.removeAll { $0.item.id == item.id }
        history.insert(entry, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
        save()
    }

    func clearHistory() {
        history.removeAll()
        save()
    }

    func history(for item: VodItem) -> HistoryEntry? {
        history.first { $0.item.id == item.id }
    }

    func setImportAlert(title: String, message: String, detail: String? = nil) {
        importMessage = ImportAlert(title: title, message: message, detail: detail)
    }
}

struct ImportAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var detail: String?
}

enum ImportError: LocalizedError {
    case invalidURL
    case duplicate
    case noUsableSource

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "地址必须以 http:// 或 https:// 开头"
        case .duplicate: return "这个源已经存在"
        case .noUsableSource: return "配置中没有可用的点播或直播源"
        }
    }
}
