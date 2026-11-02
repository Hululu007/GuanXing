import SwiftUI
import UIKit
import GuanXingCore

actor ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var tasks: [String: Task<UIImage?, Never>] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 180 * 1024 * 1024
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        memory.countLimit = 240
    }

    func image(for urlString: String, referer: String? = nil) async -> UIImage? {
        if let cached = memory.object(forKey: urlString as NSString) { return cached }
        if let task = tasks[urlString] { return await task.value }

        let task = Task<UIImage?, Never> {
            defer { tasks[urlString] = nil }
            guard let url = URL(string: urlString) else { return nil }
            var request = URLRequest(url: url)
            request.setValue(GuanXingHTTPUserAgent.value, forHTTPHeaderField: "User-Agent")
            if let referer {
                request.setValue(referer, forHTTPHeaderField: "Referer")
            }
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = UIImage(data: data) else { return nil }
            memory.setObject(image, forKey: urlString as NSString)
            return image
        }
        tasks[urlString] = task
        return await task.value
    }
}

enum GuanXingHTTPUserAgent {
    static let value = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}

struct RemoteImage: View {
    let url: String?
    var referer: String?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [GXTheme.surfaceElevated, GXTheme.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    if failed {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(GXTheme.secondaryText.opacity(0.6))
                    } else {
                        ProgressView()
                            .tint(GXTheme.secondaryText)
                    }
                }
            }
        }
        .task(id: url) {
            image = nil
            failed = false
            guard let url, !url.isEmpty else {
                failed = true
                return
            }
            let loaded = await ImagePipeline.shared.image(for: url, referer: referer)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.22)) {
                image = loaded
                failed = loaded == nil
            }
        }
    }
}

struct PosterCard: View {
    let item: VodItem
    var width: CGFloat?
    var showSource = true

    private let ratio: CGFloat = 0.7

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 海报宽度永远等于父级给的列宽，高度按 0.7 的宽高比推出来。
            // 之前写死 210pt：列宽一旦小于 148pt，.fill 就会把左右裁掉，
            // 首页第一列贴屏幕边，看起来就是「边缘显示不全」。
            poster
                .overlay(alignment: .topLeading) {
                    if let score = item.score, !score.isEmpty, score != "0.0", score != "0" {
                        Text(score)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.black.opacity(0.78))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(GXTheme.gold, in: Capsule())
                            .padding(7)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let remarks = item.remarks, !remarks.isEmpty {
                        Text(remarks)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.62), in: Capsule())
                            .padding(7)
                    }
                }
            Text(item.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showSource {
                Text(item.sourceName)
                    .font(.caption2)
                    .foregroundStyle(GXTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var poster: some View {
        if let width {
            posterImage
                .frame(width: width, height: width / ratio)
        } else {
            // 宽度直接取 Grid 的列宽，高度由 0.7 的比例换算。
            // Color.clear 会接受外层给的宽度提案，aspectRatio 再据此定高，
            // 图片作为 overlay 正好铺满这块区域：宽度不吃掉任何一点。
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .overlay { posterImage }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var posterImage: some View {
        RemoteImage(url: item.pic)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SourceHealthBadge: View {
    let health: SourceHealth?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        switch health?.state {
        case .healthy: return GXTheme.success
        case .slow: return GXTheme.gold
        case .failed: return GXTheme.danger
        case .checking: return GXTheme.comet
        case .unknown, .none: return GXTheme.secondaryText
        }
    }

    private var text: String {
        switch health?.state {
        case .healthy:
            if let latency = health?.latency { return String(format: "%.1fs", latency) }
            return "可用"
        case .slow:
            if let latency = health?.latency { return String(format: "%.1fs 较慢", latency) }
            return "较慢"
        case .failed: return "连接失败"
        case .checking: return "检测中"
        case .unknown, .none: return "未检测"
        }
    }
}
