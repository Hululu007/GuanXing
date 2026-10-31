import Foundation

public struct PlaybackRequest: Sendable, Hashable {
    public var url: String
    public var headers: [String: String]

    public init(url: String, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

public enum PlaybackResolver {
    public static func headers(for source: VodSource, extra: [String: String] = [:]) -> [String: String] {
        var headers = source.headers
        if headers["Referer"] == nil, let origin = URLNormalizer.origin(of: source.api) {
            headers["Referer"] = origin + "/"
        }
        if headers["User-Agent"] == nil {
            headers["User-Agent"] = GuanXingHTTP.userAgent
        }
        for (key, value) in extra { headers[key] = value }
        return headers
    }

    public static func resolve(
        episodeURL raw: String,
        source: VodSource,
        parsers: [ParseEndpoint] = []
    ) async -> PlaybackRequest {
        let headers = headers(for: source)
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if URLNormalizer.isDirectMedia(value) {
            return PlaybackRequest(url: value, headers: headers)
        }

        if let extracted = await extractFromWebPage(value, headers: headers) {
            return PlaybackRequest(url: extracted, headers: headers)
        }

        for parser in parsers.prefix(4) {
            guard let parserURL = buildParserURL(base: parser.url, target: value),
                  let text = try? await GuanXingHTTP.getText(parserURL, headers: headers, timeout: 10),
                  let extracted = extractPlayableURL(fromText: text) else { continue }
            return PlaybackRequest(url: extracted, headers: headers)
        }

        return PlaybackRequest(url: value, headers: headers)
    }

    public static func extractPlayableURL(fromText text: String) -> String? {
        let unescaped = text
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u002f", with: "/")

        if let data = unescaped.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            if let found = findPlayableURL(in: object) { return found }
        }

        let patterns = [
            #""(?:url|playUrl|playURL|src|video|m3u8|link)"\s*:\s*"([^"]+)""#,
            #"https?://[^\s"'<>\\]+?\.m3u8[^\s"'<>\\]*"#,
            #"https?://[^\s"'<>\\]+?\.mp4[^\s"'<>\\]*"#,
            #"const\s+vid\s*=\s*['"]([^'"]+)['"]"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let source = unescaped as NSString
            for match in regex.matches(in: unescaped, range: NSRange(location: 0, length: source.length)) {
                let range = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                guard range.location != NSNotFound else { continue }
                let candidate = source.substring(with: range)
                if candidate.lowercased().contains(".m3u8") || candidate.lowercased().contains(".mp4") {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func findPlayableURL(in object: Any) -> String? {
        if let string = object as? String {
            return string.lowercased().contains(".m3u8") || string.lowercased().contains(".mp4") ? string : nil
        }
        if let dict = object as? [String: Any] {
            for key in ["url", "playUrl", "playURL", "src", "video", "m3u8", "link"] {
                if let value = dict[key] as? String,
                   value.lowercased().contains(".m3u8") || value.lowercased().contains(".mp4") {
                    return value
                }
            }
            for value in dict.values {
                if let found = findPlayableURL(in: value) { return found }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let found = findPlayableURL(in: value) { return found }
            }
        }
        return nil
    }

    private static func extractFromWebPage(_ urlString: String, headers: [String: String]) async -> String? {
        guard let html = try? await GuanXingHTTP.getText(urlString, headers: headers, timeout: 12) else {
            return nil
        }
        if let found = extractPlayableURL(fromText: html) {
            if found.hasPrefix("http") { return found }
            if found.hasPrefix("//") { return "https:" + found }
            return URLNormalizer.resolve(found, base: urlString)
        }
        return nil
    }

    private static func buildParserURL(base: String, target: String) -> String? {
        let encoded = URLNormalizer.escapeQuery(target)
        if base.contains("{url}") {
            return base.replacingOccurrences(of: "{url}", with: encoded)
        }
        if base.contains("?") {
            return base + encoded
        }
        return base + "?url=" + encoded
    }
}
