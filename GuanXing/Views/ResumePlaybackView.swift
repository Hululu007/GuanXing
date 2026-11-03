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
            if let failure = errorMessage {
                EmptyViewState(
                    icon: "exclamationmark.triangle",
                    title: "续播失败",
                    message: failure,
                    actionTitle: "换源重找"
                ) {
                    didStart = false
                    errorMessage = nil
                    Task { await start() }
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
        // 先走原源。源被删、域名挂了、条目下架都会失败，
        // 这些情况不再直接给用户看报错，而是回落到「按片名在其它源重找」。
        if let source = app.source(for: entry.item.sourceID),
           let launched = await launch(from: source, detailItem: entry.item) {
            router.push(.player(launched))
            return
        }
        await fallbackByName()
    }

    /// 在原源上拉详情并跳播放器。成功返回 nil 以外的结果。
    private func launch(from source: VodSource, detailItem: VodItem) async -> PlayerLaunch? {
        do {
            let detail = try await SourceClient(source: source)
                .detail(vodID: detailItem.vodID, link: detailItem.tag)
            let lines = detail.lines.filter { !$0.episodes.isEmpty }
            guard let line = lines.first(where: { $0.name == entry.lineName }) ?? lines.first else {
                return nil
            }
            let index = min(max(entry.episodeIndex, 0), line.episodes.count - 1)
            return PlayerLaunch(
                item: detailItem,
                detail: detail,
                lineName: line.name,
                episodeIndex: index,
                startPosition: entry.position
            )
        } catch {
            return nil
        }
    }

    /// 原源不可用时，按片名在其它已启用源里重新找一部同名的。
    /// 换源后集数编号不一定对得上，所以从头播而不是硬套旧集数。
    private func fallbackByName() async {
        let targets = app.enabledSources.filter {
            $0.id != entry.item.sourceID && $0.isSearchable && !$0.isAdult
        }
        guard !targets.isEmpty else {
            errorMessage = "这条记录所属的片源已不可用，也没有其它源能接上。"
            return
        }
        let result = await SearchService.search(keyword: entry.item.name, sources: targets, limitPerSource: 8)
        // 优先同名且同源的条目，其次任意同名条目。
        let candidates = result.items.filter {
            $0.name.caseInsensitiveCompare(entry.item.name) == .orderedSame
        } + result.items.filter {
            $0.name.caseInsensitiveCompare(entry.item.name) != .orderedSame
        }
        for candidate in candidates.prefix(6) {
            guard let source = app.source(for: candidate.sourceID),
                  let launched = await launch(from: source, detailItem: candidate) else { continue }
            // 换源后旧集数/旧秒数不可信，从头开始。
            router.push(.player(PlayerLaunch(
                item: launched.item,
                detail: launched.detail,
                lineName: launched.lineName,
                episodeIndex: 0,
                startPosition: 0
            )))
            return
        }
        errorMessage = "原源已失效，其它源也没找到能播的《\(entry.item.name)》。"
    }
}
