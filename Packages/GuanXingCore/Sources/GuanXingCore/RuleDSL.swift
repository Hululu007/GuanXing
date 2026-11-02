import Foundation

/// 规则 DSL 求值。把 `A&&B`、`X||Y`、`j:path`、`✚` 这些写法翻译成取值操作。
public enum RuleDSL {

    /// 取一条规则的单个值。
    public static func pick(_ text: String, _ rule: String?) -> String? {
        guard let rule, !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        for branch in rule.components(separatedBy: "||") {
            if let value = evaluate(text, branch), !value.isEmpty { return value }
        }
        return nil
    }

    /// 取一条规则全部匹配（用于数组 / 播放列表）。
    public static func matches(in text: String, rule: String) -> [String] {
        guard let pattern = arrayPattern(rule) else { return [] }
        return extractAll(text, before: pattern.0, after: pattern.1)
    }

    /// 先按整条规则裁出片段（二次截取用）。
    public static func cut(_ text: String, _ rule: String) -> String {
        guard let pattern = arrayPattern(rule) else { return text }
        guard let first = extractAll(text, before: pattern.0, after: pattern.1).first else { return text }
        return first
    }

    /// 从列表页里切出每一条影片对应的 HTML 片段。
    public static func items(from text: String, arrayRule: String?, baseURL: String) -> [String] {
        guard let arrayRule, !arrayRule.isEmpty else { return [] }
        // `标题&&链接` 这种每行两个字段的写法在列表里不常见，
        // 统一按「数组」规则切块即可。
        return matches(in: text, rule: arrayRule)
    }

    /// 从详情链接里拿 ID：优先 ?id= / /detail/123 这类，取不到就用标题哈希。
    public static func extractID(_ link: String, fallback: String) -> String {
        if let components = URLComponents(string: link),
           let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
           !id.isEmpty {
            return id
        }
        let parts = link.split(whereSeparator: { "/?#&=.".contains($0) }).filter { !$0.isEmpty }
        for part in parts.reversed() where part.count >= 2 && part.allSatisfy({ $0.isNumber || $0.isLetter }) {
            if part.contains(where: \.isNumber) { return String(part) }
        }
        return fallback
    }

    // MARK: - 核心求值

    static func evaluate(_ text: String, _ rawRule: String) -> String? {
        var rule = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty else { return nil }

        // 拼接：多段用 ✚ 连起来
        if rule.contains("✚") {
            let parts = rule.components(separatedBy: "✚")
            var output = ""
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if trimmed.hasPrefix("j:") || trimmed.contains("&&") || trimmed.hasPrefix("[") {
                    output += evaluate(text, trimmed) ?? ""
                } else {
                    output += trimmed
                }
            }
            return output.isEmpty ? nil : output
        }

        // JSON 取值
        if rule.hasPrefix("j:") {
            return jsonValue(text, path: String(rule.dropFirst(2)))
        }

        // 后置处理：[替换:a>>b#c>>d]、[含序号:2]
        var processors: [String] = []
        while let start = rule.lastIndex(of: "["), rule.hasSuffix("]"),
              let close = rule.lastIndex(of: "]"), close > start {
            processors.insert(String(rule[rule.index(after: start)..<close]), at: 0)
            rule = String(rule[rule.startIndex..<start])
        }

        guard let pattern = arrayPattern(rule) else { return nil }
        var value: String?
        if pattern.0.isEmpty && pattern.1.isEmpty {
            value = nil
        } else if pattern.1.isEmpty {
            value = after(text, marker: pattern.0)
        } else if pattern.0.isEmpty {
            value = before(text, marker: pattern.1)
        } else {
            value = between(text, start: pattern.0, end: pattern.1)
        }

        guard var result = value, !result.isEmpty else { return nil }
        for processor in processors {
            result = apply(processor, to: result)
        }
        return result.isEmpty ? nil : result
    }

    /// 把 `A&&B` 拆成前后两个标记。
    static func arrayPattern(_ rule: String) -> (String, String)? {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let range = trimmed.range(of: "&&") {
            return (String(trimmed[trimmed.startIndex..<range.lowerBound]),
                    String(trimmed[range.upperBound...]))
        }
        // 只有单个标记：当结尾标记用
        return ("", trimmed)
    }

    // MARK: - 字符串定位

    static func between(_ text: String, start: String, end: String) -> String? {
        guard let startRange = text.range(of: start) else { return nil }
        let tail = text[startRange.upperBound...]
        guard let endRange = tail.range(of: end) else { return nil }
        return String(tail[tail.startIndex..<endRange.lowerBound])
    }

    static func after(_ text: String, marker: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        return String(text[range.upperBound...])
    }

    static func before(_ text: String, marker: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        return String(text[text.startIndex..<range.lowerBound])
    }

    static func extractAll(_ text: String, before: String, after: String) -> [String] {
        let startMarker = before.isEmpty ? "" : before
        let endMarker = after.isEmpty ? "" : after
        var output: [String] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            let slice = text[cursor...]
            let start: String.Index
            if startMarker.isEmpty {
                start = cursor
            } else if let range = slice.range(of: startMarker) {
                start = range.upperBound
            } else {
                break
            }

            if endMarker.isEmpty {
                let value = String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { output.append(value) }
                break
            }

            let tail = text[start...]
            guard let endRange = tail.range(of: endMarker) else { break }
            let value = String(tail[tail.startIndex..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { output.append(value) }
            cursor = endRange.upperBound
            if cursor == start { break }
        }
        return output
    }

    // MARK: - JSON 路径

    static func jsonValue(_ text: String, path: String) -> String? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        var current: Any = root
        for raw in path.split(separator: ".") {
            var key = String(raw)
            var indices: [Int] = []
            while let open = key.lastIndex(of: "["), key.hasSuffix("]") {
                let inner = String(key[key.index(after: open)..<key.index(before: key.endIndex)])
                if let index = Int(inner) { indices.insert(index, at: 0) }
                key = String(key[key.startIndex..<open])
            }
            if !key.isEmpty {
                guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
                current = next
            }
            for index in indices {
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            }
        }
        if let string = current as? String { return string }
        if let number = current as? NSNumber { return number.stringValue }
        return nil
    }

    // MARK: - 后置处理

    static func apply(_ processor: String, to value: String) -> String {
        var result = value
        if processor.hasPrefix("替换:") {
            let body = String(processor.dropFirst("替换:".count))
            for pair in body.components(separatedBy: "#") {
                let parts = pair.components(separatedBy: ">>")
                guard parts.count == 2, !parts[0].isEmpty else { continue }
                result = result.replacingOccurrences(of: parts[0], with: parts[1])
            }
        } else if processor.hasPrefix("去除:") {
            let body = String(processor.dropFirst("去除:".count))
            for token in body.components(separatedBy: "#") where !token.isEmpty {
                result = result.replacingOccurrences(of: token, with: "")
            }
        } else if processor.hasPrefix("含序号:") {
            let index = Int(processor.dropFirst("含序号:".count)) ?? 1
            let parts = result.components(separatedBy: "$")
            if parts.indices.contains(index - 1) { result = parts[index - 1] }
        } else if processor.hasPrefix("不包含:") {
            let token = String(processor.dropFirst("不包含:".count))
            if result.contains(token) { return "" }
        } else if processor == "去空白" {
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
