import Foundation

/// 统一入口：按源的类型分派到 CMS / 规则 DSL / APP 采集。
///
/// 界面层只依赖这个，不需要知道某个源背后到底是什么协议。
public struct SourceClient: Sendable {
    public let source: VodSource
    let timeout: TimeInterval

    public init(source: VodSource, timeout: TimeInterval = 15) {
        self.source = source
        self.timeout = timeout
    }

    public var engineName: String {
        guard let spider = source.spider else { return "CMS" }
        switch spider.kind {
        case .rule: return "规则 Spider"
        case .appGet, .appQi: return "APP 采集"
        case .appRJ: return "APP 采集 · 热播"
        }
    }

    public func categories() async throws -> [VodCategory] {
        if let spider = source.spider {
            switch spider.kind {
            case .rule:
                return ruleCategories(spider)
            case .appGet, .appQi, .appRJ:
                let spider = try makeAppSpider(spider)
                return try await spider.categories()
            }
        }
        return try await CMSClient(source: source, timeout: timeout).categories()
    }

    public func latest(page: Int = 1) async throws -> VodPage {
        if let spider = source.spider {
            switch spider.kind {
            case .rule:
                return try await ruleLatest(spider, page: page)
            case .appGet, .appQi, .appRJ:
                let spider = try makeAppSpider(spider)
                return try await spider.latest(page: page)
            }
        }
        return try await CMSClient(source: source, timeout: timeout).latest(page: page)
    }

    public func list(typeID: String?, page: Int = 1) async throws -> VodPage {
        if let spider = source.spider {
            switch spider.kind {
            case .rule:
                return try await ruleList(spider, typeID: typeID, page: page)
            case .appGet, .appQi, .appRJ:
                let spider = try makeAppSpider(spider)
                let items = try await spider.list(typeID: typeID, page: page)
                return VodPage(items: items, page: page, pageCount: page + 1, total: items.count)
            }
        }
        return try await CMSClient(source: source, timeout: timeout).list(typeID: typeID, page: page)
    }

    public func search(keyword: String, page: Int = 1) async throws -> [VodItem] {
        if let spider = source.spider {
            switch spider.kind {
            case .rule:
                return try await ruleSearch(spider, keyword: keyword, page: page)
            case .appGet, .appQi, .appRJ:
                let spider = try makeAppSpider(spider)
                return try await spider.search(keyword: keyword, page: page)
            }
        }
        return try await CMSClient(source: source, timeout: timeout).search(keyword: keyword, page: page)
    }

    public func detail(vodID: String, link: String? = nil) async throws -> VodDetail {
        if let spider = source.spider {
            switch spider.kind {
            case .rule:
                return try await ruleDetail(spider, vodID: vodID, link: link)
            case .appGet, .appQi, .appRJ:
                let spider = try makeAppSpider(spider)
                return try await spider.detail(vodID: vodID)
            }
        }
        return try await CMSClient(source: source, timeout: timeout).detail(vodID: vodID)
    }

    public func healthCheck() async -> SourceHealth {
        let start = Date()
        do {
            let page = try await latest(page: 1)
            let latency = Date().timeIntervalSince(start)
            if page.items.isEmpty {
                return SourceHealth(state: .slow, latency: latency, message: "能连通但没返回内容", checkedAt: Date())
            }
            return SourceHealth(state: .healthy, latency: latency, message: "\(page.items.count) 条", checkedAt: Date())
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return SourceHealth(state: .failed, message: message, checkedAt: Date())
        }
    }

    // MARK: - 分派细节

    private func makeAppSpider(_ binding: SpiderBinding) throws -> AppCmsSpider {
        let ext = binding.dictionary
        switch binding.kind {
        case .appGet, .appQi:
            guard let config = AppCmsConfig(ext: ext) else {
                throw GuanXingError.decode("缺少 url / dataKey，无法直连该 APP 接口")
            }
            let kind: AppCmsSpider.Kind = binding.kind == .appGet ? .appGet : .appQi
            return AppCmsSpider(source: source, kind: kind, config: config, timeout: timeout)
        case .appRJ:
            guard let root = LooseValue.string(ext["url"]) ?? LooseValue.string(ext["site"]) else {
                throw GuanXingError.decode("缺少 url，无法直连该 APP 接口")
            }
            let config = AppCmsConfig(root: root, dataKey: "", dataIv: "")
            return AppCmsSpider(source: source, kind: .appRJ, config: config, timeout: timeout)
        case .rule:
            throw GuanXingError.decode("规则型源不应走到这里")
        }
    }

    private func ruleConfig(_ binding: SpiderBinding) -> RuleConfig {
        RuleConfigParser.decode(binding.dictionary)
    }

    private func ruleCategories(_ binding: SpiderBinding) -> [VodCategory] {
        let pairs = ruleConfig(binding).categoryList
        return pairs.map { VodCategory(id: $0.0, name: $0.1) }
    }

    private func ruleLatest(_ binding: SpiderBinding, page: Int) async throws -> VodPage {
        let config = ruleConfig(binding)
        let spider = RuleSpider(config: config, source: source)
        // 没有主页规则时，退到第一个分类页，避免请求站点根路径拿到空白页。
        if config.homeURL == nil,
           let first = config.categoryList.first,
           let url = spider.categoryURL(categoryID: first.0, page: page) {
            let html = try await GuanXingHTTP.getText(url, headers: source.headers, timeout: timeout)
            return spider.parseList(html: html, page: page)
        }
        let url = config.homeURL ?? source.api
        let html = try await GuanXingHTTP.getText(url, headers: source.headers, timeout: timeout)
        return spider.parseList(html: html, page: page)
    }

    private func ruleList(_ binding: SpiderBinding, typeID: String?, page: Int) async throws -> VodPage {
        let config = ruleConfig(binding)
        let spider = RuleSpider(config: config, source: source)
        guard let typeID, let url = spider.categoryURL(categoryID: typeID, page: page) else {
            return try await ruleLatest(binding, page: page)
        }
        let html = try await GuanXingHTTP.getText(url, headers: source.headers, timeout: timeout)
        return spider.parseList(html: html, page: page)
    }

    private func ruleSearch(_ binding: SpiderBinding, keyword: String, page: Int) async throws -> [VodItem] {
        let config = ruleConfig(binding)
        let spider = RuleSpider(config: config, source: source)
        guard let url = spider.searchURL(keyword: keyword, page: page) else {
            throw GuanXingError.decode("该规则源没有配置搜索地址")
        }
        let html = try await GuanXingHTTP.getText(url, headers: source.headers, timeout: timeout)
        let result = spider.parseSearch(html: html, page: page)
        return result.items
    }

    private func ruleDetail(_ binding: SpiderBinding, vodID: String, link: String? = nil) async throws -> VodDetail {
        let config = ruleConfig(binding)
        let spider = RuleSpider(config: config, source: source)
        let url = link.flatMap { $0.hasPrefix("http") ? $0 : spider.resolve($0) }
            ?? (vodID.hasPrefix("http") ? vodID : (spider.resolve(vodID) ?? source.api))
        let html = try await GuanXingHTTP.getText(url, headers: source.headers, timeout: timeout)
        let item = VodItem(
            sourceID: source.id,
            sourceName: source.name,
            vodID: vodID,
            name: source.name
        )
        return spider.parseDetail(html: html, item: item)
    }
}
