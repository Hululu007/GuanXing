import SwiftUI

enum GXTheme {
    static let background = Color(red: 0.035, green: 0.047, blue: 0.075)
    static let surface = Color(red: 0.075, green: 0.09, blue: 0.13)
    static let surfaceElevated = Color(red: 0.105, green: 0.123, blue: 0.17)
    static let stroke = Color.white.opacity(0.085)
    static let secondaryText = Color(red: 0.61, green: 0.65, blue: 0.73)
    static let gold = Color(red: 0.96, green: 0.73, blue: 0.35)
    static let goldSoft = Color(red: 0.83, green: 0.60, blue: 0.29)
    static let comet = Color(red: 0.47, green: 0.75, blue: 0.96)
    static let success = Color(red: 0.39, green: 0.82, blue: 0.62)
    static let danger = Color(red: 0.96, green: 0.42, blue: 0.42)

    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.11, blue: 0.20),
            Color(red: 0.13, green: 0.09, blue: 0.12),
            background
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct StarfieldBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<58 {
                    let seed = CGFloat(index)
                    let x = (seed * 37.31).truncatingRemainder(dividingBy: 1.0)
                    let y = (seed * 61.73).truncatingRemainder(dividingBy: 1.0)
                    let twinkle = CGFloat((sin(time * 0.55 + Double(seed) * 1.91) + 1) * 0.5)
                    let radius: CGFloat = 0.55 + (seed.truncatingRemainder(dividingBy: 1.7)) * 1.05
                    let rect = CGRect(
                        x: x * size.width,
                        y: y * size.height,
                        width: radius,
                        height: radius
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color.white.opacity(0.10 + twinkle * 0.26))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct GXCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(GXTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(GXTheme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func gxCard(padding: CGFloat = 16, radius: CGFloat = 18) -> some View {
        modifier(GXCardModifier(padding: padding, radius: radius))
    }

    func gxScreenBackground() -> some View {
        background(GXTheme.background.ignoresSafeArea())
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(GXTheme.secondaryText)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GXTheme.gold)
            }
        }
    }
}

struct Pill: View {
    let text: String
    var tint: Color = GXTheme.gold

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct EmptyViewState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(GXTheme.gold)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(GXTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(GXPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

struct GXPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color(red: 0.09, green: 0.07, blue: 0.035))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [GXTheme.gold, GXTheme.goldSoft],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct GXSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(GXTheme.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(GXTheme.stroke, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
