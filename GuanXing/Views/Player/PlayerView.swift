import AVFoundation
import SwiftUI
import UIKit
import GuanXingCore

struct PlayerView: View {
    let launch: PlayerLaunch

    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @State private var model: PlayerModel?
    @State private var dragPosition: Double?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .tint(GXTheme.gold)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(model?.isFullscreen ?? false)
        .onAppear {
            if model == nil, let source = app.source(for: launch.item.sourceID) {
                model = PlayerModel(
                    launch: launch,
                    source: source,
                    parsers: app.parsers,
                    defaultSpeed: app.settings.defaultSpeed,
                    autoPlay: app.settings.autoPlay,
                    autoNext: app.settings.autoNext
                )
            }
            Task { await model?.prepare() }
        }
        .onDisappear {
            saveProgress()
            model?.teardown()
            // 把手势改过的亮度还原成进入播放器前的值。
            model?.restoreBrightness()
            // 只在真的横屏时才强制回竖屏，避免打断用户本来就在竖屏的状态。
            if OrientationHelper.isLandscape {
                OrientationHelper.lockPortrait()
            }
        }
    }

    private func content(_ model: PlayerModel) -> some View {
        // 视频层必须始终占住同一个结构位置。
        // 之前用 if/else 切换两套布局，进入全屏时 AVPlayerLayer 会被整块重建，
        // 表现就是黑屏、或者画面不跟着铺满。
        VStack(spacing: 0) {
            if !model.isFullscreen {
                topBar(model)
            }
            videoArea(model)
                .modifier(VideoAreaLayout(fullscreen: model.isFullscreen))
            if !model.isFullscreen {
                episodePanel(model)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(edges: model.isFullscreen ? .all : [])
        .persistentSystemOverlays(model.isFullscreen ? .hidden : .automatic)
    }

    private func topBar(_ model: PlayerModel) -> some View {
        HStack(spacing: 12) {
            Button {
                saveProgress()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.titleText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.subtitleText)
                    .font(.caption2)
                    .foregroundStyle(GXTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                app.toggleFavorite(launch.item)
            } label: {
                Image(systemName: app.isFavorite(launch.item) ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(app.isFavorite(launch.item) ? GXTheme.gold : .white)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(GXTheme.background)
    }

    private func videoArea(_ model: PlayerModel) -> some View {
        ZStack {
            PlayerSurface(player: model.player, fill: model.isFullscreen)
            // 手势层压在视频上，但控制在控件层之下，避免挡住按钮点击。
            PlayerGestureLayer(model: model)
            if model.isBuffering || model.isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
                    .allowsHitTesting(false)
            }
            if let error = model.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(GXTheme.gold)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await model.loadCurrentEpisode() }
                    }
                    .buttonStyle(GXSecondaryButtonStyle())
                }
                .padding(18)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(20)
            }
            if model.controlsVisible {
                controlsOverlay(model)
                    .transition(.opacity)
            }
        }
    }

    private func controlsOverlay(_ model: PlayerModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                if model.isFullscreen {
                    Button {
                        exitFullscreen(model)
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                }
                Spacer()
                Button {
                    model.showEpisodePicker = true
                    model.controlsVisible = false
                } label: {
                    Image(systemName: "rectangle.stack")
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            Spacer()

            HStack(spacing: 34) {
                Button { model.skip(-10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .frame(width: 58, height: 58)
                        .background(GXTheme.gold, in: Circle())
                }
                Button { model.skip(10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(timeText(model.previewPosition ?? dragPosition ?? model.position))
                    Spacer()
                    if !model.bufferedText.isEmpty {
                        Text(model.bufferedText)
                            .foregroundStyle(GXTheme.gold.opacity(0.85))
                    }
                    if model.bitrateKbps > 0 {
                        Text("\(model.bitrateKbps) kbps")
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Text(timeText(model.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.84))

                GeometryReader { proxy in
                    let shown = model.previewPosition ?? dragPosition ?? model.position
                    let progress = model.duration > 0
                        ? min(max(shown / model.duration, 0), 1)
                        : 0
                    let bufferedRatio = model.duration > 0
                        ? min(max(model.bufferedDuration / model.duration, 0), 1)
                        : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.24)).frame(height: 4)
                        Capsule()
                            .fill(Color.white.opacity(0.42))
                            .frame(width: max(0, proxy.size.width * bufferedRatio), height: 4)
                        Capsule().fill(GXTheme.gold).frame(width: max(0, proxy.size.width * progress), height: 4)
                        Circle()
                            .fill(GXTheme.gold)
                            .frame(width: 12, height: 12)
                            .offset(x: max(0, proxy.size.width * progress - 6))
                    }
                    .frame(height: 18)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard model.duration > 0, proxy.size.width > 1 else { return }
                                model.previewPosition = nil
                                let ratio = min(max(value.location.x / proxy.size.width, 0), 1)
                                dragPosition = ratio * model.duration
                            }
                            .onEnded { _ in
                                if let dragPosition {
                                    model.seek(to: dragPosition)
                                    self.dragPosition = nil
                                    model.showControlsTemporarily()
                                }
                            }
                    )
                }
                .frame(height: 18)

                HStack {
                    Button {
                        model.showSpeedPicker.toggle()
                    } label: {
                        Text(speedLabel(model.speed))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.13), in: Capsule())
                    }
                    Spacer()
                    Button { model.previousEpisode() } label: {
                        Image(systemName: "backward.end.fill")
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Button { model.nextEpisode() } label: {
                        Image(systemName: "forward.end.fill")
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    Button {
                        model.isFullscreen ? exitFullscreen(model) : enterFullscreen(model)
                    } label: {
                        Image(systemName: model.isFullscreen
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(.white)
                    }
                }
                .font(.system(size: 15))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, model.isFullscreen ? 26 : 10)
        }
        .background {
            // 背景不参与点击判定，否则会挡住下面的手势层。
            LinearGradient(
                colors: [.black.opacity(0.62), .clear, .black.opacity(0.74)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .safeAreaPadding(controlInsets(model))
        .overlay(alignment: .center) {
            if model.showSpeedPicker {
                speedPicker(model)
            }
        }
    }

    /// 全屏时避开刘海与底部指示条，竖屏时不需要额外内边距。
    private func controlInsets(_ model: PlayerModel) -> EdgeInsets {
        model.isFullscreen
            ? EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
            : EdgeInsets()
    }

    private func speedPicker(_ model: PlayerModel) -> some View {
        HStack(spacing: 4) {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                Button {
                    model.setSpeed(value)
                } label: {
                    Text(speedLabel(value))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.speed == value ? Color.black.opacity(0.82) : .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(model.speed == value ? GXTheme.gold : Color.white.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(7)
        .background(.black.opacity(0.82), in: Capsule())
    }

    private func episodePanel(_ model: PlayerModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.line.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(model.line.episodes.count) 集 · \(model.sourceName)")
                        .font(.caption2)
                        .foregroundStyle(GXTheme.secondaryText)
                }
                Spacer()
                Button {
                    model.showEpisodePicker = true
                } label: {
                    Text("选集")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GXTheme.gold)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.line.episodes.indices, id: \.self) { index in
                        let episode = model.line.episodes[index]
                        let current = index == model.currentEpisodeIndex
                        Button {
                            model.select(episode: index)
                        } label: {
                            Text(episode.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(current ? Color.black.opacity(0.84) : .white.opacity(0.85))
                                .lineLimit(1)
                                .frame(minWidth: 52)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    current ? GXTheme.gold : GXTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let content = model.detail.content, !content.isEmpty {
                Text(content)
                    .font(.caption)
                    .foregroundStyle(GXTheme.secondaryText)
                    .lineLimit(4)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .sheet(isPresented: Binding(
            get: { model.showEpisodePicker },
            set: { model.showEpisodePicker = $0 }
        )) {
            EpisodePickerSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func enterFullscreen(_ model: PlayerModel) {
        // 先让系统允许横屏，再切布局，避免几何更新被旧 mask 拒绝。
        OrientationHelper.lockLandscape()
        withAnimation(.easeInOut(duration: 0.25)) {
            model.isFullscreen = true
            model.controlsVisible = true
        }
        // 重新读一次真实亮度/音量，避免和用户刚在控制中心改过的值不一致。
        model.syncSystemLevels()
        model.showControlsTemporarily()
    }

    private func exitFullscreen(_ model: PlayerModel) {
        withAnimation(.easeInOut(duration: 0.25)) {
            model.isFullscreen = false
            model.controlsVisible = true
        }
        model.previewPosition = nil
        OrientationHelper.lockPortrait()
    }

    private func saveProgress() {
        guard let model = self.model, let snapshot = model.progressSnapshot() else { return }
        app.recordProgress(
            item: launch.item,
            line: snapshot.line,
            episodeIndex: snapshot.episodeIndex,
            position: snapshot.position,
            duration: snapshot.duration
        )
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func speedLabel(_ value: Double) -> String {
        value == floor(value) ? "\(Int(value))x" : "\(value)x"
    }
}

/// 竖屏锁定 16:9 并留黑边，全屏时铺满可用空间。
/// 用 ViewModifier 而不是 if/else 包住 videoArea，保证视图身份不变、AVPlayerLayer 不被重建。
private struct VideoAreaLayout: ViewModifier {
    let fullscreen: Bool

    func body(content: Content) -> some View {
        if fullscreen {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    /// 全屏时按屏幕比例铺满（会裁掉少量边缘），竖屏时保持完整画面。
    var fill: Bool = false

    func makeUIView(context: Context) -> PlayerContainer {
        let view = PlayerContainer()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerContainer, context: Context) {
        uiView.playerLayer.player = player
        let gravity: AVLayerVideoGravity = fill ? .resizeAspectFill : .resizeAspect
        if uiView.playerLayer.videoGravity != gravity {
            uiView.playerLayer.videoGravity = gravity
        }
    }

    final class PlayerContainer: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            playerLayer.videoGravity = .resizeAspect
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
