import Foundation
import GuanXingCore

struct PersistenceStore {
    struct Snapshot {
        var sources: [VodSource]
        var liveSources: [LiveSource]
        var parsers: [ParseEndpoint]
        var favorites: [FavoriteItem]
        var history: [HistoryEntry]
        var favoriteChannels: [FavoriteChannel]
        var settings: AppSettings
        var health: [String: SourceHealth]
        var repositoryURLs: [String]
    }

    private struct Payload: Codable {
        var schemaVersion: Int
        var sources: [VodSource]
        var liveSources: [LiveSource]
        var parsers: [ParseEndpoint]
        var favorites: [FavoriteItem]
        var history: [HistoryEntry]
        var favoriteChannels: [FavoriteChannel]
        var settings: AppSettings
        var health: [String: SourceHealth]
        var repositoryURLs: [String]
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = root.appendingPathComponent("GuanXing", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("library.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> Snapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return Snapshot(
                sources: BuiltinSources.vod,
                liveSources: BuiltinSources.live,
                parsers: [],
                favorites: [],
                history: [],
                favoriteChannels: [],
                settings: AppSettings(),
                health: [:],
                repositoryURLs: []
            )
        }
        return Snapshot(
            sources: payload.sources,
            liveSources: payload.liveSources,
            parsers: payload.parsers,
            favorites: payload.favorites,
            history: payload.history,
            favoriteChannels: payload.favoriteChannels,
            settings: payload.settings,
            health: payload.health,
            repositoryURLs: payload.repositoryURLs
        )
    }

    func save(_ snapshot: Snapshot) {
        let payload = Payload(
            schemaVersion: 1,
            sources: snapshot.sources,
            liveSources: snapshot.liveSources,
            parsers: snapshot.parsers,
            favorites: snapshot.favorites,
            history: snapshot.history,
            favoriteChannels: snapshot.favoriteChannels,
            settings: snapshot.settings,
            health: snapshot.health,
            repositoryURLs: snapshot.repositoryURLs
        )
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
