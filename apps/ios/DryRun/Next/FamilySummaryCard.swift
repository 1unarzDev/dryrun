import SwiftUI
import DryRunCore

/// The family panel on Prepare: the few saved facts that change what this family must prepare or practice, each with
/// what it means and a direct route to correct it. Not a roster: people with nothing consequential recorded are
/// counted, not listed. Every line comes from saved facts and Core's own derived properties; nothing is inferred.
struct FamilySummaryCard: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false

    struct Fact: Identifiable {
        enum Target { case person(String), device(String) }
        let id: String
        let title: String
        let detail: String?
        let implications: [(symbol: String, text: String)]
        let target: Target
    }

    var body: some View {
        let l = model.localizer
        if let household = model.household {
            let facts = Self.facts(household, localizer: l)
            let shown = showAll ? facts : Array(facts.prefix(Theme.previewCount))
            SectionCard(title: l("family.edit"), systemImage: "person.2.fill") {
                if facts.isEmpty {
                    Text(l("ui.familyPanel.none")).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(shown) { fact in
                    NavigationLink { destination(fact.target) } label: { row(fact) }
                        .buttonStyle(.plain)
                        .accessibilityHint(l("ui.familyPanel.correctHint"))
                        .accessibilityIdentifier("family.panel.\(fact.id)")
                    if fact.id != shown.last?.id { Divider() }
                }
                ShowAllButton(total: facts.count, showAll: $showAll)
                    .accessibilityIdentifier("family.panel.showAll")
                NavigationLink { FocusedHouseholdEditor(focus: .family) } label: {
                    Label(l("ui.familyPanel.editAll"), systemImage: "square.and.pencil")
                }
                .buttonStyle(.inline)
                .accessibilityIdentifier("family.panel.editAll")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("family.panel")
        }
    }

    @ViewBuilder private func destination(_ target: Fact.Target) -> some View {
        switch target {
        case .person(let id): FocusedHouseholdEditor(focus: .family, expanding: id)
        case .device(let id): MedicalSetupView(equipmentID: id)
        }
    }

    /// Leading text column on the card's text edge; the chevron sits in a fixed trailing column (visual rule 6).
    private func row(_ fact: Fact) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(fact.title).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                if let detail = fact.detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                ForEach(Array(fact.implications.enumerated()), id: \.offset) { _, item in
                    Label(item.text, systemImage: item.symbol)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                .frame(width: Theme.Space.xl, height: Theme.minTap)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Theme.minTap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// People with equipment first (a power or storage dependency), then people with assistance needs, then essential
    /// equipment not assigned to anyone. Pure function of the saved household so it can be unit-checked.
    static func facts(_ household: HouseholdProfile, localizer l: Localizer) -> [Fact] {
        let essential = household.equipment.filter(\.isEssential)
        func implications(for devices: [PoweredEquipment]) -> [(symbol: String, text: String)] {
            devices.flatMap { device -> [(symbol: String, text: String)] in
                let name = DisplayNames.equipment(device, localizer: l)
                var lines: [(symbol: String, text: String)] = []
                if device.requiresElectricalPower { lines.append(("bolt.heart", l("ui.familyPanel.power", ["device": name]))) }
                if device.requiresColdStorage { lines.append(("snowflake", l("ui.familyPanel.cold", ["device": name]))) }
                return lines
            }
        }
        let people: [(rank: Int, fact: Fact)] = household.people.compactMap { person in
            let devices = essential.filter { $0.personID == person.id }
            guard !person.needs.isEmpty || !devices.isEmpty else { return nil }
            var title = person.localizedLabel(l)
            if let role = relationship(person, localizer: l) { title += " · " + role }
            let needs = AssistanceNeed.allCases.filter(person.needs.contains).map { l("common.need.\($0.rawValue)") }
            let detail = needs.isEmpty ? nil : DisplayNames.sentenceCase(needs.joined(separator: ", "))
            var lines: [(symbol: String, text: String)] = []
            if person.requiresStepFreeRoute { lines.append(("figure.roll", l("ui.familyPanel.stepFree"))) }
            lines += implications(for: devices)
            return (devices.isEmpty ? 1 : 0, Fact(id: "person.\(person.id)", title: title, detail: detail, implications: lines, target: .person(person.id)))
        }
        let personIDs = Set(household.people.map(\.id))
        let unassigned = essential.filter { $0.personID.map { !personIDs.contains($0) } ?? true }.map { device in
            Fact(id: "device.\(device.id)", title: DisplayNames.equipment(device, localizer: l), detail: nil,
                 implications: implications(for: [device]), target: .device(device.id))
        }
        return people.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element.fact) + unassigned
    }

    private static func relationship(_ person: Person, localizer l: Localizer) -> String? {
        guard let relationship = person.relationship else { return nil }
        if relationship == .custom {
            let custom = person.customRelationship?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return custom.isEmpty ? nil : custom
        }
        return l("relationship.\(relationship.rawValue)")
    }
}
