import Foundation

public enum ImportedConfigParser {
    public static func parse(text: String, fallbackName: String? = nil) throws -> ImportedConfig {
        let json: Any
        do {
            json = try JSONC.parse(text)
        } catch {
            throw GuanXingError.decode("无法识别订阅格式，请确认是 TVBox / LibreTV JSON，或 M3U / TXT / JSON 直播列表")
        }

        if let object = json as? [String: Any] {
            if object["tvbox"] != nil || object["url"] != nil, object["sites"] == nil,
               let url = LooseValue.string(object["url"]) {
                throw GuanXingError.empty("这是远程仓库索引 \(url)，请先导入该仓库地址")
            }
            return parseObject(object, fallbackName: fallbackName)
        }

        if let array = json as? [Any] {
            return parseArray(array, fallbackName: fallbackName)
        }

        throw GuanXingError.decode("订阅内容既不是对象也不是数组")
    }

    private static func parseObject(_ object: [String: Any], fallbackName: String?) -> ImportedConfig {
        let name = LooseValue.string(object["name"]) ?? fallbackName
        let rawSites = LooseValue.array(object["sites"]) ?? []
        let rawLives = LooseValue.array(object["lives"]) ?? []
        let rawParses = LooseValue.array(object["parses"]) ?? []
        let repositories = extractRepositories(
            object["urls"] ?? object["repos"] ?? object["repositories"] ?? object["jar"]
        )

        var skipped = 0
        var reasons: [String: Int] = [:]
        var sources: [VodSource] = []
        var seenSources = Set<String>()

        for raw in rawSites {
            guard let site = LooseValue.dictionary(raw) else {
                skipped += 1
                reasons["格式错误", default: 0] += 1
                continue
            }
            guard let api = URLNormalizer.normalized(LooseValue.string(site["api"])) else {
                skipped += 1
                reasons["地址无效", default: 0] += 1
                continue
            }
            let siteID = LooseValue.string(site["key"]) ?? URLNormalizer.host(of: api)
            if seenSources.contains(api) { continue }

            let type = LooseValue.int(site["type"]) ?? 1
            let searchable = LooseValue.int(site["searchable"]) ?? 1
            let isAppleCMS = api.lowercased().contains("/api.php/provide/vod")
            if type == 3 || type == 4 {
                if !isAppleCMS {
                    skipped += 1
                    reasons["需要 Spider 引擎", default: 0] += 1
                    continue
                }
            } else if type == 0 && !isAppleCMS {
                skipped += 1
                reasons["XML 接口不支持", default: 0] += 1
                continue
            } else if type != 1 && type != 0 && !isAppleCMS {
                skipped += 1
                reasons["不支持的类型", default: 0] += 1
                continue
            }
            if searchable == 0 {
                skipped += 1
                reasons["不可搜索", default: 0] += 1
                continue
            }

            let key = "site_\(sources.count)_\(siteID)"
            let displayName = LooseValue.string(site["name"]) ?? URLNormalizer.host(of: api)
            var headers: [String: String] = [:]
            if let rawHeaders = LooseValue.dictionary(site["headers"]) {
                for (key, value) in rawHeaders {
                    if let value = LooseValue.string(value) {
                        headers[key] = value
                    }
                }
            }
            sources.append(VodSource(
                id: StableID.make("site", key),
                name: displayName,
                api: api,
                detailURL: URLNormalizer.normalized(LooseValue.string(site["detail"])),
                origin: .imported,
                headers: headers
            ))
            seenSources.insert(api)
        }

        var liveSources: [LiveSource] = []
        var seenLives = Set<String>()
        for raw in rawLives {
            guard let live = LooseValue.dictionary(raw) else {
                skipped += 1
                reasons["格式错误", default: 0] += 1
                continue
            }
            let type = LooseValue.int(live["type"]) ?? 0
            guard type == 0 else {
                skipped += 1
                reasons["非 M3U/TXT 直播", default: 0] += 1
                continue
            }
            guard let url = URLNormalizer.normalized(LooseValue.string(live["url"]), trimTrailingSlash: false) else {
                skipped += 1
                reasons["地址无效", default: 0] += 1
                continue
            }
            if seenLives.contains(url) { continue }
            let displayName = LooseValue.string(live["name"]) ?? URLNormalizer.host(of: url)
            liveSources.append(LiveSource(
                id: StableID.make("live", url),
                name: displayName,
                url: url,
                epg: URLNormalizer.normalized(LooseValue.string(live["epg"]), trimTrailingSlash: false),
                origin: .imported
            ))
            seenLives.insert(url)
        }

        if sources.isEmpty && liveSources.isEmpty, let rawSources = LooseValue.array(object["sources"]) {
            let nested = parseArray(rawSources, fallbackName: name)
            var merged = nested
            if let rawLive = LooseValue.array(object["liveSources"]) {
                let liveParsed = parseArray(rawLive, fallbackName: name)
                merged = merge(merged, liveParsed)
            }
            if let rawRepositories = LooseValue.array(object["repositories"]) {
                let repositoryNames = rawRepositories.compactMap { item -> String? in
                    if let url = LooseValue.string(item) { return URLNormalizer.normalized(url) }
                    if let dict = LooseValue.dictionary(item),
                       let url = LooseValue.string(dict["url"]) ?? LooseValue.string(dict["api"]) {
                        return URLNormalizer.normalized(url)
                    }
                    return nil
                }
                merged.repositoryURLs.append(contentsOf: repositoryNames)
            }
            merged.name = name ?? merged.name
            merged.report.format = "LibreTV"
            merged.report.sourceCount = merged.sources.count
            merged.report.liveCount = merged.liveSources.count
            return merged
        }

        var parsers: [ParseEndpoint] = []
        for raw in rawParses {
            guard let parser = LooseValue.dictionary(raw),
                  let url = URLNormalizer.normalized(LooseValue.string(parser["url"]), trimTrailingSlash: false) else {
                continue
            }
            parsers.append(ParseEndpoint(
                id: StableID.make("parse", url),
                name: LooseValue.string(parser["name"]) ?? URLNormalizer.host(of: url),
                url: url,
                type: LooseValue.int(parser["type"]) ?? 1
            ))
        }

        if let rawSources = LooseValue.array(object["sources"]) {
            let legacy = parseArray(rawSources, fallbackName: name)
            for source in legacy.sources where !seenSources.contains(source.api) {
                sources.append(source)
                seenSources.insert(source.api)
            }
        }
        if let rawLive = LooseValue.array(object["liveSources"]) {
            let legacy = parseArray(rawLive, fallbackName: name)
            for source in legacy.liveSources where !seenLives.contains(source.url) {
                liveSources.append(source)
                seenLives.insert(source.url)
            }
        }

        let format: String
        if object["sites"] != nil || object["lives"] != nil {
            format = "TVBox"
        } else if object["sources"] != nil || object["liveSources"] != nil {
            format = "LibreTV"
        } else {
            format = "通用 JSON"
        }

        return ImportedConfig(
            name: name,
            sources: sources,
            liveSources: liveSources,
            parsers: parsers,
            repositoryURLs: Array(Set(repositories)).sorted(),
            report: ImportReport(
                format: format,
                sourceCount: sources.count,
                liveCount: liveSources.count,
                parserCount: parsers.count,
                skipped: skipped,
                skippedReasons: reasons,
                repositoryCount: repositories.count
            )
        )
    }

    private static func parseArray(_ array: [Any], fallbackName: String?) -> ImportedConfig {
        let allObjects = array.allSatisfy { $0 is [String: Any] }
        let isCatalog = allObjects && array.contains { item in
            guard let dict = item as? [String: Any] else { return false }
            return dict["baseUrl"] != nil
        }

        var sources: [VodSource] = []
        var lives: [LiveSource] = []
        var skipped = 0
        var reasons: [String: Int] = [:]
        var seen = Set<String>()

        for raw in array {
            guard let item = raw as? [String: Any] else {
                skipped += 1
                reasons["格式错误", default: 0] += 1
                continue
            }
            if LooseValue.bool(item["enabled"]) == false {
                skipped += 1
                reasons["已停用", default: 0] += 1
                continue
            }
            let apiValue = LooseValue.string(item["baseUrl"]) ?? LooseValue.string(item["url"]) ?? LooseValue.string(item["api"])
            guard let url = URLNormalizer.normalized(apiValue, trimTrailingSlash: !isM3U(item)) else {
                skipped += 1
                reasons["地址无效", default: 0] += 1
                continue
            }
            if seen.contains(url) { continue }
            if isM3U(item) || isLiveURL(url) {
                lives.append(LiveSource(
                    id: StableID.make("live", url),
                    name: LooseValue.string(item["name"]) ?? URLNormalizer.host(of: url),
                    url: url,
                    epg: URLNormalizer.normalized(LooseValue.string(item["epg"]), trimTrailingSlash: false),
                    origin: .imported
                ))
            } else {
                sources.append(VodSource(
                    id: StableID.make("site", url),
                    name: LooseValue.string(item["name"]) ?? URLNormalizer.host(of: url),
                    api: url,
                    detailURL: URLNormalizer.normalized(LooseValue.string(item["detail"])),
                    origin: .imported,
                    isAdult: LooseValue.bool(item["isAdult"]) ?? false
                ))
            }
            seen.insert(url)
        }

        let format = isCatalog ? "接口目录" : "LibreTV-SourceList"
        return ImportedConfig(
            name: fallbackName,
            sources: sources,
            liveSources: lives,
            report: ImportReport(
                format: format,
                sourceCount: sources.count,
                liveCount: lives.count,
                skipped: skipped,
                skippedReasons: reasons
            )
        )
    }

    private static func isM3U(_ item: [String: Any]) -> Bool {
        if LooseValue.int(item["type"]) == 1 { return true }
        if let raw = LooseValue.string(item["url"]) ?? LooseValue.string(item["baseUrl"]) {
            return isLiveURL(raw)
        }
        return false
    }

    private static func isLiveURL(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if lower.contains(".m3u") || lower.contains("/live/") || lower.contains("iptv") { return true }
        if lower.contains(".txt"), lower.contains("live") || lower.contains("iptv") { return true }
        return false
    }

    private static func extractRepositories(_ raw: Any?) -> [String] {
        var output: [String] = []
        if let list = raw as? [Any] {
            for item in list {
                if let url = URLNormalizer.normalized(LooseValue.string(item), trimTrailingSlash: false) {
                    output.append(url)
                } else if let dict = item as? [String: Any],
                          let url = URLNormalizer.normalized(LooseValue.string(dict["url"]) ?? LooseValue.string(dict["api"]), trimTrailingSlash: false) {
                    output.append(url)
                }
            }
        } else if let url = URLNormalizer.normalized(LooseValue.string(raw), trimTrailingSlash: false) {
            output.append(url)
        }
        return output
    }

    private static func merge(_ first: ImportedConfig, _ second: ImportedConfig) -> ImportedConfig {
        var sources = first.sources
        var existing = Set(sources.map(\.api))
        for source in second.sources where !existing.contains(source.api) {
            sources.append(source)
            existing.insert(source.api)
        }
        var lives = first.liveSources
        var existingLives = Set(lives.map(\.url))
        for live in second.liveSources where !existingLives.contains(live.url) {
            lives.append(live)
            existingLives.insert(live.url)
        }
        return ImportedConfig(
            name: first.name ?? second.name,
            sources: sources,
            liveSources: lives,
            parsers: first.parsers + second.parsers,
            repositoryURLs: Array(Set(first.repositoryURLs + second.repositoryURLs)),
            report: ImportReport(
                format: "混合订阅",
                sourceCount: sources.count,
                liveCount: lives.count,
                parserCount: first.parsers.count + second.parsers.count,
                skipped: first.report.skipped + second.report.skipped,
                skippedReasons: first.report.skippedReasons.merging(second.report.skippedReasons) { $0 + $1 }
            )
        )
    }
}

public enum SourceImportType: String, Sendable {
    case tvbox
    case libretv
    case sourceCatalog
    case m3u
    case repository

    public var title: String {
        switch self {
        case .tvbox: return "TVBox 配置"
        case .libretv: return "LibreTV 源列表"
        case .sourceCatalog: return "接口目录"
        case .m3u: return "直播列表"
        case .repository: return "远程仓库"
        }
    }
}

public enum ConfigLoader {
    public static func load(urlString: String, timeout: TimeInterval = 18) async throws -> ImportedConfig {
        guard let url = URLNormalizer.normalized(urlString, trimTrailingSlash: false) else {
            throw GuanXingError.invalidURL(urlString)
        }
        let (data, response) = try await GuanXingHTTP.get(url, timeout: timeout)
        let text = TextDecoder.decode(data) ?? ""

        _ = response
        if let format = LivePlaylist.detect(text) {
            let sourceID = StableID.make("live", url)
            let name = URLNormalizer.host(of: url)
            let result = LivePlaylist.parse(text, sourceID: sourceID, sourceName: name)
            let count = result?.channels.count ?? 0
            var messages = ["订阅含 \(count) 个频道"]
            if let alternates = result?.alternateURLCount, alternates > 0 {
                messages.append("忽略 \(alternates) 个备用地址")
            }
            return ImportedConfig(
                name: name,
                sources: [],
                liveSources: [LiveSource(id: sourceID, name: name, url: url, origin: .imported)],
                report: ImportReport(
                    format: format.title,
                    sourceCount: 0,
                    liveCount: 1,
                    messages: messages
                )
            )
        }
        return try ImportedConfigParser.parse(text: text, fallbackName: URLNormalizer.host(of: url))
    }

    public static func looksLikeM3U(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("#EXTM3U") || trimmed.hasPrefix("#EXTINF")
    }

    /// 是否为可直接导入的直播列表（M3U / TXT / JSON 频道表）。
    public static func looksLikeLivePlaylist(_ text: String) -> Bool {
        LivePlaylist.detect(text) != nil
    }
}
