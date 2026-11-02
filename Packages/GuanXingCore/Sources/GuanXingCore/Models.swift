import Foundation

public enum SourceOrigin: String, Codable, Sendable {
    case builtin
    case imported
    case manual
}

public struct VodSource: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var api: String
    public var detailURL: String?
    public var origin: SourceOrigin
    public var isEnabled: Bool
    public var isAdult: Bool
    public var isSearchable: Bool
    public var headers: [String: String]
    /// 需要专用协议的源（APP 采集 / 规则 DSL）在这里挂一份解析配置。
    public var spider: SpiderBinding?
    public var createdAt: Date

    public init(
        id: String,
        name: String,
        api: String,
        detailURL: String? = nil,
        origin: SourceOrigin = .manual,
        isEnabled: Bool = true,
        isAdult: Bool = false,
        isSearchable: Bool = true,
        headers: [String: String] = [:],
        spider: SpiderBinding? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.api = api
        self.detailURL = detailURL
        self.origin = origin
        self.isEnabled = isEnabled
        self.isAdult = isAdult
        self.isSearchable = isSearchable
        self.headers = headers
        self.spider = spider
        self.createdAt = createdAt
    }

    public var host: String { URLNormalizer.host(of: api) }
    public var referer: String { URLNormalizer.origin(of: api) ?? api }
}

public struct LiveSource: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var url: String
    public var epg: String?
    public var origin: SourceOrigin
    public var isEnabled: Bool
    public var createdAt: Date

    public init(
        id: String,
        name: String,
        url: String,
        epg: String? = nil,
        origin: SourceOrigin = .manual,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.epg = epg
        self.origin = origin
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

public struct ParseEndpoint: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var url: String
    public var type: Int

    public init(id: String, name: String, url: String, type: Int = 1) {
        self.id = id
        self.name = name
        self.url = url
        self.type = type
    }
}

public struct VodCategory: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var parentID: String?

    public init(id: String, name: String, parentID: String? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
    }
}

public struct VodItem: Codable, Hashable, Identifiable, Sendable {
    public var sourceID: String
    public var sourceName: String
    public var vodID: String
    public var name: String
    public var pic: String?
    public var remarks: String?
    public var year: String?
    public var area: String?
    public var typeName: String?
    public var score: String?
    public var tag: String?

    public var id: String { "\(sourceID)|\(vodID)" }
    public var displayMeta: String {
        [year, area, typeName].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: "  ·  ")
    }

    public init(
        sourceID: String,
        sourceName: String,
        vodID: String,
        name: String,
        pic: String? = nil,
        remarks: String? = nil,
        year: String? = nil,
        area: String? = nil,
        typeName: String? = nil,
        score: String? = nil,
        tag: String? = nil
    ) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.vodID = vodID
        self.name = name
        self.pic = pic
        self.remarks = remarks
        self.year = year
        self.area = area
        self.typeName = typeName
        self.score = score
        self.tag = tag
    }
}

public struct Episode: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(name)|\(url)" }
    public var name: String
    public var url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

public struct PlayLine: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var episodes: [Episode]

    public init(name: String, episodes: [Episode]) {
        self.name = name
        self.episodes = episodes
    }
}

public struct VodDetail: Codable, Hashable, Sendable {
    public var item: VodItem
    public var content: String?
    public var director: String?
    public var actor: String?
    public var lines: [PlayLine]

    public init(
        item: VodItem,
        content: String? = nil,
        director: String? = nil,
        actor: String? = nil,
        lines: [PlayLine]
    ) {
        self.item = item
        self.content = content
        self.director = director
        self.actor = actor
        self.lines = lines
    }
}

public struct VodPage: Sendable {
    public var items: [VodItem]
    public var page: Int
    public var pageCount: Int
    public var total: Int

    public init(items: [VodItem], page: Int = 1, pageCount: Int = 1, total: Int = 0) {
        self.items = items
        self.page = page
        self.pageCount = pageCount
        self.total = total
    }
}

public struct LiveChannel: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var url: String
    public var logo: String?
    public var group: String?
    public var tvgID: String?
    public var sourceID: String
    public var sourceName: String
    public var headers: [String: String]

    public var isLikelyPlayable: Bool {
        let lower = url.lowercased()
        return !lower.hasSuffix(".flv") && !lower.contains(".flv?")
    }

    public init(
        id: String,
        name: String,
        url: String,
        logo: String? = nil,
        group: String? = nil,
        tvgID: String? = nil,
        sourceID: String,
        sourceName: String,
        headers: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.logo = logo
        self.group = group
        self.tvgID = tvgID
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.headers = headers
    }
}

public enum SourceHealthState: String, Codable, Sendable {
    case unknown
    case checking
    case healthy
    case slow
    case failed
}

public struct SourceHealth: Codable, Sendable, Equatable {
    public var state: SourceHealthState
    public var latency: TimeInterval?
    public var message: String?
    public var checkedAt: Date?

    public init(
        state: SourceHealthState = .unknown,
        latency: TimeInterval? = nil,
        message: String? = nil,
        checkedAt: Date? = nil
    ) {
        self.state = state
        self.latency = latency
        self.message = message
        self.checkedAt = checkedAt
    }
}

public struct ImportReport: Codable, Sendable, Equatable {
    public var format: String
    public var sourceCount: Int
    public var liveCount: Int
    public var parserCount: Int
    public var skipped: Int
    public var skippedReasons: [String: Int]
    public var repositoryCount: Int
    public var messages: [String]

    public init(
        format: String,
        sourceCount: Int,
        liveCount: Int,
        parserCount: Int = 0,
        skipped: Int = 0,
        skippedReasons: [String: Int] = [:],
        repositoryCount: Int = 0,
        messages: [String] = []
    ) {
        self.format = format
        self.sourceCount = sourceCount
        self.liveCount = liveCount
        self.parserCount = parserCount
        self.skipped = skipped
        self.skippedReasons = skippedReasons
        self.repositoryCount = repositoryCount
        self.messages = messages
    }

    public var summary: String {
        var parts: [String] = []
        if sourceCount > 0 { parts.append("\(sourceCount) 个点播源") }
        if liveCount > 0 { parts.append("\(liveCount) 个直播源") }
        if parserCount > 0 { parts.append("\(parserCount) 个解析接口") }
        if parts.isEmpty { parts.append("没有可用条目") }
        if skipped > 0 { parts.append("跳过 \(skipped) 条") }
        return parts.joined(separator: "，")
    }
}

public struct ImportedConfig: Sendable {
    public var name: String?
    public var sources: [VodSource]
    public var liveSources: [LiveSource]
    public var parsers: [ParseEndpoint]
    public var repositoryURLs: [String]
    public var report: ImportReport

    public init(
        name: String? = nil,
        sources: [VodSource],
        liveSources: [LiveSource],
        parsers: [ParseEndpoint] = [],
        repositoryURLs: [String] = [],
        report: ImportReport
    ) {
        self.name = name
        self.sources = sources
        self.liveSources = liveSources
        self.parsers = parsers
        self.repositoryURLs = repositoryURLs
        self.report = report
    }
}

public struct FavoriteItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String { item.id }
    public var item: VodItem
    public var addedAt: Date

    public init(item: VodItem, addedAt: Date = Date()) {
        self.item = item
        self.addedAt = addedAt
    }
}

public struct HistoryEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String { item.id }
    public var item: VodItem
    public var lineName: String
    public var episodeIndex: Int
    public var episodeName: String
    public var position: Double
    public var duration: Double
    public var updatedAt: Date

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    public init(
        item: VodItem,
        lineName: String,
        episodeIndex: Int,
        episodeName: String,
        position: Double,
        duration: Double,
        updatedAt: Date = Date()
    ) {
        self.item = item
        self.lineName = lineName
        self.episodeIndex = episodeIndex
        self.episodeName = episodeName
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }
}

public struct FavoriteChannel: Codable, Hashable, Identifiable, Sendable {
    public var id: String { channel.id }
    public var channel: LiveChannel
    public var addedAt: Date

    public init(channel: LiveChannel, addedAt: Date = Date()) {
        self.channel = channel
        self.addedAt = addedAt
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var autoNext: Bool
    public var rememberProgress: Bool
    public var autoPlay: Bool
    public var defaultSpeed: Double
    public var preferHighCompatibility: Bool
    /// 已删除的内置源 ID。内置源可以删除，删除后不会被「更新内置源」重新加回来。
    public var removedBuiltinSourceIDs: [String]
    /// 用户当前采用的内置源目录版本，用于提示有新版可更新。
    public var builtinCatalogVersion: String

    public init(
        autoNext: Bool = true,
        rememberProgress: Bool = true,
        autoPlay: Bool = true,
        defaultSpeed: Double = 1.0,
        preferHighCompatibility: Bool = true,
        removedBuiltinSourceIDs: [String] = [],
        builtinCatalogVersion: String = BuiltinSources.catalogVersion
    ) {
        self.autoNext = autoNext
        self.rememberProgress = rememberProgress
        self.autoPlay = autoPlay
        self.defaultSpeed = defaultSpeed
        self.preferHighCompatibility = preferHighCompatibility
        self.removedBuiltinSourceIDs = removedBuiltinSourceIDs
        self.builtinCatalogVersion = builtinCatalogVersion
    }

    private enum CodingKeys: String, CodingKey {
        case autoNext, rememberProgress, autoPlay, defaultSpeed, preferHighCompatibility
        case removedBuiltinSourceIDs, builtinCatalogVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoNext = try c.decodeIfPresent(Bool.self, forKey: .autoNext) ?? true
        rememberProgress = try c.decodeIfPresent(Bool.self, forKey: .rememberProgress) ?? true
        autoPlay = try c.decodeIfPresent(Bool.self, forKey: .autoPlay) ?? true
        defaultSpeed = try c.decodeIfPresent(Double.self, forKey: .defaultSpeed) ?? 1.0
        preferHighCompatibility = try c.decodeIfPresent(Bool.self, forKey: .preferHighCompatibility) ?? true
        removedBuiltinSourceIDs = try c.decodeIfPresent([String].self, forKey: .removedBuiltinSourceIDs) ?? []
        builtinCatalogVersion = try c.decodeIfPresent(String.self, forKey: .builtinCatalogVersion)
            ?? BuiltinSources.catalogVersion
    }
}

public struct SearchOutcome: Sendable {
    public var source: VodSource
    public var items: [VodItem]
    public var error: String?
    public var elapsed: TimeInterval

    public init(source: VodSource, items: [VodItem], error: String? = nil, elapsed: TimeInterval = 0) {
        self.source = source
        self.items = items
        self.error = error
        self.elapsed = elapsed
    }
}
