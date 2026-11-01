import AVFoundation
import Foundation
import Observation
import SwiftUI
import UIKit
import GuanXingCore

@MainActor
@Observable
final class PlayerModel {
    let player = AVPlayer()

    var detail: VodDetail
    var currentLineIndex: Int
    var currentEpisodeIndex: Int
    var isLoading = false
    var isPlaying = false
    var isBuffering = false
    var errorMessage: String?
    var duration: Double = 0
    var position: Double = 0
    var speed: Double = 1.0
    var controlsVisible = true
    var isFullscreen = false
    var showEpisodePicker = false
    var showSpeedPicker = false
    /// 已缓冲时长（秒），用于展示缓冲进度。
    var bufferedDuration: Double = 0
    /// 最近一次播放的实测码率，单位 kbps，用于估算缓冲速度。
    var bitrateKbps: Int = 0
    /// 手势拖动时的预览进度；有值时时间轴显示它，松手才真正 seek。
    var previewPosition: Double?
    /// 屏幕亮度（0...1），左侧上下滑动控制。
    var brightness: Double = 0.5
    /// 系统音量（0...1），右侧上下滑动控制。
    var volume: Double = 0.5
    var bufferedText: String {
        guard bufferedDuration > 0 else { return "" }
        let remaining = max(0, bufferedDuration - position)
        guard remaining > 0 else { return "" }
        return String(format: "缓冲 %.0fs", remaining)
    }

    var sourceName: String { source.name }

    private let item: VodItem
    private let source: VodSource
    private let parsers: [ParseEndpoint]
    private let autoPlay: Bool
    private let autoNext: Bool
    private var initialPosition: Double
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var controlsTask: Task<Void, Never>?
    /// 进入播放器时的原始屏幕亮度，退出时还原。
    private var baselineBrightness: Double?

    init(
        launch: PlayerLaunch,
        source: VodSource,
        parsers: [ParseEndpoint],
        defaultSpeed: Double,
        autoPlay: Bool = true,
        autoNext: Bool = true
    ) {
        self.detail = launch.detail
        self.currentEpisodeIndex = max(0, launch.episodeIndex)
        self.currentLineIndex = launch.detail.lines.firstIndex(where: { $0.name == launch.lineName }) ?? 0
        self.initialPosition = launch.startPosition
        self.item = launch.item
        self.source = source
        self.parsers = parsers
        self.speed = defaultSpeed
        self.autoPlay = autoPlay
        self.autoNext = autoNext
        configureAudio()
    }

    func teardown() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        rateObserver?.invalidate()
        rateObserver = nil
        controlsTask?.cancel()
        controlsTask = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        bufferedDuration = 0
        bitrateKbps = 0
    }

    var line: PlayLine {
        guard detail.lines.indices.contains(currentLineIndex) else {
            return PlayLine(name: "线路", episodes: [])
        }
        return detail.lines[currentLineIndex]
    }

    var episode: Episode? {
        line.episodes.indices.contains(currentEpisodeIndex) ? line.episodes[currentEpisodeIndex] : nil
    }

    var hasNext: Bool { currentEpisodeIndex + 1 < line.episodes.count }
    var hasPrevious: Bool { currentEpisodeIndex > 0 }
    var titleText: String { item.name }
    var subtitleText: String { "\(line.name) · \(episode?.name ?? "正片")" }

    func prepare() async {
        guard player.currentItem == nil else { return }
        syncSystemLevels()
        observePlayer()
        await loadCurrentEpisode()
    }

    func loadCurrentEpisode() async {
        guard let episode else {
            errorMessage = "这一条线路没有可播放的剧集"
            return
        }
        isLoading = true
        errorMessage = nil
        duration = 0
        player.pause()

        let request = await PlaybackResolver.resolve(
            episodeURL: episode.url,
            source: source,
            parsers: parsers
        )
        guard let url = URL(string: request.url) else {
            isLoading = false
            errorMessage = "播放地址无法识别"
            return
        }

        let asset: AVURLAsset
        if request.headers.isEmpty {
            asset = AVURLAsset(url: url)
        } else {
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": request.headers])
        }
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 8
        observe(playerItem)
        player.replaceCurrentItem(with: playerItem)
        isLoading = false
        showControlsTemporarily()
    }

    func play() {
        if player.currentItem == nil && !isLoading {
            Task { await loadCurrentEpisode() }
            return
        }
        player.play()
        player.rate = Float(speed)
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
            showControlsTemporarily()
        } else {
            play()
        }
    }

    func seek(to seconds: Double) {
        let target = min(max(seconds, 0), max(duration, 0))
        position = target
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func skip(_ delta: Double) {
        seek(to: position + delta)
        showControlsTemporarily()
    }

    func setSpeed(_ value: Double) {
        speed = value
        if isPlaying { player.rate = Float(value) }
        showSpeedPicker = false
    }
    // MARK: - 亮度与音量（手势）

    func setBrightness(_ value: Double) {
        let next = min(max(value, 0), 1)
        brightness = next
        ScreenBrightness.set(next)
    }

    func setVolume(_ value: Double) {
        let next = min(max(value, 0), 1)
        volume = next
        SystemVolume.set(next)
    }

    /// 重新读取系统真实亮度/音量，避免和用户刚在控制中心改过的值不一致。
    /// 第一次同步时记下原始亮度，退出播放器时按它还原。
    func syncSystemLevels() {
        let current = ScreenBrightness.current
        if baselineBrightness == nil { baselineBrightness = current }
        brightness = current
        volume = SystemVolume.current
    }

    /// 退出播放器时把亮度还原成进入前的值。
    func restoreBrightness() {
        if let baselineBrightness {
            ScreenBrightness.set(baselineBrightness)
        }
        baselineBrightness = nil
    }

    func nextEpisode() {
        guard hasNext else { return }
        currentEpisodeIndex += 1
        initialPosition = 0
        Task { await loadCurrentEpisode() }
    }

    func previousEpisode() {
        guard hasPrevious else {
            seek(to: 0)
            return
        }
        currentEpisodeIndex -= 1
        initialPosition = 0
        Task { await loadCurrentEpisode() }
    }

    func select(line index: Int) {
        guard detail.lines.indices.contains(index) else { return }
        currentLineIndex = index
        currentEpisodeIndex = 0
        initialPosition = 0
        showEpisodePicker = false
        Task { await loadCurrentEpisode() }
    }

    func select(line lineIndex: Int, episode episodeIndex: Int) {
        guard detail.lines.indices.contains(lineIndex) else { return }
        let episodes = detail.lines[lineIndex].episodes
        currentLineIndex = lineIndex
        currentEpisodeIndex = episodes.isEmpty ? 0 : max(0, min(episodeIndex, episodes.count - 1))
        initialPosition = 0
        showEpisodePicker = false
        Task { await loadCurrentEpisode() }
    }

    func select(episode index: Int) {
        guard line.episodes.indices.contains(index) else { return }
        currentEpisodeIndex = index
        initialPosition = 0
        showEpisodePicker = false
        Task { await loadCurrentEpisode() }
    }

    func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible { showControlsTemporarily() }
    }

    func showControlsTemporarily() {
        withAnimation(.easeOut(duration: 0.18)) {
            controlsVisible = true
        }
        controlsTask?.cancel()
        controlsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, let self else { return }
            guard self.isPlaying, !self.showEpisodePicker, !self.showSpeedPicker else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                self.controlsVisible = false
            }
        }
    }

    func progressSnapshot() -> (line: PlayLine, episodeIndex: Int, position: Double, duration: Double)? {
        guard duration > 0, position > 3 else { return nil }
        return (line, currentEpisodeIndex, position, duration)
    }

    private func configureAudio() {
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? session.setActive(true)
    }

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let seconds = time.seconds
                if seconds.isFinite {
                    self.position = max(0, seconds)
                }
                if let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.updateNetworkMetrics()
            }
        }
        rateObserver = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.timeControlStatus == .playing
                self?.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard let finished = notification.object as? AVPlayerItem,
                      finished === self.player.currentItem else { return }
                if self.autoNext && self.hasNext {
                    self.nextEpisode()
                } else {
                    self.player.pause()
                }
            }
        }
    }

    private func observe(_ playerItem: AVPlayerItem) {
        statusObservation?.invalidate()
        statusObservation = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.errorMessage = nil
                    self.isLoading = false
                    self.updateAccessLog()
                    let shouldResume = self.initialPosition > 3
                    if shouldResume {
                        self.player.seek(
                            to: CMTime(seconds: self.initialPosition, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                        self.initialPosition = 0
                    }
                    if self.autoPlay || shouldResume {
                        self.player.play()
                        self.player.rate = Float(self.speed)
                    }
                case .failed:
                    self.isLoading = false
                    let code = (item.error as NSError?)?.code ?? 0
                    self.errorMessage = "这条线路播放失败（\(code)），可以切到其他线路。"
                default:
                    break
                }
            }
        }
    }

    private func updateNetworkMetrics() {
        guard let item = player.currentItem else {
            bufferedDuration = 0
            return
        }
        bufferedDuration = Self.bufferedSeconds(of: item)
        if let event = player.currentItem?.accessLog()?.events.last, event.numberOfBytesTransferred > 0 {
            bitrateKbps = Int(event.observedBitrate / 1000)
        }
    }

    private func updateAccessLog() {
        if let event = player.currentItem?.accessLog()?.events.last, event.numberOfBytesTransferred > 0 {
            bitrateKbps = Int(event.observedBitrate / 1000)
        }
    }

    static func bufferedSeconds(of item: AVPlayerItem) -> Double {
        guard let range = item.loadedTimeRanges.last?.timeRangeValue else { return 0 }
        let end = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
        return end.isFinite ? max(0, end) : 0
    }
}
