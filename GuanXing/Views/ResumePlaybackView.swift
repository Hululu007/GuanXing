import SwiftUI
import GuanXingCore

/// 从「观看记录」直接续播。
/// 记录里只有集数与秒数，没有完整线路信息，所以这里先按 vodID 拉一次详情，
/// 找到同名线路后再进播放器，避免让用户先经过详情页多点一次。
struct ResumePlaybackView: View {
    let entry: HistoryEntry

    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @State private var errorMessage: String?
    @State private var didStart = false

    var body: some View {
        ZStack {
            GXTheme.background.ignoresSafeArea()
            if let errorMessage {
                EmptyViewState(
                    icon: "exclamationmark.triangle",
                    title: "续播失败",
                    message: errorMessage,
                    actionTitle: "看详情"
                ) {
                    router.push(.detail(entry.item))
                }
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(GXTheme.gold)
                    Text("正在续播《\(entry.item.name)》")
                        .font(.subheadline)
                        .foregroundStyle(GXTheme.secondaryText)
                    Text("\(entry.episodeName) · 已看 \(Int(entry.progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(GXTheme.secondaryText.opacity(0.8))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await start() }
    }

    private func start() async {
        guard !didStart else { return }
        didStart = true
        guard let source = app.source(for: entry.item.sourceID) else {
            errorMessage = "这条记录所属的片源已被删除，换一个源再看。"
            return
        }
        do {
            let detail = try await SourceClient(source: source)
                .detail(vodID: entry.item.vodID, link: entry.item.tag)
            let lines = detail.lines.filter { !$0.episodes.isEmpty }
            guard let line = lines.first(where: { $0.name == entry.lineName }) ?? lines.first else {
                errorMessage = "这个源已经没有可播放的线路了。"
                return
            }
            let index = min(max(entry.episodeIndex, 0), line.episodes.count - 1)
            router.push(.player(PlayerLaunch(
                item: entry.item,
                detail: detail,
                lineName: line.name,
                episodeIndex: index,
                startPosition: entry.position
            )))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
