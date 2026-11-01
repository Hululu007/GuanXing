import Foundation

public enum LiveService {
    public static func load(source: LiveSource) async throws -> [LiveChannel] {
        let text: String
        if source.url.hasPrefix("file://"), let url = URL(string: source.url) {
            let data = try Data(contentsOf: url)
            guard let decoded = TextDecoder.decode(data) else {
                throw GuanXingError.decode("本地播放列表编码无法识别")
            }
            text = decoded
        } else {
            text = try await GuanXingHTTP.getText(source.url, timeout: 20)
        }
        return try channels(in: text, source: source)
    }

    public static func channels(in text: String, source: LiveSource) throws -> [LiveChannel] {
        guard let result = LivePlaylist.parse(
            text,
            sourceID: source.id,
            sourceName: source.name
        ) else {
            throw GuanXingError.decode("直播源不是 M3U / TXT / JSON 格式")
        }
        guard !result.channels.isEmpty else {
            throw GuanXingError.empty("直播源中没有可用频道")
        }
        return result.channels
    }

    public static func loadAll(sources: [LiveSource]) async -> (channels: [LiveChannel], errors: [String]) {
        await withTaskGroup(of: (LiveSource, Result<[LiveChannel], Error>).self) { group in
            for source in sources where source.isEnabled {
                group.addTask {
                    do {
                        return (source, .success(try await load(source: source)))
                    } catch {
                        return (source, .failure(error))
                    }
                }
            }
            var channels: [LiveChannel] = []
            var errors: [String] = []
            for await (source, result) in group {
                switch result {
                case .success(let list):
                    channels.append(contentsOf: list)
                case .failure(let error):
                    errors.append("\(source.name)：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
                }
            }
            return (channels, errors)
        }
    }
}
