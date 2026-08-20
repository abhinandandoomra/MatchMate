import SwiftUI

/// One match, as a card: portrait, name, subtitle, and the decision affordance.
///
/// When the match is undecided the affordance is the Accept/Decline pair; once
/// decided the pair is replaced by a single `StatusPill` that remains tappable
/// so the decision can be undone (D-26).
@MainActor
struct MatchCardView: View {
    @Environment(\.profileStyle) private var style
    let row: MatchRowUIModel
    var onOpen: () -> Void
    var onDecision: (DecisionIntent) -> Void

    var body: some View {
        VStack(spacing: style.spacing.l) {
            Button(action: onOpen) {
                HStack(spacing: style.spacing.l) {
                    ProfileImageView(
                        imageData: row.imageData,
                        initials: row.initials,
                        cornerRadius: style.radius.thumbnail
                    )
                    .frame(width: style.size.thumbnail, height: style.size.thumbnail)

                    VStack(alignment: .leading, spacing: style.spacing.xs) {
                        Text(row.fullName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(style.text.nameLineLimit)

                        Text(row.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(style.text.subtitleLineLimit)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(row.fullName), \(row.subtitle)")
            .accessibilityValue(row.statusDescription)
            .accessibilityHint("Double tap to view the full profile")
            .accessibilityAddTraits(.isButton)

            Divider()
                .opacity(style.opacity.disabledControl)

            decisionArea
        }
        .padding(style.spacing.l)
        .cardSurface()
    }

    @ViewBuilder
    private var decisionArea: some View {
        if let decision = row.decision {
            HStack {
                // Undo is explicit now: ask for .pending rather than relying on
                // re-applying the current status and letting the toggle invert it.
                StatusPill(badge: decision, isBusy: row.isBusy) { onDecision(.undo) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            DecisionButtons(
                name: row.fullName,
                isBusy: row.isBusy,
                onDecline: { onDecision(.decline) },
                onAccept: { onDecision(.accept) }
            )
        }
    }

}
