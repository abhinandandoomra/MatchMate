import Foundation

/// Pure `Profile` -> `MatchRowUIModel` projection.
///
/// `now` is a parameter rather than a call to `Date()` inside the body so age
/// formatting is deterministic under test.
enum MatchRowMapper {
    static func map(_ p: Profile, isBusy: Bool = false, now: Date = .now) -> MatchRowUIModel {
        MatchRowUIModel(
            id: p.uuid,
            fullName: p.fullName,
            subtitle: subtitle(for: p, now: now),
            decision: DecisionBadge.make(for: p.status),
            isBusy: isBusy,
            statusDescription: DecisionBadge.description(for: p.status),
            imageData: p.imageData,
            initials: ProfileFormatting.initials(firstName: p.firstName, lastName: p.lastName)
        )
    }

    private static func subtitle(for p: Profile, now: Date) -> String {
        let place = ProfileFormatting.place(
            city: p.city,
            country: ProfileFormatting.countryName(for: p.nationalityCode)
        )
        guard let age = ProfileFormatting.age(from: p.dateOfBirth, now: now) else { return place }
        return place.isEmpty ? "\(age)" : "\(age) · \(place)"
    }
}

/// Shared, side-effect-free formatting used by both the row and the detail
/// mapper so the two screens can never disagree on how a value reads.
enum ProfileFormatting {
    static func age(from dateOfBirth: Date, now: Date = .now) -> Int? {
        let years = Calendar.current.dateComponents([.year], from: dateOfBirth, to: now).year
        guard let years, years >= 0 else { return nil }
        return years
    }

    /// Falls back to the raw ISO code when the region is unknown to the locale.
    static func countryName(for regionCode: String) -> String {
        let trimmed = regionCode.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        return Locale.current.localizedString(forRegionCode: trimmed) ?? trimmed
    }

    static func initials(firstName: String, lastName: String) -> String {
        let letters = [firstName, lastName]
            .compactMap { $0.trimmingCharacters(in: .whitespaces).first }
            .map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    static func place(city: String, country: String) -> String {
        [city, country]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func mediumDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
