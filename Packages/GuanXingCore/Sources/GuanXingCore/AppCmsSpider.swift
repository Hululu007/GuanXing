import Foundation

/// 「APP 采集型」Spider 的纯 Swift 复刻。
///
/// 这类源（TVBox 里的 `csp_AppGet` / `csp_AppQi` / `csp_AppRJ` 一类）在安卓上是
/// 一段 Java 类，请求私有 APP 接口。它们不是标准 CMS，但协议本身是固定的：
///
/// - 请求头签名或请求体签名（时间戳 + 固定盐 → 摘要）
/// - 响应体用 `dataKey` / `dataIv` 做 AES/CBC 解密，得到 JSON
/// - 播放列表 `vod_play_list` 里多数是直链 m3u8，少数走第三方解析
///
/// 因为签名是公开算法、密钥写在站点配置里，所以可以原样搬到 iOS，
/// 不需要 JVM，也不需要跑任何 Java 字节码。
public struct AppCmsSpider: Sendable {
    public enum Kind: String, Codable, Sendable {
        /// `/api.php/getappapi.index/*`，AES 解密 data 字段
        case appGet
        /// `/api.php/qijiappapi.index/*`，AES 解密 data 字段
        case appQi
        /// `/v3/*`，MD5(固定key + 时间戳) 作为 sign，POST 表单
        case appRJ
    }

    public let source: VodSource
    public let kind: Kind
    public let config: AppCmsConfig
    private let timeout: TimeInterval

    public init(source: VodSource, kind: Kind, config: AppCmsConfig, timeout: TimeInterval = 20) {
        self.source = source
        self.kind = kind
        self.config = config
        self.timeout = timeout
    }

    // MARK: - 从 ext 还原

    /// 站点 ext 里是否带有能还原成 HTTP 协议的字段。
    public static func kind(forAPIName api: String, ext: [String: Any]) -> Kind? {
        let name = api.lowercased()
        let root = (LooseValue.string(ext["url"]) ?? LooseValue.string(ext["site"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCrypto = !(LooseValue.string(ext["dataKey"]) ?? "").isEmpty
        if name.contains("appget") {
            return (hasCrypto && root.hasPrefix("http")) ? .appGet : nil
        }
        if name.contains("appqi") {
            return (hasCrypto && root.hasPrefix("http")) ? .appQi : nil
        }
        if name.contains("apprj") {
            return root.hasPrefix("http") ? .appRJ : nil
        }
        return nil
    }

    // MARK: - 首页 / 分类 / 搜索

    public func categories() async throws -> [VodCategory] {
        switch kind {
        case .appGet: return try await appCmsCategories(prefix: "getappapi.index")
        case .appQi: return try await appCmsCategories(prefix: "qijiappapi.index")
        case .appRJ: return try await rjCategories()
        }
    }

    public func latest(page: Int = 1) async throws -> VodPage {
        let items = try await list(typeID: nil, page: page)
        return VodPage(items: items, page: page, pageCount: page + 1, total: items.count)
    }

    public func list(typeID: String?, page: Int = 1) async throws -> [VodItem] {
        switch kind {
        case .appGet: return try await appCmsList(prefix: "getappapi.index", typeID: typeID, page: page)
        case .appQi: return try await appCmsList(prefix: "qijiappapi.index", typeID: typeID, page: page)
        case .appRJ: return try await rjList(typeID: typeID, page: page)
        }
    }

    public func search(keyword: String, page: Int = 1) async throws -> [VodItem] {
        switch kind {
        case .appGet, .appQi:
            let prefix = kind == .appGet ? "getappapi.index" : "qijiappapi.index"
            let body = jsonBody(["type_id": "", "page": String(page), "keywords": keyword])
            let path = "/\(prefix)/typeFilterVodList?page=\(page)"
            let data = try await call(path: path, body: body)
            return parseAppCmsList(data, key: "recommend_list")
        case .appRJ:
            return try await rjSearch(keyword: keyword, page: page)
        }
    }

    // MARK: - 详情

    public func detail(vodID: String) async throws -> VodDetail {
        switch kind {
        case .appGet:
            let data = try await call(path: "/getappapi.index/vodDetail", body: jsonBody(["vod_id": vodID]))
            return try parseAppCmsDetail(data, vodID: vodID)
        case .appQi:
            // 祈家系（蓝色/蓝鹰）的详情只认 query 参数，body 会返回空列表
            let data = try await call(path: "/qijiappapi.index/vodDetail?vod_id=\(encoded(vodID))", body: "")
            return try parseAppCmsDetail(data, vodID: vodID)
        case .appRJ:
            return try await rjDetail(vodID: vodID)
        }
    }

    func encoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// 该集地址是否已经可以直接丢给 AVPlayer。
    public func isPlayableDirectly(_ url: String) -> Bool {
        URLNormalizer.isDirectMedia(url)
    }
}

/// AppGet / AppQi 需要的解密参数。
public struct AppCmsConfig: Sendable, Equatable {
    public var root: String
    public var dataKey: String
    public var dataIv: String
    public var deviceID: String?
    public var version: String?
    public var userAgent: String?
    public var token: String?

    public init(
        root: String,
        dataKey: String,
        dataIv: String,
        deviceID: String? = nil,
        version: String? = nil,
        userAgent: String? = nil,
        token: String? = nil
    ) {
        self.root = root
        self.dataKey = dataKey
        self.dataIv = dataIv
        self.deviceID = deviceID
        self.version = version
        self.userAgent = userAgent
        self.token = token
    }

    public init?(ext: [String: Any]) {
        guard let root = LooseValue.string(ext["url"]) ?? LooseValue.string(ext["site"]),
              root.hasPrefix("http") else { return nil }
        self.root = root.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.dataKey = LooseValue.string(ext["dataKey"]) ?? ""
        self.dataIv = LooseValue.string(ext["dataIv"]) ?? ""
        self.deviceID = LooseValue.string(ext["deviceId"])
        self.version = LooseValue.string(ext["version"]).flatMap { raw in
            Int(raw).map(String.init) ?? (raw.isEmpty ? nil : raw)
        }
        self.userAgent = LooseValue.string(ext["ua"])
        self.token = LooseValue.string(ext["token"])
    }
}
