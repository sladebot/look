import SwiftUI

enum LookTheme {
    enum ColorToken {
        static let darkroom = Color(hex: 0x0E1012)
        static let paper = Color(hex: 0x1F2327)
        static let surface = Color(hex: 0x2A3036)
        static let graphite = Color(hex: 0xEEF3F6)
        static let mist = Color(hex: 0x3D464E)
        static let cyan = Color(hex: 0x2EA8FF)
        static let amber = Color(hex: 0xD9A441)
        static let danger = Color(hex: 0xC94545)
    }

    enum Radius {
        static let panel: CGFloat = 10
        static let control: CGFloat = 8
        static let thumbnail: CGFloat = 3
    }

    enum Spacing {
        static let hairline: CGFloat = 1
        static let tight: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 14
        static let large: CGFloat = 20
        static let screen: CGFloat = 16
    }

    static func title(_ text: String) -> some View {
        Text(text)
            .font(.system(.title2, design: .rounded).weight(.semibold))
            .foregroundStyle(ColorToken.graphite)
    }

    static func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct LookScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(LookTheme.ColorToken.paper.ignoresSafeArea())
    }
}

struct LookPanel: ViewModifier {
    var inset: CGFloat = LookTheme.Spacing.medium

    func body(content: Content) -> some View {
        content
            .padding(inset)
            .background(LookTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous)
                    .stroke(LookTheme.ColorToken.mist, lineWidth: 1)
            }
    }
}

struct LookInsetSurface: ViewModifier {
    var radius: CGFloat = LookTheme.Radius.panel

    func body(content: Content) -> some View {
        content
            .background(LookTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(LookTheme.ColorToken.mist, lineWidth: 1)
            }
    }
}

struct LookTextInputSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, LookTheme.Spacing.medium)
            .padding(.vertical, 12)
            .foregroundStyle(LookTheme.ColorToken.graphite)
            .tint(LookTheme.ColorToken.cyan)
            .modifier(LookInsetSurface())
    }
}

struct LookFilmRail: ViewModifier {
    var color: Color = LookTheme.ColorToken.darkroom
    var isActive = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(color.opacity(isActive ? 1 : 0.75))
                    .frame(width: isActive ? 5 : 3)
            }
            .overlay {
                Rectangle()
                    .stroke(color.opacity(isActive ? 0.9 : 0.18), lineWidth: isActive ? 2 : 1)
            }
    }
}

struct LookStatusBanner: View {
    enum Tone {
        case info, success, warning, error

        var color: Color {
            switch self {
            case .info: return LookTheme.ColorToken.cyan
            case .success: return .green
            case .warning: return LookTheme.ColorToken.amber
            case .error: return LookTheme.ColorToken.danger
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }
    }

    let title: String
    var message: String?
    var tone: Tone = .info
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: LookTheme.Spacing.small) {
            Image(systemName: tone.icon)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: LookTheme.Spacing.tight)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(LookTheme.Spacing.medium)
        .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous)
                .stroke(tone.color.opacity(0.26), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct LookChip: View {
    let title: String
    var systemImage: String?
    var tint: Color = LookTheme.ColorToken.graphite

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.11), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct LookNavTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(LookTheme.ColorToken.graphite)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

struct LookEmptyState: View {
    let title: String
    let systemImage: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: LookTheme.Spacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

struct LookLoadingState: View {
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: LookTheme.Spacing.medium) {
            ProgressView()
            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func lookScreenBackground() -> some View {
        modifier(LookScreenBackground())
    }

    func lookPanel(inset: CGFloat = LookTheme.Spacing.medium) -> some View {
        modifier(LookPanel(inset: inset))
    }

    func lookInsetSurface(radius: CGFloat = LookTheme.Radius.panel) -> some View {
        modifier(LookInsetSurface(radius: radius))
    }

    func lookTextInputSurface() -> some View {
        modifier(LookTextInputSurface())
    }

    func lookFilmRail(color: Color = LookTheme.ColorToken.darkroom, isActive: Bool = false) -> some View {
        modifier(LookFilmRail(color: color, isActive: isActive))
    }
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double(hex & 0xff) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
