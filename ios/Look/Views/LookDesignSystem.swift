import SwiftUI
import UIKit

/// Look Archive: an adaptive, photo-first digital contact sheet. Paper and ink
/// keep the library calm; cobalt is reserved for interaction and selection,
/// while signal orange marks archival/index information.
enum LookTheme {
    // MARK: Color

    enum ColorToken {
        static let backdrop = adaptive(light: 0x171815, dark: 0x090A08)
        static let canvas = adaptive(light: 0xF3F1EA, dark: 0x171815)
        static let surface = adaptive(light: 0xFBFAF6, dark: 0x20211E)
        static let elevated = adaptive(light: 0xE6E2D8, dark: 0x2A2B27)
        static let primaryText = adaptive(light: 0x171815, dark: 0xF3F1EA)
        static let secondaryText = adaptive(light: 0x555850, dark: 0xC4C2BA)
        static let separator = adaptive(light: 0xC8C3B7, dark: 0x43443E)
        static let accent = adaptive(light: 0x3157D5, dark: 0x7895FF)
        static let accentControl = adaptive(light: 0x3157D5, dark: 0x4268E6)
        static let success = adaptive(light: 0x66735C, dark: 0x94A58A)
        static let warning = adaptive(light: 0xC95127, dark: 0xF08A5E)
        static let danger = adaptive(light: 0xB54835, dark: 0xFF806E)

        private static func adaptive(light: UInt, dark: UInt) -> Color {
            Color(uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            })
        }
    }

    // MARK: Typography

    /// Semantic type scale. Every role is a Dynamic Type text style so the app
    /// scales with the user's preferred reading size. `caption` (.footnote) is
    /// the floor and is reserved for auxiliary metadata (timestamps, counts)
    /// rendered in `secondaryText` or brighter.
    enum Typography {
        /// Hero text (connection/setup screen). .largeTitle.
        static let display = Font.system(.largeTitle, design: .rounded).weight(.bold)
        /// Large on-screen titles (photo filename on the detail sheet). .title2.
        static let title = Font.system(.title2, design: .rounded).weight(.semibold)
        /// Section-level titles inside a screen. .title3.
        static let sectionTitle = Font.system(.title3, design: .rounded).weight(.semibold)
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
        static let card: CGFloat = 6
        /// Buttons, fields, small controls.
        static let control: CGFloat = 8
        /// Photo thumbnails.
        static let thumbnail: CGFloat = 2
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

// MARK: - Undo toast

/// Transient bottom toast confirming an action, with an optional Undo.
/// Screens hold a `LookToast?` and overlay `LookToastView`; the view
/// auto-dismisses after 4 seconds unless Undo is tapped.
struct LookToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    var undoTitle: String? = "Undo"
    var undo: (() -> Void)?

    static func == (lhs: LookToast, rhs: LookToast) -> Bool { lhs.id == rhs.id }
}

struct LookToastView: View {
    let toast: LookToast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: LookTheme.Spacing.small) {
            Text(toast.message)
                .font(LookTheme.Typography.secondary)
                .foregroundStyle(LookTheme.ColorToken.primaryText)
                .lineLimit(2)

            Spacer(minLength: LookTheme.Spacing.tight)

            if let undoTitle = toast.undoTitle, let undo = toast.undo {
                Button(undoTitle) {
                    undo()
                    dismiss()
                }
                .font(LookTheme.Typography.secondaryEmphasis)
                .foregroundStyle(LookTheme.ColorToken.accent)
            }
        }
        .padding(.horizontal, LookTheme.Spacing.medium)
        .padding(.vertical, 12)
        .background(LookTheme.ColorToken.elevated,
                    in: RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .padding(.horizontal, LookTheme.Spacing.screen)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: toast.id) {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            dismiss()
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Overlays a `LookToast` above the given bottom padding, animated.
    func lookToast(_ toast: Binding<LookToast?>, bottomPadding: CGFloat = 0) -> some View {
        overlay(alignment: .bottom) {
            if let value = toast.wrappedValue {
                LookToastView(toast: value) {
                    if toast.wrappedValue == value { toast.wrappedValue = nil }
                }
                .padding(.bottom, bottomPadding)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: toast.wrappedValue)
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

private extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: alpha)
    }
}
