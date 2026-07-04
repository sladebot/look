import SwiftUI

enum LookTheme {
    /// "Archival Bronze": warm true-neutral charcoals (no blue cast, so the
    /// photographs read truer) with a single bronze identity accent — the
    /// color of frame fittings and archival box clasps. Semantic green/red
    /// are reserved for status.
    enum ColorToken {
        static let darkroom = Color(hex: 0x0D0C0B)
        static let paper = Color(hex: 0x161514)
        static let surface = Color(hex: 0x201E1C)
        static let elevated = Color(hex: 0x292623)
        static let graphite = Color(hex: 0xF5F3EF)
        static let readableSecondary = Color(hex: 0xCDC9C1)
        static let readableTertiary = Color(hex: 0xB3AEA4)
        static let mist = Color(hex: 0x3B3833)
        static let line = Color(hex: 0x474439)
        /// Identity accent for text, icons, chips, eyebrows, selection.
        static let accent = Color(hex: 0xD3A94F)
        /// Deeper bronze for filled controls, so white labels keep contrast.
        static let accentControl = Color(hex: 0x8F7128)
        /// Legacy aliases — older call sites re-point to the single accent.
        static let cyan = accent
        static let amber = accent
        static let success = Color(hex: 0x55BD7F)
        static let danger = Color(hex: 0xD25F51)
    }

    /// Semantic type scale. Every role maps to a Dynamic Type text style so the
    /// whole app scales with the user's preferred reading size. `caption` (SwiftUI
    /// .footnote, 13pt) is the smallest size any readable content may use —
    /// .caption/.caption2 are reserved for glyph sizing on decorative icons.
    enum Typography {
        /// Display roles use the serif design (New York): paired with the
        /// tracked bronze eyebrows they read like gallery wall labels.
        /// Hero text on the connection/setup screen.
        static let display = Font.system(.largeTitle, design: .serif).weight(.bold)
        /// Large on-screen titles (photo filename on the detail sheet).
        static let title = Font.system(.title2, design: .serif).weight(.semibold)
        /// Section-level titles inside a screen.
        static let sectionTitle = Font.system(.title3, design: .serif).weight(.semibold)
        /// Panel headers and row titles.
        static let headline = Font.headline
        /// Primary content.
        static let body = Font.body
        static let bodyEmphasis = Font.body.weight(.semibold)
        /// Supporting copy, descriptions, row subtitles.
        static let secondary = Font.subheadline
        static let secondaryEmphasis = Font.subheadline.weight(.semibold)
        /// Smallest readable size: timestamps, counts, badges.
        static let caption = Font.footnote
        static let captionEmphasis = Font.footnote.weight(.semibold)
        /// Uppercased section eyebrows; always paired with tracking via eyebrow().
        static let overline = Font.footnote.weight(.semibold)
        /// Technical values: paths, URLs, coordinates.
        static let mono = Font.system(.footnote, design: .monospaced)
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
            .font(Typography.title)
            .foregroundStyle(ColorToken.graphite)
    }

    /// The archive-label signature: amber, letter-spaced, uppercase section marker.
    static func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typography.overline)
            .tracking(1.1)
            .foregroundStyle(ColorToken.amber)
    }
}

struct LookScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                LinearGradient(
                    colors: [LookTheme.ColorToken.paper, LookTheme.ColorToken.darkroom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
    }
}

struct LookPanel: ViewModifier {
    var inset: CGFloat = LookTheme.Spacing.medium

    func body(content: Content) -> some View {
        content
            .padding(inset)
            .background(LookTheme.ColorToken.surface,
                        in: RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous)
                    .stroke(LookTheme.ColorToken.line.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
    }
}

struct LookInsetSurface: ViewModifier {
    var radius: CGFloat = LookTheme.Radius.panel

    func body(content: Content) -> some View {
        content
            .background(LookTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(LookTheme.ColorToken.line.opacity(0.55), lineWidth: 1)
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
            .modifier(LookInsetSurface(radius: LookTheme.Radius.control))
    }
}

/// Left accent bar marking a row or image as part of the "filmstrip".
struct LookFilmRail: ViewModifier {
    var color: Color = LookTheme.ColorToken.darkroom
    var isActive = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: LookTheme.Radius.panel,
                                       bottomLeadingRadius: LookTheme.Radius.panel)
                    .fill(color.opacity(isActive ? 1 : 0.7))
                    .frame(width: 3)
            }
    }
}

struct LookStatusBanner: View {
    enum Tone {
        case info, success, warning, error

        var color: Color {
            switch self {
            case .info: return LookTheme.ColorToken.cyan
            case .success: return LookTheme.ColorToken.success
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
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .foregroundStyle(LookTheme.ColorToken.graphite)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(LookTheme.Typography.secondary)
                        .foregroundStyle(LookTheme.ColorToken.readableSecondary)
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
        .background(LookTheme.ColorToken.elevated, in: RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: LookTheme.Radius.panel,
                                   bottomLeadingRadius: LookTheme.Radius.panel)
                .fill(tone.color)
                .frame(width: 3)
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
        .font(LookTheme.Typography.captionEmphasis)
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct LookConnectionPill: View {
    var title = "Tailscale"

    var body: some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(LookTheme.Typography.captionEmphasis)
            .foregroundStyle(LookTheme.ColorToken.success)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(LookTheme.ColorToken.success.opacity(0.11), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(LookTheme.ColorToken.success.opacity(0.22), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }
}

struct LookNavTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(LookTheme.Typography.headline)
                .foregroundStyle(LookTheme.ColorToken.graphite)
                .lineLimit(1)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(LookTheme.Typography.caption)
                    .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                    .lineLimit(1)
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
                .foregroundStyle(LookTheme.ColorToken.readableTertiary)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text(title)
                    .font(LookTheme.Typography.headline)
                    .foregroundStyle(LookTheme.ColorToken.graphite)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(LookTheme.Typography.secondary)
                        .foregroundStyle(LookTheme.ColorToken.readableSecondary)
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
                    .font(LookTheme.Typography.headline)
                    .foregroundStyle(LookTheme.ColorToken.graphite)
                if let message {
                    Text(message)
                        .font(LookTheme.Typography.secondary)
                        .foregroundStyle(LookTheme.ColorToken.readableSecondary)
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
