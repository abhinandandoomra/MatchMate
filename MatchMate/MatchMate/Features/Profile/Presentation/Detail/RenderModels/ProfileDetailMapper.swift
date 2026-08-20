import Foundation

/// Pure `Profile` -> `ProfileDetailUIModel` projection. No I/O, no actor hops,
/// no dependence on ambient state beyond `now`.
enum ProfileDetailMapper {
    static func map(_ p: Profile, isBusy: Bool = false, now: Date = .now) -> ProfileDetailUIModel {
        let countryName = ProfileFormatting.countryName(for: p.nationalityCode)
        let age = ProfileFormatting.age(from: p.dateOfBirth, now: now)

        let about = ProfileDetailUIModel.Section(
            title: "About",
            fields: [
                .init(label: "Gender", value: p.gender.capitalized),
                .init(label: "Date of birth", value: dateOfBirthLine(p.dateOfBirth, age: age)),
                .init(label: "Nationality", value: countryName.isEmpty ? p.nationalityCode : countryName)
            ]
        )

        let contact = ProfileDetailUIModel.Section(
            title: "Contact",
            fields: [
                .init(label: "Email", value: p.email),
                .init(label: "Phone", value: p.phone),
                .init(label: "Cell", value: p.cell)
            ]
        )

        let location = ProfileDetailUIModel.Section(
            title: "Location",
            fields: [
                .init(label: "City", value: p.city),
                .init(label: "State", value: p.state),
                .init(label: "Country", value: p.country)
            ]
        )

        let membership = ProfileDetailUIModel.Section(
            title: "Member since",
            fields: [
                .init(label: "Joined", value: ProfileFormatting.mediumDate(p.registeredAt))
            ]
        )

        return ProfileDetailUIModel(
            uuid: p.uuid,
            fullName: p.fullName,
            ageLine: ageLine(age: age, city: p.city, country: countryName),
            decision: DecisionBadge.make(for: p.status),
            isBusy: isBusy,
            imageData: p.imageData,
            initials: ProfileFormatting.initials(firstName: p.firstName, lastName: p.lastName),
            sections: [about, contact, location, membership].map(withNonEmptyFields)
        )
    }

    // MARK: - Helpers

    private static func ageLine(age: Int?, city: String, country: String) -> String {
        let place = ProfileFormatting.place(city: city, country: country)
        guard let age else { return place }
        return place.isEmpty ? "\(age)" : "\(age) · \(place)"
    }

    private static func dateOfBirthLine(_ date: Date, age: Int?) -> String {
        let formatted = ProfileFormatting.mediumDate(date)
        guard let age else { return formatted }
        return "\(formatted) · \(age) years"
    }

    /// A blank value reads as a broken row; drop it instead of rendering an
    /// empty line. Sections that lose every field are dropped by the view.
    private static func withNonEmptyFields(
        _ section: ProfileDetailUIModel.Section
    ) -> ProfileDetailUIModel.Section {
        ProfileDetailUIModel.Section(
            title: section.title,
            fields: section.fields.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        )
    }
}
