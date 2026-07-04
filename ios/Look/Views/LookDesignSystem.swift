import SwiftUI

enum LookTheme {
    /// "Selenium": the cool neutral black of film base and selenium-toned
    /// silver — the archival process photographers use to make prints
    /// permanent. One muted selenium-violet identity accent; semantic
    /// green/red are reserved for status.
    enum ColorToken {
        static let darkroom = Color(hex: 0x0B0B0D)
        static let paper = Color(hex: 0x141416)
        static let surface = Color(hex: 0x1D1D21)
        static let elevated = Color(hex: 0x26262B)
        static let graphite = Color(hex: 0xF2F2F5)
        static let readableSecondary = Color(hex: 0xC7C7CE)
        static let readableTertiary = Color(hex: 0xA9A9B2)
        static let mist = Color(hex: 0x37373E)
        static let line = Color(hex: 0x414149)
        /// Identity accent for text, icons, chips, eyebrows, selection.
        static let accent = Color(hex: 0xB7A9E6)
        /// Deeper violet for filled controls, so white labels keep contrast.
        static let accentControl = Color(hex: 0x6F5FBE)
        /// Legacy aliases — older call sites re-point to the single accent.
        static let cyan = accent
        static let amber = accent
        static let success = Color(hex: 0x4CC27E)
        static let danger = Color(hex: 0xE0655A)
    }

    /// Semantic type scale. Every role maps to a Dynamic Type text style so the
    /// whole app scales with the user's preferred reading size. `caption` (SwiftUI
    /// .footnote, 13pt) is the smallest size any readable content may use —
    /// .caption/.caption2 are reserved for glyph sizing on decorative icons.
    enum Typography {
        /// Hero text on the connection/setup screen.
        static let display = Font.largeTitle.weight(.bold)
        /// Large on-screen titles (photo filename on the detail sheet).
        static let title = Font.title2.weight(.semibold)
        /// Section-level titles inside a screen.
        static let sectionTitle = Font.title3.weight(.semibold)
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
        /// Monospaced — the "edge print" signature, echoing the frame markings
        /// on film stock.
        static let overline = Font.system(.footnote, design: .monospaced).weight(.semibold)
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

    /// The edge-print signature: monospaced, letter-spaced, uppercase section
    /// marker in selenium violet — like the frame markings on film stock.
    static func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typography.overline)
            .tracking(1.2)
            .foregroundStyle(ColorToken.accent)
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
