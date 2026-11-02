import Foundation

/// 判断一个 `csp_*` 站点能不能在 iOS 上纯 Swift 跑，并产出对应绑定。
///
/// 判定只看两件事：
/// 1. 协议是不是已知的（AppGet / AppQi / AppRJ / 规则 DSL）
/// 2. 配置里有没有跑起来必需的参数（根地址、密钥）
///
/// 判不出来的直接返回 nil，导入时按「需要 Spider 运行时」跳过，
/// 不做「看起来能跑」的猜测。
public enum SpiderBindingResolver {
    public static func resolve(api: String, ext: Any?, type: Int) -> SpiderBinding? {
        let name = api.lowercased()
        guard name.hasPrefix("csp_") else { return nil }

        // 规则 DSL：ext 本身就是规则对象
        if case .rule(let config) = RuleConfigParser.classify(api: api, ext: ext),
           config.listArray != nil || config.playList != nil {
            guard let binding = SpiderBinding(kind: .rule, ext: sanitizedRule(ext)) else { return nil }
            _ = type
            return binding
        }

        guard let dict = ext as? [String: Any] else { return nil }

        if let kind = AppCmsSpider.kind(forAPIName: api, ext: dict) {
            switch kind {
            case .appGet: return SpiderBinding(kind: .appGet, ext: dict)
            case .appQi: return SpiderBinding(kind: .appQi, ext: dict)
            case .appRJ: return SpiderBinding(kind: .appRJ, ext: dict)
            }
        }

        // 以后在这里继续挂新的协议实现，判不出来的自然落到 nil
        return nil
    }

    /// 有些站的 api 是本地文件路径（如 `./lib/9.txt`），
    /// 这种要换成 ext 里的真实根地址，否则请求必然失败。
    public static func apiRoot(api: String, binding: SpiderBinding?) -> String? {
        guard let binding else { return nil }
        guard !api.lowercased().hasPrefix("http") else { return nil }
        let dict = binding.dictionary
        guard let root = LooseValue.string(dict["url"]) ?? LooseValue.string(dict["site"]),
              root.hasPrefix("http") else { return nil }
        return root
    }

    private static func sanitizedRule(_ ext: Any?) -> [String: Any]? {
        guard let dict = ext as? [String: Any] else { return nil }
        // 去掉明显是运行时才需要的键，减小持久化体积
        var output = dict
        output.removeValue(forKey: "ext")
        return output
    }
}
