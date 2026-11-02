import Foundation

/// 把 TVBox 配置里的 `type=3 + csp_XBPQ` 一类条目识别成「规则型」，并解析出 RuleConfig。
///
/// 这类源不需要 jar / js：规则本身就是数据，只要把 DSL 解释出来就能抓页面。
/// 识别不出来的（真正的 csp_ 类名、drpy 脚本）会被标记为 unsupported，交给上层提示。
public enum RuleConfigParser {

    public enum Outcome: Sendable {
        /// 规则型，可以直接用纯 Swift 跑
        case rule(RuleConfig)
        /// 需要 jar / js 运行时，iOS 不支持
        case unsupported(String)
    }

    /// 规则型 API 名。XBPQ 系是其中最常见的实现。
    public static let ruleAPIs: Set<String> = [
        "csp_xbpq", "csp_hbpq", "csp_xyqhiker", "csp_xyqhikeral"
    ]

    public static func classify(api: String, ext: Any?) -> Outcome {
        let lower = api.lowercased()

        // ext 本身就是完整规则对象（不看 api 名也给机会）
        if let dict = ext as? [String: Any], looksLikeRule(dict) {
            return .rule(decode(dict))
        }

        guard ruleAPIs.contains(lower) else {
            if lower.hasPrefix("csp_") { return .unsupported("需要 Spider 运行时：\(api)") }
            if lower.hasSuffix(".js") { return .unsupported("需要 JS 运行时：\(api)") }
            return .unsupported("未知类型：\(api)")
        }

        // ext 是路径字符串时无法离线取到规则文件，只能标记待加载
        return .unsupported("规则文件需联网加载：\(String(describing: ext ?? ""))")
    }

    /// 判断一个字典像不像 XBPQ 规则（有「数组」「标题」这类键）。
    public static func looksLikeRule(_ dict: [String: Any]) -> Bool {
        let keys = Set(dict.keys)
        let signals = ["数组", "分类url", "播放列表", "标题", "链接", "分类"]
        return signals.contains { keys.contains($0) }
    }

    public static func decode(_ dict: [String: Any]) -> RuleConfig {
        var config = RuleConfig()
        config.siteName = string(dict["站名"])
        config.homeURL = string(dict["主页url"])
        config.categoryURL = string(dict["分类url"])
        config.listArray = string(dict["数组"])
        config.listSecondCut = string(dict["二次截取"]) ?? string(dict["数组二次截取"])
        config.title = string(dict["标题"])
        config.link = string(dict["链接"])
        config.pic = string(dict["图片"])
        config.subtitle = string(dict["副标题"])
        config.intro = string(dict["简介"])
        config.director = string(dict["导演"])
        config.actor = string(dict["主演"]) ?? string(dict["演员"])
        config.year = string(dict["影片年代"])
        config.area = string(dict["影片地区"])
        config.typeName = string(dict["影片类型"]) ?? string(dict["类型"])

        config.searchURL = string(dict["搜索url"])
        config.searchArray = string(dict["搜索数组"])
        config.searchTitle = string(dict["搜索标题"])
        config.searchLink = string(dict["搜索链接"])
        config.searchPic = string(dict["搜索图片"])
        config.searchSubtitle = string(dict["搜索副标题"])
        config.searchSuffix = string(dict["搜索后缀"])
        config.searchSecondCut = string(dict["搜索二次截取"])
        config.searchMode = string(dict["搜索模式"])

        config.lineTitle = string(dict["线路标题"])
        config.lineSecondCut = string(dict["线路二次截取"])
        config.playArray = string(dict["播放数组"])
        config.playList = string(dict["播放列表"])
        config.playTitle = string(dict["播放标题"])
        config.playLink = string(dict["播放链接"])
        config.playSecondCut = string(dict["播放二次截取"])

        config.sniffWords = string(dict["嗅探词"])
        config.noSniff = string(dict["免嗅"])
        if let filters = string(dict["过滤词"]) {
            config.filterWords = filters.components(separatedBy: "#").filter { !$0.isEmpty }
        }
        config.categoryList = parseCategories(string(dict["分类"]))
        return config
    }

    /// `电影$movie#电视剧$tv` → [(movie, 电影), (tv, 电视剧)]
    static func parseCategories(_ raw: String?) -> [(String, String)] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw.components(separatedBy: "#").compactMap { chunk in
            let parts = chunk.components(separatedBy: "$")
            guard parts.count >= 2 else { return nil }
            return (parts[1], parts[0])
        }
    }

    static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}
