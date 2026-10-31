import Foundation

public enum M3UParser {
    public static func parse(
        _ text: String,
        sourceID: String,
        sourceName: String,
        headers: [String: String] = [:]
    ) -> [LiveChannel] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var channels: [LiveChannel] = []
        var pendingAttributes: [String: String]?
        var pendingName: String?
        var pendingGroup: String?
        var pendingLogo: String?
        var pendingTvgID: String?
        var seen = Set<String>()

        func addChannel(url rawURL: String) {
            let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, !url.hasPrefix("#") else { return }
            guard let normalized = URLNormalizer.normalized(url, trimTrailingSlash: false) else { return }
            let name = pendingName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (name?.isEmpty == false ? name! : URLNormalizer.host(of: normalized))
            let identity = "\(sourceID)|\(normalized)"
            guard !seen.contains(identity) else { return }
            seen.insert(identity)

            var channelHeaders = headers
            if let userAgent = pendingAttributes?["http-user-agent"], !userAgent.isEmpty {
                channelHeaders["User-Agent"] = userAgent
            }
            if let referrer = pendingAttributes?["http-referrer"] ?? pendingAttributes?["http-referer"],
               !referrer.isEmpty {
                channelHeaders["Referer"] = referrer
            }

            channels.append(LiveChannel(
                id: StableID.make("channel", identity),
                name: displayName,
                url: normalized,
                logo: pendingLogo,
                group: pendingGroup,
                tvgID: pendingTvgID,
                sourceID: sourceID,
                sourceName: sourceName,
                headers: channelHeaders
            ))
            pendingAttributes = nil
            pendingName = nil
            pendingGroup = nil
            pendingLogo = nil
            pendingTvgID = nil
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXTINF:") || line.hasPrefix("#EXTINF ") {
                let attributes = parseAttributes(line)
                pendingAttributes = attributes
                pendingTvgID = attributes["tvg-id"]
                pendingLogo = attributes["tvg-logo"]
                pendingGroup = attributes["group-title"]
                if let comma = line.lastIndex(of: ",") {
                    let title = String(line[line.index(after: comma)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    pendingName = title.isEmpty ? nil : title
                }
                continue
            }
            if line.hasPrefix("#EXTGRP:") {
                let group = line.replacingOccurrences(of: "#EXTGRP:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !group.isEmpty { pendingGroup = group }
                continue
            }
            if line.hasPrefix("#EXTVLCOPT:") {
                let option = line.replacingOccurrences(of: "#EXTVLCOPT:", with: "")
                let parts = option.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    var attributes = pendingAttributes ?? [:]
                    if parts[0].lowercased().contains("user-agent") {
                        attributes["http-user-agent"] = parts[1]
                    } else if parts[0].lowercased().contains("referrer") || parts[0].lowercased().contains("referer") {
                        attributes["http-referrer"] = parts[1]
                    }
                    pendingAttributes = attributes
                }
                continue
            }
            if line.hasPrefix("#") { continue }
            if URLNormalizer.normalized(line, trimTrailingSlash: false) != nil {
                addChannel(url: line)
            }
        }
        return channels
    }

    static func parseAttributes(_ line: String) -> [String: String] {
        var output: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z0-9_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#) else {
            return output
        }
        let source = line as NSString
        for match in regex.matches(in: line, range: NSRange(location: 0, length: source.length)) {
            let key = source.substring(with: match.range(at: 1)).lowercased()
            let value: String
            if match.range(at: 2).location != NSNotFound {
                value = source.substring(with: match.range(at: 2))
            } else {
                value = source.substring(with: match.range(at: 3))
            }
            output[key] = value
        }
        return output
    }

    public static func groupChannels(_ channels: [LiveChannel]) -> [(String, [LiveChannel])] {
        var groups: [String: [LiveChannel]] = [:]
        var order: [String] = []
        for channel in channels {
            let group = channel.group?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未分组"
            if groups[group] == nil {
                groups[group] = []
                order.append(group)
            }
            groups[group]?.append(channel)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
