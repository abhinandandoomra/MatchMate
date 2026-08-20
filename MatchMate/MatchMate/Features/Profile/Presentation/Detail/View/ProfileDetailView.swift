import SwiftUI

/// The full profile. Reads its model straight through the shared repository, so
/// a decision taken here is visible on the list the instant the stack pops —
/// and a decision taken on the list is already reflected when this pushes.
@MainActor
struct ProfileDetailView: View {
    @Environment(\.profileStyle) private var style

    @State private var viewModel: ProfileDetailViewModel

    init(viewModel: ProfileDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if let profile = viewModel.profile {
                loaded(profile)
            } else {
                missingState
            }
        }
        .background(style.screenBackground)
        .navigationTitle(viewModel.profile?.fullName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Loaded

    private func loaded(_ profile: ProfileDetailUIModel) -> some View {
        ScrollView {
            VStack(spacing: style.spacing.xl) {
                hero(profile)
                decisionArea(profile)

                ForEach(profile.sections.filter { !$0.fields.isEmpty }) { section in
                    sectionCard(section)
                }
            }
            .padding(.horizontal, style.spacing.l)
            .padding(.top, style.spacing.s)
            .padding(.bottom, style.spacing.xxl)
            .animation(.easeInOut(duration: style.motion.decisionChange), value: profile.decision)
        }
    }

    private func hero(_ profile: ProfileDetailUIModel) -> some View {
        VStack(spacing: style.spacing.l) {
            ProfileImageView(
                imageData: profile.imageData,
                initials: profile.initials,
                cornerRadius: style.radius.hero
            )
            .frame(height: style.size.hero)
            .frame(maxWidth: .infinity)

            VStack(spacing: style.spacing.xs) {
                Text(profile.fullName)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                if !profile.ageLine.isEmpty {
                    Text(profile.ageLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(profile.fullName). \(profile.ageLine)")
        }
    }

    @ViewBuilder
    private func decisionArea(_ profile: ProfileDetailUIModel) -> some View {
        if let decision = profile.decision {
            StatusPill(badge: decision, isBusy: profile.isBusy) { decide(.undo) }
        } else {
            DecisionButtons(
                name: profile.fullName,
                isBusy: profile.isBusy,
                onDecline: { decide(.decline) },
                onAccept: { decide(.accept) }
            )
        }
    }

    private func sectionCard(_ section: ProfileDetailUIModel.Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(style.text.sectionTracking)
                .foregroundStyle(.secondary)
                .padding(.bottom, style.spacing.m)

            ForEach(Array(section.fields.enumerated()), id: \.element.id) { index, field in
                if index > 0 {
                    Divider().opacity(style.opacity.divider).padding(.vertical, style.spacing.m)
                }
                HStack(alignment: .firstTextBaseline, spacing: style.spacing.m) {
                    Text(field.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: style.spacing.m)
                    Text(field.value)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(field.label): \(field.value)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(style.spacing.l)
        .cardSurface()
    }

    // MARK: - Missing

    private var missingState: some View {
        VStack(spacing: style.spacing.m) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: style.size.emptySymbol, weight: .light))
                .foregroundStyle(.secondary)
            Text(ProfileErrorText.profileUnavailable)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(style.spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func decide(_ intent: DecisionIntent) {
        Task { await viewModel.apply(intent) }
    }
}
