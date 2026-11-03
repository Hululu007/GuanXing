import SwiftUI
import UIKit
import GuanXingCore

@MainActor
@Observable
final class DetailModel {
    var detail: VodDetail?
    var isLoading = false
    var errorMessage: String?
    var selectedLine = 0
    var episodeOrder = 0
    var episodeIndex = 0
    var showAllEpisodes = false

    var line: PlayLine? {
        guard let detail, detail.lines.indices.contains(selectedLine) else { return nil }
        return detail.lines[selectedLine]
    }

    var episodes: [Episode] {
        guard let line else { return [] }
        return episodeOrder == 0 ? line.episodes : Array(line.episodes.reversed())
    }

    func load(item: VodItem, app: AppModel) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let source = app.source(for: item.sourceID) else {
            errorMessage = "这个源已被移除，请换一个结果。"
            return
        }
        do {
            detail = try await SourceClient(source: source).detail(vodID: item.vodID, link: item.tag)
            if let history = app.history(for: item), let matchedLine = detail?.lines.firstIndex(where: { $0.name == history.lineName }) {
                selectedLine = matchedLine
                episodeIndex = min(max(history.episodeIndex, 0), max(0, (detail?.lines[matchedLine].episodes.count ?? 1) - 1))
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct DetailView: View {
    let item: VodItem

    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @State private var model = DetailModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                backdrop
                titleBlock
                actionRow
                if let detail = model.detail {
                    infoBlock(detail)
                    linePicker(detail)
                    episodeGrid(detail)
                    if let content = detail.content, !content.isEmpty {
                        synopsis(content)
                    }
                } else if model.isLoading {
                    loadingBlock
                } else if let error = model.errorMessage {
                    EmptyViewState(
                        icon: "exclamationmark.triangle",
                        title: "暂时打不开这部片",
                        message: error,
                        actionTitle: "重新加载"
                    ) {
                        Task { await model.load(item: item, app: app) }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .gxScreenBackground()
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.toggleFavorite(item)
                    triggerHaptic()
                } label: {
                    Image(systemName: app.isFavorite(item) ? "star.fill" : "star")
                        .foregroundStyle(app.isFavorite(item) ? GXTheme.gold : .white)
                }
            }
        }
        .task {
            await model.load(item: item, app: app)
        }
    }

    private var backdrop: some View {
        ZStack(alignment: .bottom) {
            // 同上：竖版海报 .fill 会纵向溢出，clipped 只裁画面不裁命中区，
            // 溢出的部分会盖住导航栏的返回按钮。改用定尺寸容器承载图片。
            Color.clear
                .frame(height: 300)
                .overlay { RemoteImage(url: item.pic) }
                .clipped()
                .blur(radius: 1.2)
                .overlay(Color.black.opacity(0.18))
            LinearGradient(
                colors: [.clear, GXTheme.background.opacity(0.55), GXTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
        }
        .frame(height: 300)
        .padding(.horizontal, -18)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.name)
                .font(.system(size: 27, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                Pill(text: item.sourceName)
                if let remarks = item.remarks, !remarks.isEmpty {
                    Pill(text: remarks, tint: GXTheme.comet)
                }
                if let score = item.score, !score.isEmpty, score != "0.0" {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                        Text(score)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(GXTheme.gold)
                }
            }
            if !item.displayMeta.isEmpty {
                Text(item.displayMeta)
                    .font(.caption)
                    .foregroundStyle(GXTheme.secondaryText)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                playCurrent()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text(playButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GXPrimaryButtonStyle())
            .disabled(model.detail?.lines.isEmpty ?? true)

            Button {
                app.toggleFavorite(item)
            } label: {
                Image(systemName: app.isFavorite(item) ? "star.fill" : "star")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(app.isFavorite(item) ? GXTheme.gold : .white)
                    .frame(width: 46, height: 46)
                    .background(GXTheme.surface, in: Circle())
                    .overlay(Circle().stroke(GXTheme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var playButtonTitle: String {
        if let history = app.history(for: item), history.position > 5 {
            return "继续观看 · \(history.episodeName)"
        }
        return "从第一集开始"
    }

    private func infoBlock(_ detail: VodDetail) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if let director = detail.director, !director.isEmpty {
                infoLine(label: "导演", value: director)
            }
            if let actor = detail.actor, !actor.isEmpty {
                infoLine(label: "主演", value: actor)
            }
            infoLine(label: "线路", value: "\(detail.lines.count) 条播放线路")
        }
        .gxCard(padding: 14)
    }

    private func infoLine(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(GXTheme.secondaryText)
                .frame(width: 32, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func linePicker(_ detail: VodDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "播放线路", subtitle: "线路不可用时可以换一条")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(detail.lines.indices, id: \.self) { index in
                        Button {
                            model.selectedLine = index
                            model.episodeIndex = 0
                        } label: {
                            HStack(spacing: 5) {
                                if index == 0 { Image(systemName: "bolt.fill").font(.caption2) }
                                Text(detail.lines[index].name)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(model.selectedLine == index ? Color.black.opacity(0.84) : .white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(model.selectedLine == index ? GXTheme.gold : GXTheme.surface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func episodeGrid(_ detail: VodDetail) -> some View {
        let episodes = model.episodes
        let visible = model.showAllEpisodes ? episodes : Array(episodes.prefix(30))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "选集", subtitle: "共 \(episodes.count) 集")
                Button {
                    model.episodeOrder = model.episodeOrder == 0 ? 1 : 0
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                        .foregroundStyle(GXTheme.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(GXTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 54), spacing: 8)],
                spacing: 8
            ) {
                ForEach(visible) { episode in
                    let actualIndex = model.line?.episodes.firstIndex(of: episode) ?? 0
                    Button {
                        play(index: actualIndex)
                    } label: {
                        Text(episode.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(GXTheme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(
                                        actualIndex == model.episodeIndex ? GXTheme.gold.opacity(0.75) : GXTheme.stroke,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            if episodes.count > 30 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.showAllEpisodes.toggle()
                    }
                } label: {
                    Text(model.showAllEpisodes ? "收起选集" : "展开全部 \(episodes.count) 集")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GXTheme.gold)
                }
            }
        }
    }

    private func synopsis(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "剧情简介")
            Text(content)
                .font(.subheadline)
                .foregroundStyle(GXTheme.secondaryText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .gxCard(padding: 15)
    }

    private var loadingBlock: some View {
        VStack(spacing: 12) {
            ProgressView().tint(GXTheme.gold)
            Text("正在解析播放线路…")
                .font(.caption)
                .foregroundStyle(GXTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private func playCurrent() {
        guard let detail = model.detail, let line = model.line, !line.episodes.isEmpty else { return }
        let history = app.history(for: item)
        let index = history.map { min($0.episodeIndex, line.episodes.count - 1) } ?? model.episodeIndex
        let start = history?.position ?? 0
        router.push(.player(PlayerLaunch(
            item: item,
            detail: detail,
            lineName: line.name,
            episodeIndex: max(0, index),
            startPosition: start
        )))
    }

    private func play(index: Int) {
        guard let detail = model.detail, let line = model.line else { return }
        model.episodeIndex = index
        router.push(.player(PlayerLaunch(
            item: item,
            detail: detail,
            lineName: line.name,
            episodeIndex: index,
            startPosition: 0
        )))
    }

    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
