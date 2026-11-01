import Foundation

#if canImport(Darwin)
import CoreFoundation
#endif

/// 直播源文件的格式。参考 TVS（TVBox-tvs）对 M3U / TXT / JSON 三种格式自动识别的做法。
public enum LivePlaylistFormat: String, Sendable {
    case m3u
    case txt
    case json

    public var title: String {
        switch self {
        case .m3u: return "M3U 列表"
        case .txt: return "TXT 频道表"
        case .json: return "JSON 直播源"
        }
    }

    public var fileExtension: String { rawValue }
}

public struct LivePlaylistParseResult: Sendable {
    public var format: LivePlaylistFormat
    public var channels: [LiveChannel]
    /// TXT / JSON 里同一频道的备用地址数量，当前只会取第一个可播放地址。
    public var alternateURLCount: Int
    /// 无法识别而跳过的行数。
    public var skippedLineCount: Int

    public init(
        format: LivePlaylistFormat,
        channels: [LiveChannel],
        alternateURLCount: Int = 0,
        skippedLineCount: Int = 0
    ) {
        self.format = format
        self.channels = channels
        self.alternateURLCount = alternateURLCount
        self.skippedLineCount = skippedLineCount
    }
}

/// 统一处理播放列表的文本编码。国内不少 TXT 频道表使用 GBK / GB18030。
public enum TextDecoder {
    public static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return stripBOM(text)
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16) { return stripBOM(text) }
        }
        #if canImport(Darwin)
        if let text = String(data: data, encoding: gb18030) { return stripBOM(text) }
        if let text = String(data: data, encoding: gb2312) { return stripBOM(text) }
        #endif
        if let text = String(data: data, encoding: .isoLatin1) { return stripBOM(text) }
        return nil
    }

    public static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    #if canImport(Darwin)
    static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )
    static let gb2312 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue)
        )
    )
    #endif
}

/// 直播源解析入口：自动识别 M3U、TXT（`#genre#` 分组）、JSON 三种格式。
public enum LivePlaylist {
    public static let genreMarker = "#genre#"

    public static func detect(_ text: String) -> LivePlaylistFormat? {
        let body = TextDecoder.stripBOM(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        if body.hasPrefix("#EXTM3U") || body.hasPrefix("#EXTINF") {
            return .m3u
        }
        if body.hasPrefix("{") || body.hasPrefix("[") {
            return looksLikeJSONLive(body) ? .json : nil
        }
        return looksLikeTXT(body) ? .txt : nil
    }

    public static func parse(
        _ text: String,
        sourceID: String,
        sourceName: String,
        headers: [String: String] = [:]
    ) -> LivePlaylistParseResult? {
        guard let format = detect(text) else { return nil }
        switch format {
        case .m3u:
            let channels = M3UParser.parse(
                text,
                sourceID: sourceID,
                sourceName: sourceName,
                headers: headers
            )
            return LivePlaylistParseResult(format: .m3u, channels: channels)
        case .txt:
            return parseTXT(text, sourceID: sourceID, sourceName: sourceName, headers: headers)
        case .json:
            return parseJSON(text, sourceID: sourceID, sourceName: sourceName, headers: headers)
        }
    }

    // MARK: - TXT

    static func parseTXT(
        _ text: String,
        sourceID: String,
        sourceName: String,
        headers: [String: String]
    ) -> LivePlaylistParseResult {
        var channels: [LiveChannel] = []
        var seen = Set<String>()
        var currentGroup: String?
        var alternates = 0
        var skipped = 0

        for rawLine in lines(text) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                if line.hasPrefix("#EXT") { continue }
                if let group = commentGroup(line) { currentGroup = group }
                continue
            }

            let parts = split(line)
            if line.lowercased().contains(genreMarker) {
                let name = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !name.isEmpty { currentGroup = name }
                continue
            }
            guard parts.count >= 2 else {
                skipped += 1
                continue
            }

            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            var urls: [String] = []
            for part in parts.dropFirst() {
                for piece in part.components(separatedBy: "#") {
                    let candidate = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isHTTPURL(candidate) { urls.append(candidate) }
                }
            }
            guard let first = urls.first,
                  let normalized = URLNormalizer.normalized(first, trimTrailingSlash: false) else {
                skipped += 1
                continue
            }
            alternates += max(0, urls.count - 1)

            let identity = "\(sourceID)|\(normalized)"
            guard seen.insert(identity).inserted else { continue }
            channels.append(LiveChannel(
                id: StableID.make("channel", identity),
                name: name.isEmpty ? URLNormalizer.host(of: normalized) : name,
                url: normalized,
                group: currentGroup,
                sourceID: sourceID,
                sourceName: sourceName,
                headers: headers
            ))
        }

        return LivePlaylistParseResult(
            format: .txt,
            channels: channels,
            alternateURLCount: alternates,
            skippedLineCount: skipped
        )
    }

    static func looksLikeTXT(_ text: String) -> Bool {
        var sawChannel = false
        for rawLine in lines(text).prefix(400) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = split(line)
            if parts.count >= 2, isHTTPURL(parts[1]) { sawChannel = true }
            if line.lowercased().contains(genreMarker), sawChannel { break }
        }
        return sawChannel
    }

    static func commentGroup(_ line: String) -> String? {
        let lower = line.lowercased()
        guard let range = lower.range(of: genreMarker) else { return nil }
        let head = String(line[line.startIndex..<range.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: "#,;| \t"))
        return head.isEmpty ? nil : head
    }

    // MARK: - JSON

    static func parseJSON(
        _ text: String,
        sourceID: String,
        sourceName: String,
        headers: [String: String]
    ) -> LivePlaylistParseResult? {
        guard let json = try? JSONC.parse(text) else { return nil }
        var collected: [([String: Any], String?)] = []
        collectJSON(json, inheritedGroup: nil, into: &collected)
        guard !collected.isEmpty else { return nil }

        var channels: [LiveChannel] = []
        var seen = Set<String>()
        var alternates = 0
        var skipped = 0

        for (dict, inheritedGroup) in collected {
            guard let rawURL = channelURL(in: dict),
                  let normalized = URLNormalizer.normalized(rawURL, trimTrailingSlash: false) else {
                skipped += 1
                continue
            }
            alternates += alternateURLs(in: dict).count

            var channelHeaders = headers
            if let rawHeaders = LooseValue.dictionary(dict["headers"]) {
                for (key, value) in rawHeaders {
                    if let value = LooseValue.string(value) { channelHeaders[key] = value }
                }
            }
            let tvgID = LooseValue.string(dict["tvg-id"]) ?? LooseValue.string(dict["tvgID"])
            let identity = "\(sourceID)|\(normalized)"
            guard seen.insert(identity).inserted else { continue }
            let name = LooseValue.string(dict["name"])
                ?? LooseValue.string(dict["title"])
                ?? LooseValue.string(dict["tvg-name"])
                ?? URLNormalizer.host(of: normalized)
            channels.append(LiveChannel(
                id: StableID.make("channel", identity),
                name: name,
                url: normalized,
                logo: LooseValue.string(dict["logo"])
                    ?? LooseValue.string(dict["tvg-logo"])
                    ?? LooseValue.string(dict["icon"])
                    ?? LooseValue.string(dict["pic"]),
                group: LooseValue.string(dict["group"])
                    ?? LooseValue.string(dict["group-title"])
                    ?? LooseValue.string(dict["category"])
                    ?? inheritedGroup,
                tvgID: tvgID,
                sourceID: sourceID,
                sourceName: sourceName,
                headers: channelHeaders
            ))
        }

        return LivePlaylistParseResult(
            format: .json,
            channels: channels,
            alternateURLCount: alternates,
            skippedLineCount: skipped
        )
    }

    static func collectJSON(
        _ value: Any,
        inheritedGroup: String?,
        into output: inout [([String: Any], String?)]
    ) {
        if let array = value as? [Any] {
            for element in array {
                collectJSON(element, inheritedGroup: inheritedGroup, into: &output)
            }
            return
        }
        guard let dict = value as? [String: Any] else { return }
        let ownGroup = LooseValue.string(dict["group"])
            ?? LooseValue.string(dict["group-title"])
            ?? LooseValue.string(dict["category"])
        let group = ownGroup ?? inheritedGroup

        if let nested = nestedList(in: dict) {
            let nestedGroup = LooseValue.string(dict["name"])
                ?? LooseValue.string(dict["title"])
                ?? group
            for element in nested {
                collectJSON(element, inheritedGroup: nestedGroup, into: &output)
            }
            return
        }
        output.append((dict, group))
    }

    static func nestedList(in dict: [String: Any]) -> [Any]? {
        for key in ["channels", "groups", "lives", "list", "data", "items"] {
            if let array = dict[key] as? [Any] { return array }
        }
        return nil
    }

    static func channelURL(in dict: [String: Any]) -> String? {
        for key in ["url", "playUrl", "playURL", "stream", "src", "link", "address"] {
            if let value = LooseValue.string(dict[key]), isHTTPURL(value) { return value }
        }
        return nil
    }

    static func alternateURLs(in dict: [String: Any]) -> [String] {
        guard let list = dict["urls"] as? [Any] else { return [] }
        return list.compactMap { LooseValue.string($0) }.filter { isHTTPURL($0) }
    }

    static func looksLikeJSONLive(_ text: String) -> Bool {
        guard let json = try? JSONC.parse(text) else { return false }
        // TVBox / LibreTV 配置文件交给配置解析器，避免把点播源误判成频道表。
        if let dict = json as? [String: Any] {
            if dict["sites"] != nil || dict["parses"] != nil || dict["urls"] != nil { return false }
            if dict["api"] != nil || dict["baseUrl"] != nil { return false }
            if let nested = nestedList(in: dict) { return containsChannel(nested) }
            return dict.containsStreamURL
        }
        if let array = json as? [Any] {
            return !array.isEmpty && containsChannel(array)
        }
        return false
    }

    static func containsChannel(_ array: [Any]) -> Bool {
        for element in array {
            guard let dict = element as? [String: Any] else { continue }
            if dict.containsStreamURL { return true }
            if let nested = nestedList(in: dict), containsChannel(nested) { return true }
        }
        return false
    }

    /// 只有真正像流地址时才认定为 JSON 频道表，避免误伤点播接口列表。
    static func isStreamURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        guard isHTTPURL(value) || lower.hasPrefix("rtmp://") || lower.hasPrefix("rtsp://") else {
            return false
        }
        // .m3u8 是常见的频道流；裸 .m3u 更像“订阅清单”，交给配置解析器处理。
        if lower.hasSuffix(".m3u") { return false }
        let hints = [".m3u8", ".flv", ".ts", ".mp4", "/live/", "playlist", "manifest"]
        return hints.contains { lower.contains($0) }
    }

    // MARK: - Shared

    static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    static func split(_ line: String) -> [String] {
        line.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func isHTTPURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }
}

private extension Dictionary where Key == String, Value == Any {
    var containsStreamURL: Bool {
        for key in ["url", "playUrl", "playURL", "stream", "src", "link", "address"] {
            if let value = LooseValue.string(self[key]), LivePlaylist.isStreamURL(value) {
                return true
            }
        }
        if let list = self["urls"] as? [Any] {
            return list.compactMap { LooseValue.string($0) }.contains { LivePlaylist.isStreamURL($0) }
        }
        return false
    }
}
