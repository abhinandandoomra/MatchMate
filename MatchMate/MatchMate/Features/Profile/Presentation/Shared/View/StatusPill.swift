import SwiftUI


/// The decided state, shown *instead of* the Accept/Decline buttons.
///
/// D-26 — it stays tappable, emitting `DecisionIntent.undo`. That is the only
/// undo affordance, so it must never be a plain label. The pill says what the
/// user *asked for*, never what the resulting status should be — resolving
/// intent into domain state is the ViewModel's job.
@MainActor
struct StatusPill: View {
    @Environment(\.profileStyle) private var style
    let badge: DecisionBadge
    var isBusy: Bool = false
    var action: () -> Void

    private var tint: Color { style.color(for: badge.tone) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: style.spacing.xs) {
                Image(systemName: badge.symbolName)
                    .font(.footnote.weight(.bold))
                Text(badge.title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.vertical, style.size.pillVerticalPadding)
            .padding(.horizontal, style.spacing.l)
            .background(Capsule().fill(tint.opacity(style.opacity.tintFill)))
            .overlay(Capsule().strokeBorder(tint.opacity(style.opacity.tintBorder), lineWidth: style.size.hairline))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? style.opacity.disabledControl : 1)
        .accessibilityLabel(badge.title)
        .accessibilityHint(badge.accessibilityHint)
    }
}

@MainActor
struct DecisionButtons: View {
    @Environment(\.profileStyle) private var style
    let name: String
    var isBusy: Bool = false
    var onDecline: () -> Void
    var onAccept: () -> Void

    var body: some View {
        HStack(spacing: style.spacing.m) {
            Button(action: onDecline) {
                Label("Decline", systemImage: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, style.size.buttonVerticalPadding)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(style.opacity.mutedLabel))
            .background(
                Capsule().fill(Color.primary.opacity(style.opacity.hairlineBorder))
            )
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(style.opacity.subtleBorder), lineWidth: style.size.hairline)
            )
            .accessibilityLabel("Decline \(name)")

            Button(action: onAccept) {
                Label("Accept", systemImage: "heart.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, style.size.buttonVerticalPadding)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Capsule().fill(style.accent))
            .accessibilityLabel("Accept \(name)")
        }
        // A decision is already being written; ignore further taps rather than
        // racing a second write against the first.
        .disabled(isBusy)
        .opacity(isBusy ? style.opacity.disabledControl : 1)
    }
}
