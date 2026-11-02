import Foundation

/// 源身份归一化与批量导入去重。
///
/// 同一路接口在不同配置里经常长得不一样：
/// `https://a.com/api.php/provide/vod/` / `http://a.com/api.php/provide/vod` /
/// `https://a.com/api.php/provide/vod?ac=list` 其实是同一个源。
/// 这里把它们压成同一个指纹，避免批量导入时同一路接口进来十几遍。
public enum SourceDeduplicator {

    /// 计算用于判重的指纹：忽略协议、默认端口、末尾斜杠、查询参数，
    /// 并把苹果 CMS 的几种等价路径（/at/xml、/from/xxx 等）归一。
    public static func fingerprint(for rawAPI: String) -> String {
        var text = rawAPI.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return "" }

        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        // 去掉查询与锚点
        if let cut = text.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            text = String(text[text.startIndex..<cut])
        }
        // 只去掉 URL 中主机段的默认端口（a.com:443/x），不能只看结尾
        if let slash = text.firstIndex(of: "/") {
            let hostPart = String(text[text.startIndex..<slash])
            var cleaned = hostPart
            for port in [":443", ":80"] where cleaned.hasSuffix(port) {
                cleaned.removeLast(port.count)
            }
            text = cleaned + String(text[slash...])
        } else {
            for port in [":443", ":80"] where text.hasSuffix(port) {
                text.removeLast(port.count)
            }
        }
        while text.hasSuffix("/") { text.removeLast() }

        // 苹果 CMS：只有真正以 /api.php/provide/vod 结尾（或后面跟路径分隔符）的才算等价，
        // 否则 /api.php/provide/vod2 这类不同接口会被误吞。
        let marker = "/api.php/provide/vod"
        if let range = text.range(of: marker) {
            let host = String(text[text.startIndex..<range.lowerBound])
            let rest = String(text[range.lowerBound...])
            let isBoundary = rest == marker || rest.hasPrefix(marker + "/")
            if isBoundary { return host + marker }
        }
        return text
    }

    public static func isDuplicate(_ lhs: String, _ rhs: String) -> Bool {
        let a = fingerprint(for: lhs)
        let b = fingerprint(for: rhs)
        return !a.isEmpty && a == b
    }

    /// 合并结果，便于一次性展示“新增多少、重复多少、跳过多少”。
    public struct MergeResult: Sendable, Equatable {
        public var added: [VodSource]
        public var duplicates: Int
        public var skipped: Int
        public var duplicateNames: [String]

        public init(added: [VodSource], duplicates: Int, skipped: Int, duplicateNames: [String] = []) {
            self.added = added
            self.duplicates = duplicates
            self.skipped = skipped
            self.duplicateNames = duplicateNames
        }

        public var isEmpty: Bool { added.isEmpty }
    }

    /// 把一批待导入源并入已有列表，按指纹去重，同时清掉这一批内部的重复。
    public static func merge(
        incoming: [VodSource],
        existing: [VodSource]
    ) -> MergeResult {
        var seen = Set(existing.map { fingerprint(for: $0.api) })
        var added: [VodSource] = []
        var duplicates = 0
        var duplicateNames: [String] = []

        for source in incoming {
            let key = fingerprint(for: source.api)
            guard !key.isEmpty else { continue }

            if seen.contains(key) {
                duplicates += 1
                if duplicateNames.count < 20 { duplicateNames.append(source.name) }
                continue
            }
            // 同一主机不同路径通常确实是不同的源，默认放行；
            // 但完全同指纹的一定拦掉。
            seen.insert(key)
            added.append(source)
        }
        return MergeResult(added: added, duplicates: duplicates, skipped: 0, duplicateNames: duplicateNames)
    }
}

/// 多仓（urls 数组）展开结果。
public struct RepositoryEntry: Sendable, Hashable {
    public var name: String
    public var url: String
    public var parentName: String

    public init(name: String, url: String, parentName: String) {
        self.name = name
        self.url = url
        self.parentName = parentName
    }
}

public enum RepositoryParser {
    /// 从多仓配置里取出 {name, url} 列表。多仓只保存索引，不保存站点。
    public static func entries(from json: Any, parentName: String) -> [RepositoryEntry] {
        guard let object = json as? [String: Any] else { return [] }
        let raw = LooseValue.array(object["urls"]) ?? LooseValue.array(object["repos"]) ?? []
        var output: [RepositoryEntry] = []
        var seen = Set<String>()
        for item in raw {
            let url: String?
            let name: String?
            if let dict = item as? [String: Any] {
                url = URLNormalizer.normalized(
                    LooseValue.string(dict["url"]) ?? LooseValue.string(dict["api"]),
                    trimTrailingSlash: false
                )
                name = LooseValue.string(dict["name"]) ?? LooseValue.string(dict["title"])
            } else {
                url = URLNormalizer.normalized(LooseValue.string(item), trimTrailingSlash: false)
                name = nil
            }
            guard let url, seen.insert(url).inserted else { continue }
            output.append(RepositoryEntry(
                name: (name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                    ?? URLNormalizer.host(of: url),
                url: url,
                parentName: parentName
            ))
        }
        return output
    }
}
