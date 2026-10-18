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
    /// Recorded ownership/quantity establishes availability only, never location, functional checks,
    /// coverage or suitability. Contradictory supply answers remain incomplete.
    public static func recordedSupplyAvailability(_ id: String, household h: HouseholdProfile) -> Bool? {
        let recorded = h.preparedness?.items[id]?.available.confirmedValue
        let canonical: Bool?
        switch id {
        case "water": canonical = h.supplies.storedWaterGallons.confirmedValue.map { $0.isFinite && $0 > 0 }
        case "food": canonical = h.supplies.shelfStableFoodDays.confirmedValue.map { $0.isFinite && $0 > 0 }
        case "firstAid": canonical = h.supplies.firstAidKit.confirmedValue
        case "flashlight": canonical = h.supplies.flashlights.confirmedValue.map { $0 > 0 }
        // Zero power-bank charges do not disprove a separately recorded stock of batteries.
        case "batteries": canonical = h.communications.powerBankCharges.confirmedValue.flatMap { $0.isFinite && $0 > 0 ? true : nil }
        case "radio": canonical = h.communications.batteryOrCrankRadio.confirmedValue
        case "extinguisher": canonical = h.supplies.fireExtinguisher.confirmedValue
        default: canonical = nil
        }
        // This checklist also accepts a recorded alternative reception arrangement; it does not
        // change radio ownership or claim that a modeled radio service is available.
        if id == "radio", recorded == true || canonical == true { return true }
        if recorded == false || canonical == false { return false }
        return recorded ?? canonical
    }

    public static let definitions: [PreparationDefinition] = [
        .init(id: "smokeAlarms", editor: .supplies, scenarioIDs: ["home-fire"], sourceIDs: ["S19"], requiresPhysicalCheck: true),
        .init(id: "coAlarms", editor: .supplies, scenarioIDs: ["home-fire", "freeze-power-loss"], sourceIDs: ["S20"], requiresPhysicalCheck: true),
        .init(id: "extinguisher", editor: .supplies, scenarioIDs: ["home-fire"], sourceIDs: ["S19"], requiresPhysicalCheck: true),
        .init(id: "clearExits", editor: .home, scenarioIDs: ["home-fire"], sourceIDs: ["S19"], requiresPhysicalCheck: true),
        .init(id: "fireDrill", editor: .family, scenarioIDs: ["home-fire"], sourceIDs: ["S19"], requiresPhysicalCheck: true),
        .init(id: "food", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "firstAid", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "flashlight", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "batteries", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "radio", editor: .supplies, scenarioIDs: ["freeze-power-loss", "tornado", "flash-flood"], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "sanitation", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "reconnect", editor: .family, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "floodPlan", editor: .supplies, scenarioIDs: ["flash-flood"], sourceIDs: ["S23"], requiresPhysicalCheck: false),
        .init(id: "wellFloodPlan", editor: .contacts, scenarioIDs: ["flash-flood"], sourceIDs: ["S24"], requiresPhysicalCheck: false),
        .init(id: "heatCold", editor: .supplies, scenarioIDs: ["freeze-power-loss", "extreme-heat"], sourceIDs: ["S53"], requiresPhysicalCheck: false)
    ]

    /// Readiness records close preparation tasks without changing exercise routing, drinking-water
    /// status, or other physical facts. Date-based maintenance belongs to the evaluator's injected
    /// reference date; the deterministic rehearsal engine never reads wall-clock time.
    static func hasRecordedReadiness(_ id: String, household: HouseholdProfile) -> Bool {
        if id == "waterUtility" {
            return household.contacts.contains { $0.role == .waterUtility && $0.isComplete }
        }
        guard let fact = household.preparedness?.items[id], fact.available.confirmedValue == true,
              !fact.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return id != "fireDrill" || fact.checkedAt != nil
    }

    /// The reference date is injected for repeatable maintenance checks. The 180-day review is an app
    /// planning prompt, not a prediction of safety or a substitute for item-specific instructions.
    public static func evaluate(household h: HouseholdProfile, home: HomeModel? = nil, savedPlaces: [SavedPlace] = [], referenceDate: Date = Date()) -> [Recommendation] {
        var out: [Recommendation] = []
        func add(_ id: String, tier: PriorityTier = .scenarioSupplyOrContinuityGap, facts: [String] = [], values: [String: String] = [:], scenarios: [String] = [], sources: [String] = ["S53"], subjectID: String? = nil, whyKey: String? = nil) {
            out.append(Recommendation(actionID: "prep.\(id)", tier: tier, titleKey: "prep.\(id).title", whyKey: whyKey ?? "prep.\(id).why", templateValues: values,
                matchedFactIDs: facts, causeEventIDs: [], scenarioIDs: scenarios, tryIntervention: nil, modeledEffectKey: nil, effort: .noCost, sourceIDs: sources, verificationStatus: .needsVerification, subjectID: subjectID))
        }
        func hasLocation(_ fact: PreparationFact?) -> Bool {
            !(fact?.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        func owns(_ fact: PreparationFact?, canonical: Bool? = nil) -> Bool {
            if canonical == false || fact?.available.confirmedValue == false { return false }
            return fact?.available.confirmedValue == true || canonical == true
        }
        for d in definitions {
            if d.id == "wellFloodPlan", h.housing.waterSource != .privateWell { continue }
            // Heating fuel alone cannot rule out CO sources such as cooking appliances, an attached garage
            // or nearby combustion equipment. Do not erase an unresolved alarm review from that one answer.
            let fact = h.preparedness?.items[d.id]
            let alarm = d.id == "smokeAlarms" || d.id == "coAlarms"
            let owned = recordedSupplyAvailability(d.id, household: h) == true
            let complete = owned && hasLocation(fact)
                && (!d.requiresPhysicalCheck || fact?.checkedAt != nil)
                && (!alarm || fact?.coverageReviewed?.confirmedValue == true)
                && (d.id != "extinguisher" || fact?.familyAware?.confirmedValue == true)
            if !complete {
                let critical = ["smokeAlarms", "coAlarms", "clearExits"].contains(d.id)
                add(d.id, tier: critical ? (fact?.available.confirmedValue == false || (alarm && fact?.coverageReviewed?.confirmedValue == false) ? .unmetEssentialRequirement : .blockingUnknownFact) : (d.id == "fireDrill" ? .general : .scenarioSupplyOrContinuityGap),
                    facts: ["preparedness.\(d.id)"], values: ["item": d.id], scenarios: d.scenarioIDs, sources: d.sourceIDs,
                    whyKey: owned && !hasLocation(fact) ? "prep.location.why" : nil)
            } else if let checkedAt = fact?.checkedAt {
                let days = alarm ? 30 : 180
                if referenceDate.timeIntervalSince(checkedAt) >= Double(days) * 86_400 {
                    add(d.id, tier: .general, facts: ["preparedness.\(d.id).checkedAt"], values: ["days": String(days)], scenarios: d.scenarioIDs,
                        sources: alarm ? ["S53"] : d.sourceIDs, whyKey: "prep.recheck.why")
                }
            }
        }
        if h.preparedness?.reviewedAt.map({ referenceDate.timeIntervalSince($0) < 180 * 86_400 }) != true {
            add("reviewCard", tier: .general, facts: ["preparedness.reviewedAt"], sources: ["S52"])
        }
        let water = h.supplies.storedWaterGallons.confirmedValue
        let enoughWater = water.map { $0.isFinite && $0 >= Double(h.people.count) * 3 && $0 >= 0 } == true
            && h.preparedness?.items["water"]?.available.confirmedValue != false
        if !enoughWater || !hasLocation(h.preparedness?.items["water"]) {
            add("water", facts: ["supplies.storedWaterGallons", "preparedness.water.location"], values: ["item": "water", "target": String(h.people.count * 3), "litres": String(Int((Double(h.people.count) * 3 * 3.78541).rounded()))], sources: ["S26"],
                whyKey: enoughWater ? "prep.location.why" : nil)
        }
        // Supported enrollment is optional coverage metadata, not inferred from an Apple county name.
        if PublicDataPolicy.isAllowedRegionID(h.regionID) {
            let fact = h.preparedness?.items["alerts"]
            if !owns(fact) || !hasLocation(fact) {
                add("alerts", facts: ["regionID", "preparedness.alerts"], sources: ["S52"])
            }
        }
        if !h.contacts.contains(where: { $0.role != .waterUtility && $0.isComplete }) { add("contact", facts: ["contacts"]) }
        if !h.contacts.contains(where: { $0.role == .outOfAreaContact && $0.isComplete }) { add("outOfAreaContact", facts: ["contacts"]) }
        if h.housing.waterSource == .municipal, !hasRecordedReadiness("waterUtility", household: h) {
            add("waterUtility", facts: ["housing.waterSource", "contacts.waterUtility"], scenarios: ["water-outage", "flash-flood"], sources: ["S24"])
        }
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
            if eq.purpose != .refrigeratedMedication {
                let key = "equipmentSupplies.\(eq.id)"
                let fact = h.preparedness?.items[key]
                if !owns(fact) || !hasLocation(fact) {
                    add("equipmentSupplies", tier: fact?.available.confirmedValue == false ? .unmetEssentialRequirement : .blockingUnknownFact,
                        facts: ["equipment.\(eq.id)", "preparedness.\(key)"], values: ["device": eq.label.isEmpty ? eq.purpose.rawValue : eq.label, "item": key],
                        sources: ["S25"], subjectID: "equipment.\(eq.id)", whyKey: owns(fact) ? "prep.location.why" : nil)
                }
            }
        }
        let medicationPeople = h.people.filter { person in
            !(person.emergencyInformation?.essentialMedication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                || h.equipment.contains { $0.isEssential && $0.purpose == .refrigeratedMedication && $0.personID == person.id }
        }
        for person in medicationPeople {
            let key = "medication.person.\(person.id)"
            let fact = h.preparedness?.items[key]
            if !owns(fact) || !hasLocation(fact) {
                add("medication", tier: fact?.available.confirmedValue == false ? .unmetEssentialRequirement : .blockingUnknownFact,
                    facts: ["person.\(person.id).essentialMedication", "preparedness.\(key)"], values: ["person": person.alias, "item": key],
                    sources: ["S54"], subjectID: "person.\(person.id)", whyKey: owns(fact) ? "prep.location.why" : nil)
            }
        }
        // Medicine without a valid person assignment stays visible without inventing a resident association.
        for eq in h.equipment where eq.isEssential && eq.purpose == .refrigeratedMedication && !h.people.contains(where: { $0.id == eq.personID }) {
            let key = "medication.equipment.\(eq.id)"
            let fact = h.preparedness?.items[key]
            if !owns(fact) || !hasLocation(fact) {
                add("medication", tier: fact?.available.confirmedValue == false ? .unmetEssentialRequirement : .blockingUnknownFact,
                    facts: ["equipment.\(eq.id)", "preparedness.\(key)"], values: ["person": eq.label.isEmpty ? eq.purpose.rawValue : eq.label, "item": key],
                    sources: ["S54"], subjectID: "equipment.\(eq.id)", whyKey: owns(fact) ? "prep.location.why" : nil)
            }
        }
        if !h.transport.hasVehicle && !h.transport.alternatives.contains(where: { $0.agreed.confirmedValue == true }) { add("transport", facts: ["transport.alternatives"]) }
        if h.pets.contains(where: { $0.count > 0 }) {
            let fact = h.preparedness?.items["pets"]
            if !owns(fact) || !hasLocation(fact) { add("pets", facts: ["pets", "preparedness.pets"], values: ["item": "pets"], whyKey: owns(fact) ? "prep.location.why" : nil) }
        }
        return RecommendationRanker.rank(out)
    }
}
