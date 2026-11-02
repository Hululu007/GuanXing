import Foundation

// MARK: - AppRJ（热播）

extension AppCmsSpider {
    static let rjSalt = "7gp0bnd2sr85ydii2j32pcypscoc4w6c7g5spl"

    /// 安卓端用 `MD5(salt + timestamp)` 作为 sign，POST 表单提交。
    func rjCall(path: String, fields: [String: String]) async throws -> [String: Any] {
        let stamp = String(Int(Date().timeIntervalSince1970))
        var form = fields
        form["timestamp"] = stamp
        form["sign"] = AppCmsCrypto.md5Hex(Self.rjSalt + stamp)
        let body = form
            .map { key, value in "\(escape(key))=\(escape(value))" }
            .sorted()
            .joined(separator: "&")
        let headers = [
            "User-Agent": "okhttp-okgo/jeasonlzy",
            "Content-Type": "application/x-www-form-urlencoded"
        ]
        let text = try await post(config.root + path, body: body, headers: headers)
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw TransportError(message: "返回内容不是 JSON")
        }
        return object
    }

    func escape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    func rjCategories() async throws -> [VodCategory] {
        let data = try await rjCall(path: "/v3/type/top_type", fields: [:])
        let payload = (data["data"] as? [String: Any]) ?? data
        let list = (payload["list"] as? [[String: Any]]) ?? []
        return list.compactMap { entry in
            guard let id = LooseValue.string(entry["type_id"]), !id.isEmpty else { return nil }
            let name = LooseValue.string(entry["type_name"]) ?? "分类"
            return VodCategory(id: id, name: name)
        }
    }

    func rjList(typeID: String?, page: Int) async throws -> [VodItem] {
        var fields: [String: String] = ["page": String(page), "limit": "12"]
        if let typeID, !typeID.isEmpty {
            fields["type_id"] = typeID
        }
        // 首页没有单独的推荐接口时，退回第一个分类，避免空列表
        if fields["type_id"] == nil {
            let categories = try await rjCategories()
            if let first = categories.first { fields["type_id"] = first.id }
        }
        let data = try await rjCall(path: "/v3/home/type_search", fields: fields)
        let payload = (data["data"] as? [String: Any]) ?? data
        return parseRJList(payload["list"])
    }

    func rjSearch(keyword: String, page: Int) async throws -> [VodItem] {
        let data = try await rjCall(
            path: "/v3/home/search",
            fields: ["keyword": keyword, "limit": "12", "page": String(page)]
        )
        let payload = (data["data"] as? [String: Any]) ?? data
        return parseRJList(payload["list"])
    }

    func parseRJList(_ raw: Any?) -> [VodItem] {
        let array = raw as? [[String: Any]] ?? []
        return array.compactMap { entry -> VodItem? in
            guard let vodID = LooseValue.string(entry["vod_id"]), !vodID.isEmpty else { return nil }
            let name = LooseValue.string(entry["vod_name"]) ?? ""
            guard !name.isEmpty else { return nil }
            let pic = LooseValue.string(entry["vod_pic"]).flatMap { $0.isEmpty ? nil : $0 }
                ?? LooseValue.string(entry["vod_pic_thumb"])
            return VodItem(
                sourceID: source.id,
                sourceName: source.name,
                vodID: vodID,
                name: name,
                pic: pic,
                remarks: LooseValue.string(entry["vod_remarks"]),
                year: LooseValue.string(entry["vod_year"]),
                area: LooseValue.string(entry["vod_area"]),
                typeName: LooseValue.string(entry["vod_class"]),
                score: LooseValue.string(entry["vod_score"])
            )
        }
    }

    func rjDetail(vodID: String) async throws -> VodDetail {
        let data = try await rjCall(path: "/v3/home/vod_details", fields: ["vod_id": vodID])
        let vod = (data["data"] as? [String: Any]) ?? data
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
}

