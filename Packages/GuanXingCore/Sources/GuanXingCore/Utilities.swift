import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum GuanXingError: LocalizedError, Sendable {
    case invalidURL(String)
    case http(Int)
    case network(String)
    case decode(String)
    case empty(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value): return "地址无效：\(value)"
        case .http(let code): return "服务器返回 HTTP \(code)"
        case .network(let message): return "网络请求失败：\(message)"
        case .decode(let message): return "数据解析失败：\(message)"
        case .empty(let message): return message
        }
    }
}

public enum URLNormalizer {
    public static func normalized(_ raw: String?, trimTrailingSlash: Bool = true) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        while let last = text.last, last == "?" || last == "#" {
            text.removeLast()
        }
        guard let scheme = URLComponents(string: text)?.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var components = URLComponents(string: text),
              let host = components.host, !host.isEmpty else {
            return nil
        }
        if trimTrailingSlash {
            while components.path.count > 1 && components.path.hasSuffix("/") {
                components.path.removeLast()
            }
            if components.path == "/" { components.path = "" }
        }
        if components.query?.isEmpty == true { components.query = nil }
        if components.fragment?.isEmpty == true { components.fragment = nil }
        return components.string
    }

    public static func host(of value: String) -> String {
        URLComponents(string: value)?.host ?? value
    }

    public static func origin(of value: String) -> String? {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme,
              let host = components.host else { return nil }
        var origin = "\(scheme)://\(host)"
        if let port = components.port { origin += ":\(port)" }
        return origin
    }

    public static func resolve(_ raw: String?, base: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let direct = normalized(raw) { return direct }
        guard let base, let baseURL = URL(string: base),
              let resolved = URL(string: raw, relativeTo: baseURL)?.absoluteURL.absoluteString else {
            return nil
        }
        return normalized(resolved)
    }

    public static func appendQuery(to api: String, items: [(String, String)]) -> String? {
        guard var components = URLComponents(string: api) else { return nil }
        var queryItems = components.queryItems ?? []
        for (name, value) in items {
            queryItems.removeAll { $0.name == name }
            queryItems.append(URLQueryItem(name: name, value: value))
        }
        components.queryItems = queryItems
        return components.url?.absoluteString
    }

    public static func escapeQuery(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    public static func isDirectMedia(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if lower.hasPrefix("data:video/") { return true }
        let path = lower.split(separator: "?", maxSplits: 1).first.map(String.init) ?? lower
        let extensions = [".m3u8", ".mp4", ".m4v", ".mov", ".ts", ".webm", ".flv", ".mkv"]
        return extensions.contains { path.hasSuffix($0) }
    }
}

public enum StableID {
    public static func make(_ prefix: String, _ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "\(prefix)_\(String(hash, radix: 16))"
    }
}

public enum TextSanitizer {
    public static func plainText(fromHTML html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<[^>]+>", with: "", options: .regularExpression)
        let entities: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&ldquo;": "“",
            "&rdquo;": "”", "&hellip;": "…", "&mdash;": "—"
        ]
        for (key, value) in entities {
            text = text.replacingOccurrences(of: key, with: value, options: .caseInsensitive)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);") {
            let source = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
                let raw = source.substring(with: match.range(at: 1))
                let scalarValue = raw.lowercased().hasPrefix("x")
                    ? UInt32(raw.dropFirst(), radix: 16)
                    : UInt32(raw, radix: 10)
                if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                    text = (text as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
                }
            }
        }
        text = text.replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n[\\t ]+", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func concise(_ raw: String?, limit: Int = 120) -> String? {
        guard let raw else { return nil }
        let value = plainText(fromHTML: raw)
        guard !value.isEmpty else { return nil }
        if value.count <= limit { return value }
        return String(value.prefix(limit)) + "…"
    }

    public static func normalizedTitle(_ raw: String) -> String {
        let allowed = raw.lowercased().unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar.value > 0x2E80
        }
        return String(String.UnicodeScalarView(allowed))
    }
}

public enum JSONC {
    public static func parse(_ data: Data) throws -> Any {
        if let text = String(data: data, encoding: .utf8) {
            return try parse(text)
        }
        throw GuanXingError.decode("返回内容不是 UTF-8 文本")
    }

    public static func parse(_ text: String) throws -> Any {
        let cleaned = stripArtifacts(text.replacingOccurrences(of: "\u{FEFF}", with: ""))
        if let data = cleaned.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return object
        }

        if let extracted = extractJSONObject(from: cleaned),
           let data = extracted.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return object
        }

        if let decoded = decodeBase64Payload(in: cleaned),
           let data = decoded.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return object
        }

        throw GuanXingError.decode("订阅内容不是合法 JSON")
    }

    static func stripArtifacts(_ text: String) -> String {
        let characters = Array(text)
        var output = ""
        output.reserveCapacity(characters.count)
        var index = 0
        var inString = false
        var escaped = false
        var lineComment = false
        var blockComment = false

        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            if lineComment {
                if character == "\n" || character == "\r" {
                    lineComment = false
                    output.append(character)
                }
                index += 1
                continue
            }
            if blockComment {
                if character == "*" && next == "/" {
                    blockComment = false
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            if inString {
                if escaped {
                    if character == "\n" { output.append("n") }
                    else if character == "\r" { }
                    else { output.append(character) }
                    escaped = false
                    index += 1
                    continue
                }
                if character == "\\" {
                    output.append(character)
                    escaped = true
                    index += 1
                    continue
                }
                if character == "\"" {
                    inString = false
                    output.append(character)
                    index += 1
                    continue
                }
                if character == "\n" {
                    output.append("\\n")
                    index += 1
                    continue
                }
                if character == "\r" {
                    index += 1
                    continue
                }
                if character == "\t" {
                    output.append("\\t")
                    index += 1
                    continue
                }
                output.append(character)
                index += 1
                continue
            }

            if character == "\"" {
                inString = true
                output.append(character)
                index += 1
                continue
            }
            if character == "/" && next == "/" {
                lineComment = true
                index += 2
                continue
            }
            if character == "/" && next == "*" {
                blockComment = true
                index += 2
                continue
            }
            output.append(character)
            index += 1
        }
        return stripTrailingCommas(output)
    }

    static func stripTrailingCommas(_ text: String) -> String {
        let characters = Array(text)
        var output = ""
        var inString = false
        var escaped = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if inString {
                output.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                index += 1
                continue
            }
            if character == "\"" {
                inString = true
                output.append(character)
                index += 1
                continue
            }
            if character == "," {
                var lookahead = index + 1
                while lookahead < characters.count,
                      characters[lookahead].isWhitespace {
                    lookahead += 1
                }
                if lookahead < characters.count,
                   characters[lookahead] == "}" || characters[lookahead] == "]" {
                    index += 1
                    continue
                }
            }
            output.append(character)
            index += 1
        }
        return output
    }

    static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(text[start...end])
    }

    static func decodeBase64Payload(in text: String) -> String? {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker = compact.range(of: "base64,"),
           let data = Data(base64Encoded: String(compact[marker.upperBound...]), options: [.ignoreUnknownCharacters]),
           let decoded = String(data: data, encoding: .utf8),
           decoded.contains("{") {
            return decoded
        }
        if compact.count > 80,
           let data = Data(base64Encoded: compact, options: [.ignoreUnknownCharacters]),
           let decoded = String(data: data, encoding: .utf8),
           decoded.contains("{") {
            return decoded
        }
        guard let regex = try? NSRegularExpression(pattern: "[A-Za-z0-9+/]{80,}={0,2}") else {
            return nil
        }
        let source = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let encoded = source.substring(with: match.range)
            guard let data = Data(base64Encoded: encoded),
                  let decoded = String(data: data, encoding: .utf8),
                  decoded.contains("{") else { continue }
            return decoded
        }
        return nil
    }
}

public enum LooseValue {
    public static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        case let value as Bool:
            return value ? "1" : "0"
        case let value as [Any]:
            return value.compactMap { string($0) }.first
        default:
            return nil
        }
    }

    public static func int(_ value: Any?) -> Int? {
        switch value {
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value.trimmingCharacters(in: .whitespaces))
        case let value as Bool: return value ? 1 : 0
        default: return nil
        }
    }

    public static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as String:
            let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
            if ["true", "1", "yes", "on"].contains(lower) { return true }
            if ["false", "0", "no", "off"].contains(lower) { return false }
            return nil
        default: return nil
        }
    }

    public static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    public static func array(_ value: Any?) -> [Any]? {
        value as? [Any]
    }
}

public enum GuanXingHTTP {
    public static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    public static func get(
        _ urlString: String,
        headers: [String: String] = [:],
        timeout: TimeInterval = 15
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else {
            throw GuanXingError.invalidURL(urlString)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, text/html, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GuanXingError.network("非 HTTP 响应")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw GuanXingError.http(http.statusCode)
            }
            return (data, http)
        } catch let error as GuanXingError {
            throw error
        } catch {
            throw GuanXingError.network(error.localizedDescription)
        }
    }

    public static func getText(
        _ urlString: String,
        headers: [String: String] = [:],
        timeout: TimeInterval = 15
    ) async throws -> String {
        let (data, _) = try await get(urlString, headers: headers, timeout: timeout)
        guard let text = TextDecoder.decode(data) else {
            throw GuanXingError.decode("文本编码无法识别")
        }
        return text
    }
}
