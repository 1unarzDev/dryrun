import Foundation

public enum PreparationEditor: String, Sendable, Hashable { case family, contacts, supplies, medical, home, meetingPlace }
public struct PreparationDefinition: Sendable, Hashable, Identifiable {
    public var id: String
    public var editor: PreparationEditor
    public var scenarioIDs: [String]
    public var sourceIDs: [String]
    public var requiresPhysicalCheck: Bool
}

/// Coverage and completion contract shared by baseline evaluation and the focused checklist editor.
public enum BaselinePreparedness {
    public static let definitions: [PreparationDefinition] = [
        .init(id: "smokeAlarms", editor: .supplies, scenarioIDs: ["home-fire"], sourceIDs: ["S19"], requiresPhysicalCheck: true),
        .init(id: "coAlarms", editor: .supplies, scenarioIDs: ["home-fire", "freeze-power-loss"], sourceIDs: ["S20"], requiresPhysicalCheck: true),
        .init(id: "extinguisher", editor: .supplies, scenarioIDs: ["home-fire"], sourceIDs: ["S19"], requiresPhysicalCheck: true),
        .init(id: "clearExits", editor: .home, scenarioIDs: ["home-fire"], sourceIDs: ["S19"], requiresPhysicalCheck: true),
        .init(id: "food", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "firstAid", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "flashlight", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "batteries", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "sanitation", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "reconnect", editor: .family, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "floodPlan", editor: .supplies, scenarioIDs: ["flash-flood"], sourceIDs: ["S23"], requiresPhysicalCheck: false),
        .init(id: "heatCold", editor: .supplies, scenarioIDs: ["freeze-power-loss", "extreme-heat"], sourceIDs: ["S53"], requiresPhysicalCheck: false)
    ]

    public static func evaluate(household h: HouseholdProfile, home: HomeModel? = nil, savedPlaces: [SavedPlace] = []) -> [Recommendation] {
        var out: [Recommendation] = []
        func add(_ id: String, tier: PriorityTier = .scenarioSupplyOrContinuityGap, facts: [String] = [], values: [String: String] = [:], scenarios: [String] = [], sources: [String] = ["S53"], subjectID: String? = nil) {
            out.append(Recommendation(actionID: "prep.\(id)", tier: tier, titleKey: "prep.\(id).title", whyKey: "prep.\(id).why", templateValues: values,
                matchedFactIDs: facts, causeEventIDs: [], scenarioIDs: scenarios, tryIntervention: nil, modeledEffectKey: nil, effort: .noCost, sourceIDs: sources, verificationStatus: .needsVerification, subjectID: subjectID))
        }
        for d in definitions {
            if d.id == "coAlarms", h.housing.heatingFuel == .none { continue }
            let fact = h.preparedness?.items[d.id]
            let alarm = d.id == "smokeAlarms" || d.id == "coAlarms"
            let complete = fact?.available.confirmedValue == true && !(fact?.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                && (!d.requiresPhysicalCheck || fact?.checkedAt != nil)
                && (!alarm || fact?.coverageReviewed?.confirmedValue == true)
                && (d.id != "extinguisher" || fact?.familyAware?.confirmedValue == true)
            if !complete {
                let critical = ["smokeAlarms", "coAlarms", "clearExits"].contains(d.id)
                add(d.id, tier: critical ? (fact?.available.confirmedValue == false || (alarm && fact?.coverageReviewed?.confirmedValue == false) ? .unmetEssentialRequirement : .blockingUnknownFact) : .scenarioSupplyOrContinuityGap,
                    facts: ["preparedness.\(d.id)"], scenarios: d.scenarioIDs, sources: d.sourceIDs)
            }
        }
        if h.supplies.storedWaterGallons.confirmedValue ?? 0 < Double(h.people.count) * 3 {
            add("water", facts: ["supplies.storedWaterGallons"], values: ["target": String(h.people.count * 3), "litres": String(Int((Double(h.people.count) * 3 * 3.78541).rounded()))], sources: ["S26"])
        }
        if !h.contacts.contains(where: { $0.isComplete }) { add("contact", facts: ["contacts"]) }
        if !h.contacts.contains(where: { $0.role == .outOfAreaContact && $0.isComplete }) { add("outOfAreaContact", facts: ["contacts"]) }
        if !savedPlaces.contains(where: { $0.purpose == .outsideMeetingPoint }) { add("nearMeetup", facts: ["savedPlaces"], scenarios: ["home-fire"]) }
        if !savedPlaces.contains(where: { $0.purpose == .backupMeetingPlace }) { add("backupMeetup", facts: ["savedPlaces"]) }
        if home == nil { add("layout", tier: .multiScenarioPreparation, facts: ["home"], scenarios: ["home-fire", "tornado", "flash-flood"]) }
        for person in h.people where person.needs.contains(.needsHelperToEvacuate) && person.helperPersonID == nil {
            add("helper", tier: .unmetEssentialRequirement, facts: ["person.\(person.id).helperPersonID"], values: ["person": person.alias], subjectID: "person.\(person.id)")
        }
        for eq in h.equipment where eq.isEssential {
            if eq.requiresElectricalPower && !OutageCardBuilder.gaps(for: eq, in: h).filter({ [.noCompatibleBackup, .backupNotTested, .runtimeUnknown].contains($0) }).isEmpty {
                add("medicalBackup", tier: .unmetEssentialRequirement, facts: ["equipment.\(eq.id)"], values: ["device": eq.label.isEmpty ? eq.purpose.rawValue : eq.label], sources: ["S25"], subjectID: "equipment.\(eq.id)")
            }
            if eq.requiresColdStorage && ((eq.storageInstructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || eq.storagePlanConfirmed?.confirmedValue != true) {
                add("coldStorage", tier: .blockingUnknownFact, facts: ["equipment.\(eq.id)"], values: ["device": eq.label.isEmpty ? eq.purpose.rawValue : eq.label], sources: ["S54"], subjectID: "equipment.\(eq.id)")
            }
        }
        if !h.transport.hasVehicle && !h.transport.alternatives.contains(where: { $0.agreed.confirmedValue == true }) { add("transport", facts: ["transport.alternatives"]) }
        if !h.pets.isEmpty && h.preparedness?.items["pets"]?.available.confirmedValue != true { add("pets", facts: ["pets"]) }
        return RecommendationRanker.rank(out)
    }
}
