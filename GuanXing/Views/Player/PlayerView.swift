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
            model?.player.pause()
            OrientationHelper.lockPortrait()
        }
    }

    private func content(_ model: PlayerModel) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                if !model.isFullscreen {
                    topBar(model)
                }
                videoArea(model)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                if !model.isFullscreen {
                    episodePanel(model)
                }
                Spacer(minLength: 0)
            }
        }
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
            PlayerSurface(player: model.player)
            if model.isBuffering || model.isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
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
        .contentShape(Rectangle())
        .onTapGesture {
            model.toggleControls()
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
                HStack {
                    Text(timeText(dragPosition ?? model.position))
                    Spacer()
                    Text(timeText(model.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.84))

                GeometryReader { proxy in
                    let progress = model.duration > 0
                        ? min(max((dragPosition ?? model.position) / model.duration, 0), 1)
                        : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.24)).frame(height: 4)
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
                                guard model.duration > 0 else { return }
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
            .padding(.bottom, model.isFullscreen ? 18 : 10)
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.62), .clear, .black.opacity(0.74)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .center) {
            if model.showSpeedPicker {
                speedPicker(model)
            }
        }
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
        withAnimation(.easeInOut(duration: 0.25)) {
            model.isFullscreen = true
            model.controlsVisible = true
        }
        OrientationHelper.lockLandscape()
        model.showControlsTemporarily()
    }

    private func exitFullscreen(_ model: PlayerModel) {
        withAnimation(.easeInOut(duration: 0.25)) {
            model.isFullscreen = false
            model.controlsVisible = true
        }
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

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainer {
        let view = PlayerContainer()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerContainer, context: Context) {
        uiView.playerLayer.player = player
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
