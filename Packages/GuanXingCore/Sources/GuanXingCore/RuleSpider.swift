import Foundation

/// TVBox 规则型 Spider（XBPQ / HBPQ / XYQHiker 一类）的纯 Swift 实现。
///
/// 这类源不跑 jar，也不跑 js，而是把「从 HTML 里怎么取字段」写成一套中文 DSL：
///
///     "数组":   "class=\"stui-vodlist__box\"&&</a"
///     "标题":   "title=\"&&\""
///     "链接":   "href=\"&&\""
///
/// 语法只有四件事：
/// - `A&&B`  取 A 之后、B 之前的内容（A 或 B 为空表示取到头 / 从头）
/// - `X||Y`  依次尝试，前面取不到才用后面
/// - `j:path` 走 JSON 路径，`a.b[0].c` 形式
/// - `✚`     把多段拼起来，例如 `https://x.com/✚j:id✚.html`
///
/// 因为全部是字符串匹配和 JSON 取值，可以在 iOS 上原样运行，不需要 JVM。
public struct RuleSpider: Sendable {
    public let config: RuleConfig
    public let source: VodSource

    public init(config: RuleConfig, source: VodSource) {
        self.config = config
        self.source = source
    }

    // MARK: - 首页 / 分类

    public func homeURL() -> String? {
        if let url = config.homeURL, !url.isEmpty { return url }
        return source.api
    }

    public func categoryURL(categoryID: String, page: Int) -> String? {
        guard var template = config.categoryURL, !template.isEmpty else { return nil }
        template = template.replacingOccurrences(of: "{cateId}", with: categoryID)
        template = template.replacingOccurrences(of: "{catePg}", with: String(page))
        template = template.replacingOccurrences(of: "{pg}", with: String(page))
        template = template.replacingOccurrences(of: "{year}", with: "")
        template = template.replacingOccurrences(of: "{area}", with: "")
        return resolve(template)
    }

    public func searchURL(keyword: String, page: Int) -> String? {
        guard var template = config.searchURL, !template.isEmpty else { return nil }
        if template.contains(";post;") {
            // POST 形式在这里退化成 GET，绝大多数站点也能返回结果
            template = template.replacingOccurrences(of: "post", with: "")
        }
        template = template.replacingOccurrences(of: "{wd}", with: URLNormalizer.escapeQuery(keyword))
        template = template.replacingOccurrences(of: "{pg}", with: String(page))
        template = template.replacingOccurrences(of: "{page}", with: String(page))
        return resolve(template)
    }

    // MARK: - 列表解析

    /// 从列表页 HTML 里抽出一页影片。
    public func parseList(html: String, page: Int) -> VodPage {
        let body = config.listSecondCut.map { RuleDSL.cut(html, $0) } ?? html
        let items = RuleDSL.items(from: body, arrayRule: config.listArray, baseURL: homeURL() ?? source.api)
            .compactMap { block -> VodItem? in
                guard let name = RuleDSL.pick(block, config.title), !name.isEmpty else { return nil }
                let link = RuleDSL.pick(block, config.link).flatMap { resolve($0) }
                guard let link, !link.isEmpty else { return nil }
                let vodID = RuleDSL.extractID(link, fallback: name)
                return VodItem(
                    sourceID: source.id,
                    sourceName: source.name,
                    vodID: vodID,
                    name: name,
                    pic: RuleDSL.pick(block, config.pic).flatMap { resolve($0) },
                    remarks: RuleDSL.pick(block, config.subtitle),
                    year: RuleDSL.pick(block, config.year),
                    area: RuleDSL.pick(block, config.area),
                    typeName: RuleDSL.pick(block, config.typeName),
                    score: nil,
                    tag: nil
                )
            }
        return VodPage(items: items, page: page, pageCount: page + 1, total: items.count)
    }

    /// 搜索结果页，字段可以用独立的 搜索数组 / 搜索标题 等覆盖列表配置。
    public func parseSearch(html: String, page: Int) -> VodPage {
        let body = config.searchSecondCut.map { RuleDSL.cut(html, $0) } ?? html
        let array = config.searchArray ?? config.listArray
        let items = RuleDSL.items(from: body, arrayRule: array, baseURL: homeURL() ?? source.api)
            .compactMap { block -> VodItem? in
                let name = RuleDSL.pick(block, config.searchTitle ?? config.title)
                guard let name, !name.isEmpty else { return nil }
                let rawLink = RuleDSL.pick(block, config.searchLink ?? config.link)
                guard let link = rawLink.flatMap({ resolve($0) }), !link.isEmpty else { return nil }
                if let suffix = config.searchSuffix, !suffix.isEmpty, !link.contains(suffix) { return nil }
                return VodItem(
                    sourceID: source.id,
                    sourceName: source.name,
                    vodID: RuleDSL.extractID(link, fallback: name),
                    name: name,
                    pic: RuleDSL.pick(block, config.searchPic ?? config.pic).flatMap { resolve($0) },
                    remarks: RuleDSL.pick(block, config.searchSubtitle ?? config.subtitle),
                    year: RuleDSL.pick(block, config.year),
                    area: RuleDSL.pick(block, config.area),
                    typeName: RuleDSL.pick(block, config.typeName),
                    score: nil,
                    tag: nil
                )
            }
        return VodPage(items: items, page: page, pageCount: page + 1, total: items.count)
    }

    // MARK: - 详情解析

    /// 详情页 HTML → 多线路剧集。
    public func parseDetail(html: String, item: VodItem) -> VodDetail {
        let lineTitles = lineNames(from: html)
        let groups = episodeGroups(from: html)

        var lines: [PlayLine] = []
        for (index, group) in groups.enumerated() {
            guard !group.isEmpty else { continue }
            let title = index < lineTitles.count ? lineTitles[index] : "线路\(index + 1)"
            lines.append(PlayLine(name: title, episodes: group))
        }
        if lines.isEmpty, !groups.isEmpty {
            lines = groups.enumerated().map { PlayLine(name: "线路\($0.offset + 1)", episodes: $0.element) }
        }

        return VodDetail(
            item: item,
            content: RuleDSL.pick(html, config.intro),
            director: RuleDSL.pick(html, config.director),
            actor: RuleDSL.pick(html, config.actor),
            lines: lines
        )
    }

    /// 线路名，取不到就给序号。
    private func lineNames(from html: String) -> [String] {
        guard let rule = config.lineTitle else { return [] }
        let body = config.lineSecondCut.map { RuleDSL.cut(html, $0) } ?? html
        let raw = RuleDSL.matches(in: body, rule: rule)
        let cleaned = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return cleaned
    }

    /// 按 播放数组 → 播放列表 → 播放标题/播放链接 逐层取出剧集。
    private func episodeGroups(from html: String) -> [[Episode]] {
        let body = config.playSecondCut.map { RuleDSL.cut(html, $0) } ?? html
        guard let arrayRule = config.playArray, !arrayRule.isEmpty else {
            // 没有分组规则时，直接整页找播放项
            return [episodes(from: body)]
        }
        let blocks = RuleDSL.matches(in: body, rule: arrayRule)
        if blocks.isEmpty { return [episodes(from: body)] }
        return blocks.map { episodes(from: $0) }
    }

    private func episodes(from block: String) -> [Episode] {
        guard let listRule = config.playList, !listRule.isEmpty else { return [] }
        let items = RuleDSL.matches(in: block, rule: listRule)
        var output: [Episode] = []
        var seen = Set<String>()
        for raw in items {
            let title = RuleDSL.pick(raw, config.playTitle)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let href = RuleDSL.pick(raw, config.playLink)
            guard let href, !href.isEmpty, let url = resolve(href) else { continue }
            if config.filterWords.contains(where: { !$0.isEmpty && url.contains($0) }) { continue }
            guard seen.insert(url).inserted else { continue }
            let name = (title?.isEmpty == false ? title! : "第\(output.count + 1)集")
            output.append(Episode(name: name, url: url))
        }
        return output
    }

    // MARK: - 播放地址

    /// 该片是否需要走嗅探（网页里没有直链，要靠 WebView 抓 m3u8）。
    public func needsSniffing(_ episodeURL: String) -> Bool {
        if config.noSniff == "1" { return false }
        if let words = config.sniffWords, !words.isEmpty {
            return words.contains { episodeURL.lowercased().contains($0.lowercased()) }
        }
        return !URLNormalizer.isDirectMedia(episodeURL)
    }

    /// 把相对地址补成绝对地址。
    public func resolve(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        if value.hasPrefix("//") { return "https:" + value }
        return URLNormalizer.resolve(value, base: homeURL() ?? source.api)
    }
}

/// XBPQ 规则里实际会用到的那部分字段。
public struct RuleConfig: Sendable, Equatable {
    public var siteName: String?
    public var homeURL: String?
    public var categoryList: [(String, String)] = []
    public var categoryURL: String?
    public var listArray: String?
    public var listSecondCut: String?
    public var title: String?
    public var link: String?
    public var pic: String?
    public var subtitle: String?
    public var intro: String?
    public var director: String?
    public var actor: String?
    public var year: String?
    public var area: String?
    public var typeName: String?

    public var searchURL: String?
    public var searchArray: String?
    public var searchTitle: String?
    public var searchLink: String?
    public var searchPic: String?
    public var searchSubtitle: String?
    public var searchSuffix: String?
    public var searchSecondCut: String?
    public var searchMode: String?

    public var lineTitle: String?
    public var lineSecondCut: String?
    public var playArray: String?
    public var playList: String?
    public var playTitle: String?
    public var playLink: String?
    public var playSecondCut: String?

    public var sniffWords: String?
    public var noSniff: String?
    public var filterWords: [String] = []

    public init() {}

    public static func == (lhs: RuleConfig, rhs: RuleConfig) -> Bool {
        lhs.siteName == rhs.siteName
            && lhs.homeURL == rhs.homeURL
            && lhs.categoryURL == rhs.categoryURL
            && lhs.listArray == rhs.listArray
            && lhs.title == rhs.title
            && lhs.link == rhs.link
            && lhs.playList == rhs.playList
    }
}
