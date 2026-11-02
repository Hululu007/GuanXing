import Foundation

/// 站点绑定的 Spider 类型。只有能纯 Swift 跑的实现才会出现在这里。
public struct SpiderBinding: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case rule          // XBPQ 一类规则 DSL
        case appGet        // csp_AppGet
        case appQi         // csp_AppQi
        case appRJ         // csp_AppRJ
    }

    public var kind: Kind
    /// 原始 ext 的 JSON 文本，运行时再解出来。
    public var payload: String

    public init(kind: Kind, payload: String) {
        self.kind = kind
        self.payload = payload
    }

    public init?(kind: Kind, ext: Any) {
        guard JSONSerialization.isValidJSONObject(ext),
              let data = try? JSONSerialization.data(withJSONObject: ext, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        self.kind = kind
        self.payload = text
    }

    public var dictionary: [String: Any] {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }
}
