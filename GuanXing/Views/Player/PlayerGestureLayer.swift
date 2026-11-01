import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// 播放器手势层。
///
/// - 左半屏上下滑：亮度
/// - 右半屏上下滑：音量
/// - 任意位置左右滑：进度
struct PlayerGestureLayer: View {
    let model: PlayerModel

    @State private var mode: DragMode = .none
    @State private var startValue: Double = 0
    @State private var hud: HUD?
    @State private var hudToken = 0

    private enum DragMode {
        case none
        case brightness
        case volume
        case seek
    }

    private struct HUD: Equatable {
        enum Kind: Equatable {
            case brightness
            case volume
            case seek
        }

        var kind: Kind
        /// 0...1，用于画进度条。
        var ratio: Double
        var text: String
    }

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(drag(in: proxy.size))
                .onTapGesture {
                    model.toggleControls()
                }
                .overlay {
                    if let hud {
                        hudView(hud)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if mode == .none {
                    decide(at: value.startLocation, size: size, translation: value.translation)
                }
                guard size.width > 1, size.height > 1 else { return }

                switch mode {
                case .seek:
                    guard model.duration > 0 else { return }
                    // 横跨整屏约等于 120 秒，长片短片的操作精度都还能接受。
                    let span = min(max(model.duration, 60), 120)
                    let delta = Double(value.translation.width / size.width) * span
                    let target = min(max(startValue + delta, 0), model.duration)
                    model.previewPosition = target
                    let ratio = model.duration > 0 ? target / model.duration : 0
                    show(HUD(
                        kind: .seek,
                        ratio: ratio,
                        text: "\(timeText(target)) / \(timeText(model.duration))"
                    ))
                case .brightness:
                    let next = clamp(startValue - Double(value.translation.height / size.height))
                    model.setBrightness(next)
                    show(HUD(kind: .brightness, ratio: next, text: "\(Int(next * 100))%"))
                case .volume:
                    let next = clamp(startValue - Double(value.translation.height / size.height))
                    model.setVolume(next)
                    show(HUD(kind: .volume, ratio: next, text: "\(Int(next * 100))%"))
                case .none:
                    break
                }
            }
            .onEnded { _ in
                if mode == .seek, let target = model.previewPosition {
                    model.seek(to: target)
                }
                model.previewPosition = nil
                mode = .none
                hideSoon()
            }
    }

    private func decide(at location: CGPoint, size: CGSize, translation: CGSize) {
        let horizontal = abs(translation.width) > abs(translation.height) * 1.2
        if horizontal {
            mode = .seek
            startValue = model.position
        } else if location.x < size.width / 2 {
            mode = .brightness
            startValue = model.brightness
        } else {
            mode = .volume
            startValue = model.volume
        }
    }

    private func show(_ value: HUD) {
        hudToken += 1
        if hud != value {
            hud = value
        }
    }

    private func hideSoon() {
        hudToken += 1
        let token = hudToken
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard token == hudToken else { return }
            hud = nil
        }
    }

    private func hudView(_ value: HUD) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol(value.kind))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                Text(value.text)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 116, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(GXTheme.gold)
                        .frame(width: 116 * min(max(value.ratio, 0), 1), height: 4)
                }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func symbol(_ kind: HUD.Kind) -> String {
        switch kind {
        case .brightness: return "sun.max.fill"
        case .volume: return "speaker.wave.2.fill"
        case .seek: return "goforward"
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// 用隐藏的 MPVolumeView 改写系统音量。
@MainActor
enum SystemVolume {
    private static let volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: CGRect(x: -3000, y: -3000, width: 1, height: 1))
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        return view
    }()

    private static var installed = false

    static var current: Double {
        prepare()
        if let slider = slider {
            return Double(slider.value)
        }
        return Double(AVAudioSession.sharedInstance().outputVolume)
    }

    static func set(_ value: Double) {
        prepare()
        guard let slider else { return }
        slider.value = Float(min(max(value, 0), 1))
        slider.sendActions(for: .touchUpInside)
    }

    private static var slider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    private static func prepare() {
        guard !installed, let window = keyWindow else { return }
        window.addSubview(volumeView)
        installed = true
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

/// 屏幕亮度读写。
@MainActor
enum ScreenBrightness {
    static var current: Double {
        Double(screen?.brightness ?? 0.5)
    }

    static func set(_ value: Double) {
        screen?.brightness = CGFloat(min(max(value, 0), 1))
    }

    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }
}
