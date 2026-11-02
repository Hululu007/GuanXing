import Foundation

// MARK: - AppGet / AppQi 解析

extension AppCmsSpider {
    func appCmsCategories(prefix: String) async throws -> [VodCategory] {
        let initPath = prefix == "getappapi.index" ? "/getappapi.index/initV119" : "/qijiappapi.index/initV120"
        let data = try await call(path: initPath, body: "")
        var output: [VodCategory] = []
        var seen = Set<String>()
        // 有的版本把分类放在 type_list，有的放在 categories
        for key in ["type_list", "categories"] {
            guard let array = data[key] as? [[String: Any]] else { continue }
            for entry in array {
                let id = LooseValue.string(entry["type_id"]) ?? LooseValue.string(entry["id"]) ?? ""
                let name = LooseValue.string(entry["type_name"]) ?? LooseValue.string(entry["name"]) ?? ""
                guard !id.isEmpty, !name.isEmpty, seen.insert(id).inserted else { continue }
                output.append(VodCategory(id: id, name: name))
            }
            if !output.isEmpty { break }
        }
        return output
    }

    func appCmsList(prefix: String, typeID: String?, page: Int) async throws -> [VodItem] {
        let body: String
        if let typeID, !typeID.isEmpty {
            body = jsonBody(["type_id": typeID, "page": String(page)])
        } else {
            let data = try await call(
                path: "/\(prefix == "getappapi.index" ? "getappapi.index/initV119" : "qijiappapi.index/initV120")",
                body: ""
            )
            return parseAppCmsList(data, key: "recommend_list")
        }
        let data = try await call(
            path: "/\(prefix)/typeFilterVodList?page=\(page)",
            body: body
        )
        return parseAppCmsList(data, key: "recommend_list")
    }

    func parseAppCmsList(_ data: [String: Any], key: String) -> [VodItem] {
        let array = (data[key] as? [[String: Any]])
            ?? (data["search_list"] as? [[String: Any]])
            ?? (data["list"] as? [[String: Any]])
            ?? []
        return array.compactMap { entry -> VodItem? in
            guard let vodID = LooseValue.string(entry["vod_id"]), !vodID.isEmpty else { return nil }
            let name = LooseValue.string(entry["vod_name"]) ?? ""
            guard !name.isEmpty else { return nil }
            return VodItem(
                sourceID: source.id,
                sourceName: source.name,
                vodID: vodID,
                name: name,
                pic: LooseValue.string(entry["vod_pic"]),
                remarks: LooseValue.string(entry["vod_remarks"]),
                year: LooseValue.string(entry["vod_year"]),
                area: LooseValue.string(entry["vod_area"]),
                typeName: LooseValue.string(entry["vod_class"]),
                score: LooseValue.string(entry["vod_score"])
            )
        }
    }

    func parseAppCmsDetail(_ data: [String: Any], vodID: String) throws -> VodDetail {
        // vodDetail 有时返回 {vod:...} 有时直接返回影片对象
        let vod = (data["vod"] as? [String: Any]) ?? data
        let name = LooseValue.string(vod["vod_name"]) ?? ""
        let item = VodItem(
            sourceID: source.id,
            sourceName: source.name,
            vodID: vodID,
            name: name.isEmpty ? "未命名" : name,
            pic: LooseValue.string(vod["vod_pic"]),
            remarks: LooseValue.string(vod["vod_remarks"]),
            year: LooseValue.string(vod["vod_year"]),
            area: LooseValue.string(vod["vod_area"]),
            typeName: LooseValue.string(vod["vod_class"]),
            score: LooseValue.string(vod["vod_score"])
        )
        let lines = parsePlayList(vod["vod_play_list"])
        guard !lines.isEmpty else {
            throw GuanXingError.empty("该源没有返回可用播放地址")
        }
        return VodDetail(
            item: item,
            content: LooseValue.string(vod["vod_content"]),
            director: LooseValue.string(vod["vod_director"]),
            actor: LooseValue.string(vod["vod_actor"]),
            lines: lines
        )
    }

    /// `vod_play_list` 的两种形态：
    /// 1. `[{player_info:{show:...}, urls:[{name, url}]}]`
    /// 2. `[{name: "线路名", list: [{name, url}]}]` / 直接字符串
    func parsePlayList(_ raw: Any?) -> [PlayLine] {
        if let array = raw as? [[String: Any]] {
            var lines: [PlayLine] = []
            for (index, group) in array.enumerated() {
                let info = group["player_info"] as? [String: Any]
                var lineName = LooseValue.string(info?["show"])
                    ?? LooseValue.string(group["name"])
                    ?? LooseValue.string(group["title"])
                    ?? "线路\(index + 1)"
                lineName = lineName.trimmingCharacters(in: .whitespacesAndNewlines)
                if lineName.isEmpty { lineName = "线路\(index + 1)" }

                let rawURLs = (group["urls"] as? [[String: Any]])
                    ?? (group["list"] as? [[String: Any]])
                    ?? []
                var episodes: [Episode] = []
                var seen = Set<String>()
                for (epIndex, entry) in rawURLs.enumerated() {
                    guard let url = LooseValue.string(entry["url"]), !url.isEmpty else { continue }
                    guard seen.insert(url).inserted else { continue }
                    let title = LooseValue.string(entry["name"]).flatMap { $0.isEmpty ? nil : $0 }
                        ?? "第\(epIndex + 1)集"
                    episodes.append(Episode(name: title, url: url))
                }
                if !episodes.isEmpty {
                    lines.append(PlayLine(name: lineName, episodes: episodes))
                }
            }
            return lines
        }

        // 兼容 "线路名$$$url1#url2" 形式
        if let text = raw as? String, !text.isEmpty {
            var lines: [PlayLine] = []
            for (index, chunk) in text.components(separatedBy: "$$$").enumerated() {
                let parts = chunk.components(separatedBy: "#")
                let episodes = parts.enumerated().compactMap { offset, element -> Episode? in
                    let pieces = element.components(separatedBy: "$")
                    guard pieces.count >= 2 else { return nil }
                    let url = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !url.isEmpty else { return nil }
                    return Episode(name: pieces[0].isEmpty ? "第\(offset + 1)集" : pieces[0], url: url)
                }
                if !episodes.isEmpty {
                    lines.append(PlayLine(name: "线路\(index + 1)", episodes: episodes))
                }
            }
            return lines
        }
        return []
    }
}
