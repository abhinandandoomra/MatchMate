import SwiftUI

/// The Profile feature's design vocabulary, as a **value the views are handed**
/// rather than a global they reach into.
///
/// Every dimension, opacity and colour lives here; no view contains a literal.
/// Two consequences beyond tidiness: spacing snaps to one scale instead of
/// drifting across ad-hoc values, and a different look — a denser layout, a
/// higher-contrast palette — is a different instance rather than an edit.
struct ProfileStyle: Sendable {

    // MARK: - Colour

    /// Warm rose — deliberately mid-tone so it holds contrast on both a white
    /// and a near-black background without needing two variants.
    var accent = Color(red: 0.85, green: 0.33, blue: 0.42)
    var accepted = Color(red: 0.16, green: 0.60, blue: 0.38)
    var declined = Color(red: 0.80, green: 0.25, blue: 0.28)
    var banner = Color.orange

    var cardBackground = Color(.secondarySystemGroupedBackground)
    var screenBackground = Color(.systemGroupedBackground)

    /// A tone is semantic; resolving it to a colour is the style's job, so no
    /// view ever decides what "positive" looks like.
    func color(for tone: DecisionTone) -> Color {
        switch tone {
        case .positive: accepted
        case .negative: declined
        }
    }

    var spacing = Spacing()
    var radius = Radius()
    var size = Size()
    var opacity = Opacity()
    var motion = Motion()
    var text = Text()
    var placeholder = Placeholder()

    /// One 4-point scale. A value that does not fit belongs in a private
    /// constant beside the component that needs it, not as a new step here.
    struct Spacing: Sendable {
        var xs: CGFloat = 4
        var s: CGFloat = 8
        var m: CGFloat = 12
        var l: CGFloat = 16
        var xl: CGFloat = 24
        var xxl: CGFloat = 32
    }

    struct Radius: Sendable {
        var card: CGFloat = 20
        var thumbnail: CGFloat = 18
        var hero: CGFloat = 28
    }

    struct Size: Sendable {
        var thumbnail: CGFloat = 84
        var hero: CGFloat = 300
        var statusSymbol: CGFloat = 42
        var emptySymbol: CGFloat = 40
        var hairline: CGFloat = 1

        /// Control heights, tuned to the pill and the decision buttons rather
        /// than snapped to the spacing scale.
        var pillVerticalPadding: CGFloat = 9
        var buttonVerticalPadding: CGFloat = 11
    }

    struct Text: Sendable {
        var nameLineLimit = 1
        var subtitleLineLimit = 2
        var sectionTracking: CGFloat = 0.6
        var minimumScaleFactor: Double = 0.5
    }

    /// The locally drawn initials tile shown while a portrait loads or fails.
    struct Placeholder: Sendable {
        /// A full turn of hue, used to spread initials tints across the wheel.
        var hueDegrees: Double = 360
        /// Initials are sized as a fraction of the tile, with a floor so a very
        /// small tile stays legible.
        var initialsScale: CGFloat = 0.36
        var minimumInitialsSize: CGFloat = 12
        var saturation: Double = 0.45
        var brightness: Double = 0.62
    }

    struct Opacity: Sendable {
        var hairlineBorder: Double = 0.06
        var subtleBorder: Double = 0.12
        var tintFill: Double = 0.14
        var tintBorder: Double = 0.35
        var divider: Double = 0.4
        var disabledControl: Double = 0.5
        var gradientBottom: Double = 0.55
        var mutedLabel: Double = 0.75
        var gradientTop: Double = 0.85
        var bannerFill: Double = 0.92
    }

    struct Motion: Sendable {
        var bannerFade: Double = 0.25
        var decisionChange: Double = 0.2
    }
}

extension EnvironmentValues {
    /// Injected the SwiftUI way. A view declares `@Environment(\.profileStyle)`
    /// and receives whatever the surrounding scope provides — which is what
    /// makes a restyled variant possible without touching a single view.
    @Entry var profileStyle = ProfileStyle()
}

/// The card chrome shared by list rows and detail sections.
struct CardSurface: ViewModifier {
    @Environment(\.profileStyle) private var style

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: style.radius.card, style: .continuous)
                    .fill(style.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: style.radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(style.opacity.hairlineBorder),
                                  lineWidth: style.size.hairline)
            )
            .shadow(color: Color.black.opacity(style.opacity.hairlineBorder),
                    radius: style.spacing.m, x: 0, y: style.spacing.xs)
    }
}

extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }
}
