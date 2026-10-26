import SwiftUI
import DryRunCore

/// Top of the create form: one box where a family describes their household in their own words (typed or with
/// keyboard dictation). Nothing is added until they confirm it on the review sheet.
struct DescribeHouseholdSection: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: HouseholdProfile
    @State private var text = ""
    @State private var reading = false
    /// Presented by the form that owns this section: a sheet attached inside a Form row may never present.
    @Binding var review: Review?
    @State private var nothingFound = false

    var body: some View {
        let l = model.localizer
        let usesModel = IntakeAssistant.modelCanRead(locale: draft.preferredLocale)
        Section {
            TextField(l("ui.intake.placeholder"), text: $text, axis: .vertical)
                .lineLimit(3...8)
                .accessibilityIdentifier("intake.text")
            Button {
                Task { await read() }
            } label: {
                if reading {
                    HStack(spacing: Theme.Space.s) { ProgressView(); Text(l("ui.intake.reading")) }
                } else {
                    Label(l("ui.intake.read"), systemImage: usesModel ? "sparkles" : "text.magnifyingglass")
                }
            }
            .disabled(reading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("intake.read")
            if nothingFound { Text(l("ui.intake.nothing")).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text(l("ui.intake.header"))
        } footer: {
            Text(l(usesModel ? "ui.intake.privacyModel" : "ui.intake.privacyKeywords"))
        }
    }

    private func read() async {
        reading = true; nothingFound = false
        let result = await IntakeAssistant.propose(from: text, locale: draft.preferredLocale)
        reading = false
        if result.isEmpty { nothingFound = true } else { review = Review(proposal: result) }
    }

    struct Review: Identifiable { let id = UUID(); let proposal: IntakeProposal }
}

/// "Is this right?": every understood fact is its own switch, on by default. Turning one off drops it.
struct IntakeReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let proposal: IntakeProposal
    let onAccept: (IntakeProposal) -> Void
    @State private var off = Set<String>()

    var body: some View {
        let l = model.localizer
        let p = proposal
        Form {
            Section {
                Text(l("ui.intake.reviewBody")).font(.callout)
                Label(l(p.source == .onDeviceModel ? "ui.intake.sourceModel" : "ui.intake.sourceKeywords"),
                      systemImage: p.source == .onDeviceModel ? "sparkles" : "text.magnifyingglass")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            let people = p.people.filter { !$0.isSelf || !$0.needs.isEmpty }
            if !people.isEmpty {
                Section(l("ui.intake.people")) {
                    ForEach(people) { person in
                        row("person:\(person.id)", title: personTitle(person), detail: personDetail(person))
                    }
                }
            }
            if !p.equipment.isEmpty {
                Section(l("ui.intake.equipment")) {
                    ForEach(p.equipment) { e in
                        let owner = p.people.first { $0.id == e.personID }.map(personTitle)
                        row("equipment:\(e.id)", title: DisplayNames.name(e.purpose.rawValue, localizer: l),
                            detail: owner.map { l("ui.intake.usedBy", ["name": $0]) })
                    }
                }
            }
            if !p.pets.isEmpty {
                Section(l("ui.intake.pets")) {
                    ForEach(p.pets) { pet in
                        row("pet:\(pet.id)", title: "\(DisplayNames.name(pet.kind.rawValue, localizer: l)) × \(pet.count)", detail: nil)
                    }
                }
            }
            let home = homeFacts(p)
            if !home.isEmpty {
                Section(l("ui.intake.home")) {
                    ForEach(home, id: \.key) { fact in row("home:\(fact.key)", title: fact.title, detail: nil) }
                }
            }
        }
        .navigationTitle(l("ui.intake.reviewTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(l("ui.cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(l("ui.intake.add")) { onAccept(accepted()); dismiss() }
                    .accessibilityIdentifier("intake.add")
            }
        }
    }

    private func row(_ key: String, title: String, detail: String?) -> some View {
        Toggle(isOn: Binding(get: { !off.contains(key) }, set: { on in if on { off.remove(key) } else { off.insert(key) } })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if let detail, !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    private func personTitle(_ p: IntakeProposal.PersonDraft) -> String {
        let l = model.localizer
        if p.isSelf { return l("family.you") }
        if !p.alias.isEmpty { return p.alias }
        return p.relationship.map { DisplayNames.name($0.rawValue, localizer: l) } ?? l("ui.person")
    }

    private func personDetail(_ p: IntakeProposal.PersonDraft) -> String {
        let l = model.localizer
        var parts: [String] = []
        if !p.alias.isEmpty, let r = p.relationship { parts.append(DisplayNames.name(r.rawValue, localizer: l)) }
        if p.ageBand != .unknown { parts.append(DisplayNames.name(p.ageBand.rawValue, localizer: l)) }
        parts += p.needs.map { DisplayNames.name($0.rawValue, localizer: l) }
        return parts.joined(separator: " · ")
    }

    private func homeFacts(_ p: IntakeProposal) -> [(key: String, title: String)] {
        let l = model.localizer
        let raw: [(String, String?)] = [("homeType", p.homeType?.rawValue), ("tenancy", p.tenancy?.rawValue),
                                        ("heatingFuel", p.heatingFuel?.rawValue), ("cooling", p.cooling?.rawValue),
                                        ("waterSource", p.waterSource?.rawValue)]
        var facts = raw.compactMap { key, value in value.map { (key: key, title: DisplayNames.name($0, localizer: l)) } }
        if let floors = p.floorCount { facts.append((key: "floorCount", title: l("ui.intake.floors", ["count": "\(floors)"]))) }
        return facts
    }

    /// The proposal minus everything switched off. Removing a person also removes the equipment assigned to them.
    private func accepted() -> IntakeProposal {
        var p = proposal
        let removedPeople = Set(p.people.filter { off.contains("person:\($0.id)") }.map(\.id))
        p.people = p.people.map { person in
            guard removedPeople.contains(person.id) else { return person }
            var kept = person; kept.needs = []          // the speaker always stays; only their listed needs go
            return kept
        }.filter { $0.isSelf || !removedPeople.contains($0.id) }
        p.equipment.removeAll { off.contains("equipment:\($0.id)") || ($0.personID.map(removedPeople.contains) ?? false) }
        p.pets.removeAll { off.contains("pet:\($0.id)") }
        if off.contains("home:homeType") { p.homeType = nil }
        if off.contains("home:tenancy") { p.tenancy = nil }
        if off.contains("home:heatingFuel") { p.heatingFuel = nil }
        if off.contains("home:cooling") { p.cooling = nil }
        if off.contains("home:waterSource") { p.waterSource = nil }
        if off.contains("home:floorCount") { p.floorCount = nil }
        return p
    }
}
