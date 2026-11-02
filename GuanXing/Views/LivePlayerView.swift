import AVFoundation
import SwiftUI
import GuanXingCore

struct LivePlayerView: View {
    let channel: LiveChannel

    @Environment(AppModel.self) private var app
    @State private var player = AVPlayer()
    @State private var isPlaying = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var statusObservation: NSKeyValueObservation?
    @State private var fullscreen = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // 与点播播放器一致：用几何值算尺寸，不靠 if/else 换布局，
            // 否则切全屏时 PlayerSurface 会被重建，表现为黑屏或画面不铺满。
            // .ignoresSafeArea 必须挂在 GeometryReader 上，量到的才是整屏尺寸。
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    if !fullscreen {
                        topBar
                    }
                    if fullscreen {
                        playerArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        playerArea
                            .frame(width: proxy.size.width, height: proxy.size.width * 9.0 / 16.0)
                    }
                    if !fullscreen {
                        infoPanel
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea(edges: fullscreen ? Edge.Set.all : Edge.Set())
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(fullscreen)
        .onAppear {
            WindowBackdrop.installBlack()
            load()
        }
        .onDisappear {
            player.pause()
            WindowBackdrop.restore()
            OrientationHelper.lockPortrait()
        }
    }

    private var playerArea: some View {
        ZStack {
            PlayerSurface(player: player, fill: fullscreen)
            if isLoading {
                ProgressView().tint(.white).scaleEffect(1.2)
            }
            if let errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.title2)
                        .foregroundStyle(GXTheme.gold)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("重新连接") {
                        load()
                    }
                    .buttonStyle(GXSecondaryButtonStyle())
                }
                .padding(18)
                .background(.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(20)
            }
            VStack {
                Spacer()
                HStack {
                    Button {
                        isPlaying ? player.pause() : player.play()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.82))
                            .frame(width: 50, height: 50)
                            .background(GXTheme.gold, in: Circle())
                    }
                    Spacer()
                    Button {
                        app.toggleFavoriteChannel(channel)
                    } label: {
                        Image(systemName: app.isFavoriteChannel(channel) ? "star.fill" : "star")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(app.isFavoriteChannel(channel) ? GXTheme.gold : .white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    Button {
                        toggleFullscreen()
                    } label: {
                        Image(systemName: fullscreen
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .contentShape(Rectangle())
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(channel.group ?? "直播") · \(channel.sourceName)")
                    .font(.caption2)
                    .foregroundStyle(GXTheme.secondaryText)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(GXTheme.danger).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(GXTheme.danger)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(GXTheme.danger.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                RemoteImage(url: channel.logo)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(channel.group ?? "未分组")
                        .font(.caption)
                        .foregroundStyle(GXTheme.secondaryText)
                    Text(channel.sourceName)
                        .font(.caption2)
                        .foregroundStyle(GXTheme.gold)
                }
                Spacer()
            }
            Text("直播信号由第三方源提供，频道可能随时调整。若无法播放，可以回到列表选择同名的备用频道。")
                .font(.caption)
                .foregroundStyle(GXTheme.secondaryText)
                .lineSpacing(3)
            if !channel.isLikelyPlayable {
                Label("该频道可能是 FLV 流，iOS 播放器不直接支持", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(GXTheme.gold)
            }
        }
        .gxCard(padding: 16)
        .padding(18)
    }

    private func load() {
        isLoading = true
        errorMessage = nil
        statusObservation?.invalidate()
        guard let url = URL(string: channel.url) else {
            errorMessage = "频道地址无效"
            isLoading = false
            return
        }
        var headers = channel.headers
        if headers["User-Agent"] == nil {
            headers["User-Agent"] = GuanXingHTTPUserAgent.value
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    isLoading = false
                    player.play()
                    isPlaying = true
                case .failed:
                    isLoading = false
                    errorMessage = "直播流连接失败，可能已失效。"
                default:
                    break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
    }

    private func toggleFullscreen() {
        withAnimation(.easeInOut(duration: 0.25)) {
            fullscreen.toggle()
        }
        // 与点播播放器保持一致：先切布局再请求旋转，避免旋转前重算一次竖屏几何。
        if fullscreen {
            OrientationHelper.lockLandscape()
        } else {
            OrientationHelper.lockPortrait()
        }
    }
}
