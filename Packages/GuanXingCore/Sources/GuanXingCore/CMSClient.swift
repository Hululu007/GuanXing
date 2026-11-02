import Foundation

public struct CMSClient: Sendable {
    public let source: VodSource
    private let timeout: TimeInterval

    public init(source: VodSource, timeout: TimeInterval = 15) {
        self.source = source
        self.timeout = timeout
    }

    public func categories() async throws -> [VodCategory] {
        let data = try await request([("ac", "list")])
        return parseCategories(from: data)
    }

    public func latest(page: Int = 1) async throws -> VodPage {
        try await list(typeID: nil, page: page)
    }

    public func list(typeID: String?, page: Int = 1) async throws -> VodPage {
        var items: [(String, String)] = [("ac", "videolist"), ("pg", String(page))]
        if let typeID, !typeID.isEmpty {
            items.append(("t", typeID))
        }
        let data = try await request(items)
        return try parsePage(from: data, page: page)
    }

    public func search(keyword: String, page: Int = 1, maxPages: Int = 3) async throws -> [VodItem] {
        var allItems: [VodItem] = []
        var seen = Set<String>()
        var currentPage = page
        var pageCount = 1

        repeat {
            let data = try await request([
                ("ac", "videolist"),
                ("wd", keyword),
                ("pg", String(currentPage))
            ])
            let result = try parsePage(from: data, page: currentPage)
            for item in result.items where seen.insert(item.vodID).inserted {
                allItems.append(item)
            }
            pageCount = max(result.pageCount, 1)
            currentPage += 1
            if result.items.isEmpty { break }
        } while currentPage <= min(pageCount, page + maxPages - 1)

        return allItems.filter { item in
            let normalizedKeyword = TextSanitizer.normalizedTitle(keyword)
            let normalizedTitle = TextSanitizer.normalizedTitle(item.name)
            return normalizedTitle.contains(normalizedKeyword) || normalizedKeyword.contains(normalizedTitle)
        }
    }

    public func detail(vodID: String) async throws -> VodDetail {
        let data: Data
        do {
            data = try await request([("ac", "detail"), ("ids", vodID)])
        } catch {
            data = try await request([("ac", "videolist"), ("ids", vodID)])
        }

        var detail = try parseDetail(from: data, vodID: vodID)
        if detail.lines.isEmpty, let detailURL = source.detailURL {
            if let htmlDetail = try? await detailFromHTML(vodID: vodID, detailRoot: detailURL) {
                detail = htmlDetail
            }
        }
        if detail.lines.isEmpty {
            throw GuanXingError.empty("该源没有返回可用播放地址")
        }
        return detail
    }

    public func healthCheck() async -> SourceHealth {
        let start = Date()
        do {
            let data = try await request([("ac", "videolist"), ("pg", "1")], timeout: 8)
            let page = try parsePage(from: data, page: 1)
            let elapsed = Date().timeIntervalSince(start)
            guard !page.items.isEmpty else {
                return SourceHealth(state: .failed, latency: elapsed, message: "接口无影片", checkedAt: Date())
            }
            return SourceHealth(
                state: elapsed > 3.5 ? .slow : .healthy,
                latency: elapsed,
                message: "\(page.total) 部影片",
                checkedAt: Date()
            )
        } catch {
            return SourceHealth(
                state: .failed,
                latency: Date().timeIntervalSince(start),
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                checkedAt: Date()
            )
        }
    }

    private func request(_ items: [(String, String)], timeout: TimeInterval? = nil) async throws -> Data {
        guard let url = URLNormalizer.appendQuery(to: source.api, items: items) else {
            throw GuanXingError.invalidURL(source.api)
        }
        var headers = source.headers
        if headers["Referer"] == nil { headers["Referer"] = source.referer + "/" }
        let (data, _) = try await GuanXingHTTP.get(url, headers: headers, timeout: timeout ?? self.timeout)
        return data
    }

    private func parsePage(from data: Data, page: Int) throws -> VodPage {
        let json: Any
        do {
            json = try JSONC.parse(data)
        } catch {
            let preview = String(data: data.prefix(80), encoding: .utf8) ?? "<二进制>"
            throw GuanXingError.decode("接口未返回 JSON（\(preview)）")
        }
        guard let root = json as? [String: Any] else {
            throw GuanXingError.decode("接口根节点不是对象")
        }
        let rawList = LooseValue.array(root["list"]) ?? LooseValue.array(root["data"]) ?? []
        let items = rawList.compactMap { parseItem($0) }
        return VodPage(
            items: items,
            page: LooseValue.int(root["page"]) ?? page,
            pageCount: LooseValue.int(root["pagecount"]) ?? max(1, page),
            total: LooseValue.int(root["total"]) ?? items.count
        )
    }

    private func parseCategories(from data: Data) -> [VodCategory] {
        guard let json = try? JSONC.parse(data),
              let root = json as? [String: Any] else { return [] }
        let raw = LooseValue.array(root["class"]) ?? LooseValue.array(root["classes"]) ?? []
        return raw.compactMap { value in
            guard let dict = value as? [String: Any],
                  let id = LooseValue.string(dict["type_id"]),
                  let name = LooseValue.string(dict["type_name"]) else { return nil }
            return VodCategory(id: id, name: name, parentID: LooseValue.string(dict["type_pid"]))
        }
    }

    private func parseItem(_ value: Any) -> VodItem? {
        guard let dict = value as? [String: Any],
              let vodID = LooseValue.string(dict["vod_id"]),
              let name = LooseValue.string(dict["vod_name"]) else { return nil }
        return VodItem(
            sourceID: source.id,
            sourceName: source.name,
            vodID: vodID,
            name: name,
            pic: LooseValue.string(dict["vod_pic"]) ?? LooseValue.string(dict["vod_pic_thumb"]),
            remarks: LooseValue.string(dict["vod_remarks"]),
            year: LooseValue.string(dict["vod_year"]),
            area: LooseValue.string(dict["vod_area"]),
            typeName: LooseValue.string(dict["type_name"]),
            score: LooseValue.string(dict["vod_score"]),
            tag: LooseValue.string(dict["vod_tag"])
        )
    }

    private func parseDetail(from data: Data, vodID: String) throws -> VodDetail {
        guard let json = try? JSONC.parse(data),
              let root = json as? [String: Any],
              let rawList = LooseValue.array(root["list"]),
              let first = rawList.first as? [String: Any] else {
            throw GuanXingError.decode("详情数据为空")
        }
        guard let item = parseItem(first) else {
            throw GuanXingError.decode("详情缺少影片信息")
        }
        let from = LooseValue.string(first["vod_play_from"]) ?? ""
        let playURL = LooseValue.string(first["vod_play_url"]) ?? ""
        let episodeURL = LooseValue.string(first["vod_play_url_1"]) ?? ""
        let lines = parseLines(from: from, playURL: playURL.isEmpty ? episodeURL : playURL)
        return VodDetail(
            item: item,
            content: TextSanitizer.concise(LooseValue.string(first["vod_content"]) ?? LooseValue.string(first["vod_blurb"]), limit: 1200),
            director: LooseValue.string(first["vod_director"]),
            actor: LooseValue.string(first["vod_actor"]),
            lines: lines
        )
    }

    private func parseLines(from: String, playURL: String) -> [PlayLine] {
        let names = from.components(separatedBy: "$$$")
        let groups = playURL.components(separatedBy: "$$$")
        var output: [PlayLine] = []

        for (index, group) in groups.enumerated() {
            let episodes = group.components(separatedBy: "#").compactMap { raw -> Episode? in
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }
                let parts = value.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
                let title: String
                let url: String
                if parts.count == 2 {
                    title = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                    url = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    title = "第 \(index + 1) 集"
                    url = value
                }
                guard !url.isEmpty, url.lowercased() != "null" else { return nil }
                return Episode(name: title.isEmpty ? "正片" : title, url: url)
            }
            guard !episodes.isEmpty else { continue }
            let rawName = index < names.count ? names[index] : "线路 \(index + 1)"
            let displayName = rawName
                .replacingOccurrences(of: "\\", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            output.append(PlayLine(name: displayName.isEmpty ? "线路 \(index + 1)" : displayName, episodes: episodes))
        }
        return output
    }

    private func detailFromHTML(vodID: String, detailRoot: String) async throws -> VodDetail? {
        let origin = URLNormalizer.origin(of: detailRoot) ?? detailRoot
        let candidates = [
            "\(origin)/index.php/vod/detail/id/\(vodID).html",
            "\(origin)/detail/\(vodID).html",
            "\(origin)/voddetail/\(vodID).html"
        ]
        for candidate in candidates {
            guard let html = try? await GuanXingHTTP.getText(candidate, headers: source.headers, timeout: 12) else {
                continue
            }
            guard let playURL = extractPlayURL(fromHTML: html) else { continue }
            let plain = TextSanitizer.plainText(fromHTML: html)
            let title = extractTitle(fromHTML: html) ?? "影片 \(vodID)"
            let item = VodItem(
                sourceID: source.id,
                sourceName: source.name,
                vodID: vodID,
                name: title
            )
            return VodDetail(
                item: item,
                content: TextSanitizer.concise(plain, limit: 1200),
                lines: parseLines(from: "默认线路", playURL: playURL)
            )
        }
        return nil
    }

    private func extractPlayURL(fromHTML html: String) -> String? {
        let patterns = [
            #""url"\s*:\s*"([^"]+)""#,
            #"player_aaaa\s*=\s*\{(.*?)\}"#,
            #"https?://[^\s"'<>\\]+?\.m3u8[^\s"'<>\\]*"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
                continue
            }
            let source = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: source.length)) {
                let candidate: String
                if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                    candidate = source.substring(with: match.range(at: 1))
                        .replacingOccurrences(of: "\\/", with: "/")
                } else {
                    candidate = source.substring(with: match.range)
                }
                if candidate.contains("m3u8") || candidate.contains(".mp4") {
                    return candidate.replacingOccurrences(of: "\\/", with: "/")
                }
            }
        }
        return nil
    }

    private func extractTitle(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title>([^<]+)</title>"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)) else {
            return nil
        }
        let title = (html as NSString).substring(with: match.range(at: 1))
        return TextSanitizer.plainText(fromHTML: title)
            .replacingOccurrences(of: "- 在线观看", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum SearchService {
    /// 串行版搜索：等所有源都结束后一次性返回。
    /// App 界面请用 `stream`，能边搜边出结果。
    public static func search(
        keyword: String,
        sources: [VodSource],
        limitPerSource: Int = 40
    ) async -> (items: [VodItem], outcomes: [SearchOutcome]) {
        var raw: [SearchOutcome] = []
        for await outcome in stream(keyword: keyword, sources: sources, limitPerSource: limitPerSource) {
            raw.append(outcome)
        }
        return aggregate(raw, keyword: keyword)
    }

    /// 逐个源流式返回结果，哪个源先结束先报告。
    public static func stream(
        keyword: String,
        sources: [VodSource],
        limitPerSource: Int = 40
    ) -> AsyncStream<SearchOutcome> {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let targets = sources.filter { $0.isEnabled && $0.isSearchable && !$0.isAdult }
        guard !keyword.isEmpty else { return AsyncStream { $0.finish() } }

        return AsyncStream { continuation in
            let worker = Task {
                await withTaskGroup(of: SearchOutcome.self) { group in
                    for source in targets {
                        group.addTask {
                            await searchOne(source: source, keyword: keyword, limit: limitPerSource)
                        }
                    }
                    for await outcome in group {
                        continuation.yield(outcome)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    static func searchOne(source: VodSource, keyword: String, limit: Int) async -> SearchOutcome {
        let start = Date()
        do {
            let items = try await SourceClient(source: source, timeout: 12).search(keyword: keyword)
            return SearchOutcome(
                source: source,
                items: Array(items.prefix(limit)),
                elapsed: Date().timeIntervalSince(start)
            )
        } catch {
            return SearchOutcome(
                source: source,
                items: [],
                error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                elapsed: Date().timeIntervalSince(start)
            )
        }
    }

    /// 把单个源的结果合并成去重、排序后的平铺列表。
    public static func aggregate(
        _ raw: [SearchOutcome],
        keyword: String
    ) -> (items: [VodItem], outcomes: [SearchOutcome]) {
        let outcomes = raw.sorted { lhs, rhs in
            if lhs.items.isEmpty != rhs.items.isEmpty { return !lhs.items.isEmpty }
            return lhs.elapsed < rhs.elapsed
        }
        var items: [VodItem] = []
        var seen = Set<String>()
        for outcome in outcomes {
            for item in outcome.items where seen.insert(item.id).inserted {
                items.append(item)
            }
        }
        let keywordNormalized = TextSanitizer.normalizedTitle(keyword)
        items.sort { lhs, rhs in
            let lhsExact = TextSanitizer.normalizedTitle(lhs.name) == keywordNormalized
            let rhsExact = TextSanitizer.normalizedTitle(rhs.name) == keywordNormalized
            if lhsExact != rhsExact { return lhsExact }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return (items, outcomes)
    }
}

/// 把同一部片在不同源的结果合并成一条，借鉴 DpadTV 的“按标题分组 + 源数量”展示。
public struct TitleGroup: Identifiable, Sendable {
    public var title: String
    public var items: [VodItem]

    public var id: String { TextSanitizer.normalizedTitle(title) }
    public var sourceCount: Int { Set(items.map(\.sourceID)).count }
    public var primary: VodItem? {
        items.max { lhs, rhs in
            (Double(lhs.score ?? "") ?? 0) < (Double(rhs.score ?? "") ?? 0)
        } ?? items.first
    }

    public init(title: String, items: [VodItem]) {
        self.title = title
        self.items = items
    }
}

public enum TitleGrouper {
    /// 片名归一化后相同的条目合并，组内保留搜索结果原有顺序。
    public static func group(_ items: [VodItem]) -> [TitleGroup] {
        var order: [String] = []
        var buckets: [String: [VodItem]] = [:]
        for item in items {
            let key = TextSanitizer.normalizedTitle(item.name)
            guard !key.isEmpty else { continue }
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(item)
        }
        return order.compactMap { key in
            guard let list = buckets[key], let first = list.first else { return nil }
            return TitleGroup(title: first.name, items: list)
        }
        .sorted { lhs, rhs in
            if lhs.sourceCount != rhs.sourceCount { return lhs.sourceCount > rhs.sourceCount }
            if lhs.items.count != rhs.items.count { return lhs.items.count > rhs.items.count }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
