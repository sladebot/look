import SwiftUI

/// "Look 2.0" design language.
///
/// Dark, photo-first, quiet chrome: photos supply the color, the UI stays
/// neutral and legible. Every text role maps to a Dynamic Type text style
/// (.footnote is the absolute floor, and only for auxiliary metadata).
/// No uppercase tracked labels, no tertiary text color, no fixed-pixel fonts.
enum LookTheme {
    // MARK: Color

    enum ColorToken {
        /// Root window background (behind everything).
        static let backdrop = Color(hex: 0x0A0A0C)
        /// Screen background.
        static let canvas = Color(hex: 0x131316)
        /// Cards, rows, input fields.
        static let surface = Color(hex: 0x1C1C21)
        /// Sheets, menus, banners — one step above `surface`.
        static let elevated = Color(hex: 0x26262C)
        /// Primary readable text.
        static let primaryText = Color(hex: 0xF5F5F7)
        /// Secondary readable text — the darkest gray allowed for meaningful text.
        static let secondaryText = Color(hex: 0xC9C9D1)
        /// Hairline separators and decorative strokes only; never text.
        static let separator = Color(hex: 0x3A3A42)
        /// Brand accent for icons, text highlights, and selection tint.
        static let accent = Color(hex: 0xA79BFF)
        /// Deeper violet for filled controls so white labels keep ~5:1 contrast.
        static let accentControl = Color(hex: 0x6A5AE0)
        static let success = Color(hex: 0x4CC27E)
        /// Warning amber — legible on `elevated`, distinct from `danger` so
        /// cautions don't read as errors.
        static let warning = Color(hex: 0xE5B84E)
        static let danger = Color(hex: 0xFF6B5E)
    }

    // MARK: Typography

    /// Semantic type scale. Every role is a Dynamic Type text style so the app
    /// scales with the user's preferred reading size. `caption` (.footnote) is
    /// the floor and is reserved for auxiliary metadata (timestamps, counts)
    /// rendered in `secondaryText` or brighter.
    enum Typography {
        /// Hero text (connection/setup screen). .largeTitle.
        static let display = Font.largeTitle.weight(.bold)
        /// Large on-screen titles (photo filename on the detail sheet). .title2.
        static let title = Font.title2.weight(.semibold)
        /// Section-level titles inside a screen. .title3.
        static let sectionTitle = Font.title3.weight(.semibold)
        /// Panel headers and row titles. .headline.
        static let headline = Font.headline
        /// Primary content. .body.
        static let body = Font.body
        static let bodyEmphasis = Font.body.weight(.semibold)
        /// Supporting copy, descriptions, row subtitles. .subheadline.
        static let secondary = Font.subheadline
        static let secondaryEmphasis = Font.subheadline.weight(.semibold)
        /// Absolute floor: timestamps, counts, badges only. .footnote.
        static let caption = Font.footnote
        static let captionEmphasis = Font.footnote.weight(.semibold)
        /// File paths, URLs, coordinates ONLY — pair with a Copy affordance
        /// and .lineLimit(2)/.truncationMode(.tail). .footnote floor.
        static let mono = Font.system(.footnote, design: .monospaced)
    }

    // MARK: Metrics

    enum Radius {
        /// Cards and panels.
        static let card: CGFloat = 12
        /// Buttons, fields, small controls.
        static let control: CGFloat = 10
        /// Photo thumbnails.
        static let thumbnail: CGFloat = 6
    }

    enum Spacing {
        static let hairline: CGFloat = 1
        static let tight: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 14
        static let large: CGFloat = 20
        static let screen: CGFloat = 16
    }

    // MARK: Text helpers

    /// Large on-screen title in primary text color.
    static func title(_ text: String) -> some View {
        Text(text)
            .font(Typography.title)
            .foregroundStyle(ColorToken.primaryText)
    }

    /// Sentence-case section header — .headline in primary text.
    static func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Typography.headline)
            .foregroundStyle(ColorToken.primaryText)
    }
}

// MARK: - Screen background

struct LookScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(LookTheme.ColorToken.canvas.ignoresSafeArea())
    }
}

// MARK: - Card / surface

/// Card: content on `surface`, radius 12, no borders or heavy shadows —
/// depth comes from surface steps, not chrome.
struct LookCard: ViewModifier {
    var inset: CGFloat = LookTheme.Spacing.medium

    func body(content: Content) -> some View {
        content
            .padding(inset)
            .background(LookTheme.ColorToken.surface,
                        in: RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
    }
}

/// Bare rounded surface (no padding) for thumbnails-in-rows, inline fills.
struct LookSurface: ViewModifier {
    var radius: CGFloat = LookTheme.Radius.card

    func body(content: Content) -> some View {
        content
            .background(LookTheme.ColorToken.surface,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Text input chrome: .body input text on `surface` with a hairline stroke.
struct LookTextInput: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(LookTheme.Typography.body)
            .padding(.horizontal, LookTheme.Spacing.medium)
            .padding(.vertical, 12)
            .foregroundStyle(LookTheme.ColorToken.primaryText)
            .tint(LookTheme.ColorToken.accent)
            .background(LookTheme.ColorToken.surface,
                        in: RoundedRectangle(cornerRadius: LookTheme.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LookTheme.Radius.control, style: .continuous)
                    .stroke(LookTheme.ColorToken.separator, lineWidth: 1)
            }
    }
}

// MARK: - Status banner

struct LookStatusBanner: View {
    enum Tone {
        case info, success, warning, error

        var color: Color {
            switch self {
            case .info: return LookTheme.ColorToken.accent
            case .success: return LookTheme.ColorToken.success
            case .warning: return LookTheme.ColorToken.warning
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
                .font(LookTheme.Typography.headline)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .foregroundStyle(LookTheme.ColorToken.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(LookTheme.Typography.secondary)
                        .foregroundStyle(LookTheme.ColorToken.secondaryText)
                        .lineLimit(4)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: LookTheme.Spacing.tight)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .buttonStyle(.bordered)
                    .tint(LookTheme.ColorToken.accent)
                    .frame(minHeight: 32)
            }
        }
        .padding(LookTheme.Spacing.medium)
        .background(LookTheme.ColorToken.elevated,
                    in: RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chip

/// Capsule chip on `surface` — .subheadline label, optional icon and tint.
struct LookChip: View {
    let title: String
    var systemImage: String?
    var tint: Color = LookTheme.ColorToken.primaryText

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(LookTheme.Typography.secondary)
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(LookTheme.ColorToken.surface, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Nav title

/// Compact toolbar title: sentence case, no tracking. Subtitle is auxiliary
/// metadata (counts) so .footnote in `secondaryText` is allowed.
struct LookNavTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(LookTheme.Typography.headline)
                .foregroundStyle(LookTheme.ColorToken.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(LookTheme.Typography.caption)
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty / loading states

struct LookEmptyState: View {
    let title: String
    let systemImage: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: LookTheme.Spacing.medium) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(LookTheme.ColorToken.secondaryText)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text(title)
                    .font(LookTheme.Typography.headline)
                    .foregroundStyle(LookTheme.ColorToken.primaryText)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(LookTheme.Typography.secondary)
                        .foregroundStyle(LookTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(LookTheme.Typography.bodyEmphasis)
                    .buttonStyle(.borderedProminent)
                    .tint(LookTheme.ColorToken.accentControl)
                    .frame(minHeight: 44)
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
                .tint(LookTheme.ColorToken.accent)
            VStack(spacing: 5) {
                Text(title)
                    .font(LookTheme.Typography.headline)
                    .foregroundStyle(LookTheme.ColorToken.primaryText)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(LookTheme.Typography.secondary)
                        .foregroundStyle(LookTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - View extensions

extension View {
    /// Flat `canvas` screen background.
    func lookScreenBackground() -> some View {
        modifier(LookScreenBackground())
    }

    /// Card: padded content on `surface`, radius 12.
    func lookCard(inset: CGFloat = LookTheme.Spacing.medium) -> some View {
        modifier(LookCard(inset: inset))
    }

    /// Bare rounded `surface` fill (no padding).
    func lookSurface(radius: CGFloat = LookTheme.Radius.card) -> some View {
        modifier(LookSurface(radius: radius))
    }

    /// Text field chrome: .body input on `surface` with hairline stroke.
    func lookTextInput() -> some View {
        modifier(LookTextInput())
    }
}

// MARK: - Photo zoom transition

/// Opening a photo zooms out of its grid cell (Photos-style) on iOS 18+;
/// earlier systems keep the default cover presentation. Shared so any grid or
/// list of thumbnails (Photos, albums, search) drives the same matched zoom.
struct LookZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

struct LookZoomTransition: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
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
