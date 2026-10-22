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
    /// Alarm markers describe location only. Readiness needs independently recorded presence,
    /// findable locations, coverage review and a functional check; geometry is not a prerequisite.
    /// Recency is evaluated separately with the baseline evaluator's injected reference date.
    public static func hasRecordedAlarmReadiness(_ id: String, household: HouseholdProfile) -> Bool {
        guard id == "smokeAlarms" || id == "coAlarms",
              let fact = household.preparedness?.items[id], fact.available.confirmedValue == true,
              !fact.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              fact.coverageReviewed?.confirmedValue == true, fact.checkedAt != nil else { return false }
        return true
    }

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

    /// Checklist items whose recorded absence makes buying (or installing) one the next step.
    static let purchasable: Set<String> = ["smokeAlarms", "coAlarms", "extinguisher", "firstAid", "flashlight", "batteries"]

    public static let definitions: [PreparationDefinition] = [
        .init(id: "smokeAlarms", editor: .supplies, scenarioIDs: ["home-fire"], sourceIDs: ["S19"], requiresPhysicalCheck: true),
        .init(id: "coAlarms", editor: .supplies, scenarioIDs: ["home-fire", "freeze-power-loss"], sourceIDs: ["S20"], requiresPhysicalCheck: true),
        .init(id: "extinguisher", editor: .supplies, scenarioIDs: ["home-fire"], sourceIDs: ["S19"], requiresPhysicalCheck: true),
        .init(id: "clearExits", editor: .home, scenarioIDs: ["home-fire"], sourceIDs: ["S19"], requiresPhysicalCheck: true),
        .init(id: "fireDrill", editor: .family, scenarioIDs: ["home-fire"], sourceIDs: ["S19"], requiresPhysicalCheck: true),
        .init(id: "food", editor: .supplies, scenarioIDs: [], sourceIDs: ["S64"], requiresPhysicalCheck: false),
        .init(id: "firstAid", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "flashlight", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "batteries", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "radio", editor: .supplies, scenarioIDs: ["freeze-power-loss", "tornado", "flash-flood"], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "sanitation", editor: .supplies, scenarioIDs: [], sourceIDs: ["S53"], requiresPhysicalCheck: false),
        .init(id: "floodPlan", editor: .supplies, scenarioIDs: ["flash-flood"], sourceIDs: ["S23"], requiresPhysicalCheck: false),
        .init(id: "wellFloodPlan", editor: .contacts, scenarioIDs: ["flash-flood"], sourceIDs: ["S24"], requiresPhysicalCheck: false),
        .init(id: "heatCold", editor: .supplies, scenarioIDs: ["freeze-power-loss", "extreme-heat"], sourceIDs: ["S53"], requiresPhysicalCheck: false)
    ]

    /// True when the person's recorded sleeping room is on a floor above the home's lowest floor; false for the lowest
    /// floor or a single-story home; nil when a multi-story home has no known sleeping room. Never guessed from home type.
    static func sleepsAboveLowestFloor(_ person: Person, household h: HouseholdProfile, home: HomeModel?) -> Bool? {
        if let home, let lowest = home.floors.map(\.level).min(), let spaceID = person.sleepingSpaceID,
           let space = home.space(spaceID), let floor = home.floors.first(where: { $0.id == space.floorID }) {
            return floor.level > lowest
        }
        if let home { return home.floors.count > 1 ? nil : false }
        return h.housing.floorCount > 1 ? nil : false
    }

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
        recommendations(household: h, home: home, savedPlaces: savedPlaces, referenceDate: referenceDate, includeSatisfied: false)
    }

    /// Tangible progress derives from real records, never generic Done flags or hypothetical choices.
    /// The same applicability and completion criteria produce both unresolved and recorded lists.
    public static func recorded(household: HouseholdProfile, home: HomeModel? = nil, savedPlaces: [SavedPlace] = [], referenceDate: Date = Date()) -> [Recommendation] {
        let unresolved = Set(evaluate(household: household, home: home, savedPlaces: savedPlaces, referenceDate: referenceDate).map(\.id))
        return recommendations(household: household, home: home, savedPlaces: savedPlaces, referenceDate: referenceDate, includeSatisfied: true)
            .filter { !unresolved.contains($0.id) }
    }

    private static func recommendations(household h: HouseholdProfile, home: HomeModel?, savedPlaces: [SavedPlace], referenceDate: Date, includeSatisfied: Bool) -> [Recommendation] {
        let matchingPlaces = HomeMeetingPlaces.placesIncludingLocalMeetup(home: home, places: savedPlaces, recordedAt: h.updatedAt).filter { $0.homeID == (home?.id ?? h.stableHomeID) }
        var out: [Recommendation] = []
        func add(_ id: String, tier: PriorityTier = .scenarioSupplyOrContinuityGap, facts: [String] = [], values: [String: String] = [:], scenarios: [String] = [], sources: [String] = ["S53"], subjectID: String? = nil, whyKey: String? = nil,
                 titleKey: String? = nil, effort: EffortBand = .noCost, notes: [String] = []) {
            out.append(Recommendation(actionID: "prep.\(id)", tier: tier, titleKey: titleKey ?? "prep.\(id).title", whyKey: whyKey ?? "prep.\(id).why", templateValues: values,
                matchedFactIDs: facts, causeEventIDs: [], scenarioIDs: scenarios, tryIntervention: nil, modeledEffectKey: nil, effort: effort, feasibilityNotes: notes,
                sourceIDs: sources, verificationStatus: .needsVerification, subjectID: subjectID))
        }
        /// Buying something is the next step only when the household recorded not having it. Unknown ownership is
        /// a free check first; owned items move on to location and maintenance, never to another purchase.
        func purchaseNotes() -> [String] {
            (h.supplies.limitedBudget ? ["feasibility.budget"] : []) + (h.housing.tenancy == .renter ? ["feasibility.landlord-for-repairs"] : [])
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
            // Ownership alone cannot close a task while the published draft food horizon is unmet.
            let coverage = d.id != "food" || h.supplies.shelfStableFoodDays.confirmedValue.map{$0.isFinite && $0>=3} == true
            let complete = alarm ? hasRecordedAlarmReadiness(d.id, household: h)
                : owned && coverage && hasLocation(fact)
                    && (!d.requiresPhysicalCheck || fact?.checkedAt != nil)
                    && (d.id != "extinguisher" || fact?.familyAware?.confirmedValue == true)
            if !complete || includeSatisfied {
                let critical = ["smokeAlarms", "coAlarms", "clearExits"].contains(d.id)
                // Material ownership state picks the action: get one (recorded absent), find it (owned, no location),
                // or maintain it (owned and located, check or family awareness missing). Satisfied records keep the base wording.
                let absent = !complete && purchasable.contains(d.id) && recordedSupplyAvailability(d.id, household: h) == false
                let maintain = !complete && d.id == "extinguisher" && owned && hasLocation(fact)
                let whyKey = absent ? (alarm ? "prep.alarm.acquire.why" : "prep.acquire.why")
                    : (maintain ? "prep.extinguisher.check.why" : (owned && coverage && !hasLocation(fact) ? "prep.location.why" : nil))
                add(d.id, tier: critical ? (fact?.available.confirmedValue == false || (alarm && fact?.coverageReviewed?.confirmedValue == false) ? .unmetEssentialRequirement : .blockingUnknownFact) : (d.id == "fireDrill" ? .general : .scenarioSupplyOrContinuityGap),
                    facts: ["preparedness.\(d.id)"], values: ["item": d.id], scenarios: d.scenarioIDs, sources: d.sourceIDs,
                    whyKey: whyKey, titleKey: absent ? "prep.\(d.id).acquire.title" : (maintain ? "prep.extinguisher.check.title" : nil),
                    effort: absent ? .low : .noCost, notes: absent ? purchaseNotes() : [])
            } else if let checkedAt = fact?.checkedAt {
                let days = alarm ? 30 : 180
                if referenceDate.timeIntervalSince(checkedAt) >= Double(days) * 86_400 {
                    add(d.id, tier: .general, facts: ["preparedness.\(d.id).checkedAt"], values: ["days": String(days)], scenarios: d.scenarioIDs,
                        sources: alarm ? ["S53"] : d.sourceIDs, whyKey: "prep.recheck.why")
                }
            }
        }
        if includeSatisfied || h.preparedness?.reviewedAt.map({ referenceDate.timeIntervalSince($0) < 180 * 86_400 }) != true {
            add("reviewCard", tier: .general, facts: ["preparedness.reviewedAt"], sources: ["S52"])
        }
        let water = h.supplies.storedWaterGallons.confirmedValue
        let enoughWater = water.map { $0.isFinite && $0 >= Double(h.people.count) * 3 && $0 >= 0 } == true
            && h.preparedness?.items["water"]?.available.confirmedValue != false
        if includeSatisfied || !enoughWater || !hasLocation(h.preparedness?.items["water"]) {
            add("water", facts: ["supplies.storedWaterGallons", "preparedness.water.location"], values: ["item": "water", "target": String(h.people.count * 3), "litres": String(Int((Double(h.people.count) * 3 * 3.78541).rounded()))], sources: ["S26"],
                whyKey: enoughWater ? "prep.location.why" : nil)
        }
        // Supported enrollment is optional coverage metadata, not inferred from an Apple county name.
        if PublicDataPolicy.isAllowedRegionID(h.regionID) {
            let fact = h.preparedness?.items["alerts"]
            if includeSatisfied || !owns(fact) || !hasLocation(fact) {
                add("alerts", facts: ["regionID", "preparedness.alerts"], sources: ["S52"])
            }
        }
        if includeSatisfied || !h.contacts.contains(where: { $0.role != .waterUtility && $0.isComplete }) { add("contact", facts: ["contacts"]) }
        if includeSatisfied || !h.contacts.contains(where: { $0.role == .outOfAreaContact && $0.isComplete }) { add("outOfAreaContact", facts: ["contacts"]) }
        if h.housing.waterSource == .municipal, includeSatisfied || !hasRecordedReadiness("waterUtility", household: h) {
            add("waterUtility", facts: ["housing.waterSource", "contacts.waterUtility"], scenarios: ["water-outage", "flash-flood"], sources: ["S24"])
        }
        if includeSatisfied || !matchingPlaces.contains(where: { $0.purpose == .outsideMeetingPoint }) { add("nearMeetup", facts: ["savedPlaces"], scenarios: ["home-fire"]) }
        if includeSatisfied || !matchingPlaces.contains(where: { $0.purpose == .backupMeetingPlace }) { add("backupMeetup", facts: ["savedPlaces"]) }
        if includeSatisfied || home == nil { add("layout", tier: .multiScenarioPreparation, facts: ["home"], scenarios: ["home-fire", "tornado", "flash-flood"]) }
        let manufactured=h.housing.homeType == .manufacturedHome || home?.dwellingType == .manufacturedHome
        if manufactured || home.map({ShelterSuitability.confirmedRoom(in:$0)==nil}) == true {
            add("shelterPlan",tier:manufactured ? .unmetEssentialRequirement:.blockingUnknownFact,
                facts:["housing.homeType","home.tornadoShelterCandidate"],scenarios:["tornado"],sources:["S22"],
                subjectID:manufactured ? "manufacturedAdvancePlan":"home",whyKey:manufactured ? "prep.shelterPlan.manufactured.why":"prep.shelterPlan.why")
        }
        for person in h.people where person.needs.contains(.needsHelperToEvacuate) {
            let helperAssigned = h.people.contains { $0.id != person.id && $0.id == person.helperPersonID }
            if includeSatisfied || !helperAssigned { add("helper", tier: .unmetEssentialRequirement, facts: ["person.\(person.id).helperPersonID"], values: ["person": person.alias], subjectID: "person.\(person.id)") }
        }
        for person in h.people where person.requiresStepFreeRoute || person.needs.contains(.limitedMobility) {
            let key = "stairPlan.person.\(person.id)"
            let fact = h.preparedness?.items[key]
            guard let upper = sleepsAboveLowestFloor(person, household: h, home: home) else {
                // A multi-story home without a known sleeping floor: ask the one question that changes the plan.
                if includeSatisfied || !(owns(fact) && hasLocation(fact)) {
                    add("stairPlan", tier: .blockingUnknownFact, facts: ["person.\(person.id).needs", "person.\(person.id).sleepingSpaceID", "housing.floorCount"],
                        values: ["person": person.alias, "item": key], scenarios: ["home-fire", "flash-flood", "tornado"], sources: ["S19", "S22"],
                        subjectID: "person.\(person.id)", whyKey: "prep.stairPlan.unknown.why")
                }
                continue
            }
            guard upper, includeSatisfied || !(owns(fact) && hasLocation(fact)) else { continue }
            let helperAssigned = h.people.contains { $0.id != person.id && $0.id == person.helperPersonID }
            add("stairPlan", tier: helperAssigned ? .blockingUnknownFact : .unmetEssentialRequirement,
                facts: ["person.\(person.id).needs", "person.\(person.id).sleepingSpaceID", "person.\(person.id).helperPersonID"],
                values: ["person": person.alias, "item": key], scenarios: ["home-fire", "flash-flood", "tornado"], sources: ["S19", "S22"],
                subjectID: "person.\(person.id)", whyKey: helperAssigned ? "prep.stairPlan.helper.why" : nil)
        }
        for eq in h.equipment where eq.isEssential {
            if eq.requiresElectricalPower && (includeSatisfied || !MedicalBackupReadiness.isReady(eq, in: h)) {
                add("medicalBackup", tier: .unmetEssentialRequirement, facts: ["equipment.\(eq.id)"], values: ["device": eq.label.isEmpty ? eq.purpose.rawValue : eq.label], sources: ["S25"], subjectID: "equipment.\(eq.id)")
            }
            let instructions = !(eq.storageInstructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if eq.requiresColdStorage && (includeSatisfied || !instructions || eq.storagePlanConfirmed?.confirmedValue != true) {
                // Recorded storage instructions turn the task from "write them down" into an outage continuity plan.
                let continuity = instructions && eq.storagePlanConfirmed?.confirmedValue != true
                add("coldStorage", tier: .blockingUnknownFact, facts: ["equipment.\(eq.id)"] + (instructions ? ["equipment.\(eq.id).storageInstructions"] : []),
                    values: ["device": eq.label.isEmpty ? eq.purpose.rawValue : eq.label], sources: ["S54"], subjectID: "equipment.\(eq.id)",
                    whyKey: continuity ? "prep.coldStorage.continuity.why" : nil, titleKey: continuity ? "prep.coldStorage.continuity.title" : nil)
            }
            if eq.purpose != .refrigeratedMedication {
                let key = "equipmentSupplies.\(eq.id)"
                let fact = h.preparedness?.items[key]
                if includeSatisfied || !owns(fact) || !hasLocation(fact) {
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
            if includeSatisfied || !owns(fact) || !hasLocation(fact) {
                add("medication", tier: fact?.available.confirmedValue == false ? .unmetEssentialRequirement : .blockingUnknownFact,
                    facts: ["person.\(person.id).essentialMedication", "preparedness.\(key)"], values: ["person": person.alias, "item": key],
                    sources: ["S54"], subjectID: "person.\(person.id)", whyKey: owns(fact) ? "prep.location.why" : nil)
            }
        }
        // Medicine without a valid person assignment stays visible without inventing a resident association.
        for eq in h.equipment where eq.isEssential && eq.purpose == .refrigeratedMedication && !h.people.contains(where: { $0.id == eq.personID }) {
            let key = "medication.equipment.\(eq.id)"
            let fact = h.preparedness?.items[key]
            if includeSatisfied || !owns(fact) || !hasLocation(fact) {
                add("medication", tier: fact?.available.confirmedValue == false ? .unmetEssentialRequirement : .blockingUnknownFact,
                    facts: ["equipment.\(eq.id)", "preparedness.\(key)"], values: ["person": eq.label.isEmpty ? eq.purpose.rawValue : eq.label, "item": key],
                    sources: ["S54"], subjectID: "equipment.\(eq.id)", whyKey: owns(fact) ? "prep.location.why" : nil)
            }
        }
        if includeSatisfied || !TransportReadiness.hasRecordedOption(h) {
            add("transport", tier: TransportReadiness.needsAccessibleTransport(h) ? .blockingUnknownFact : .scenarioSupplyOrContinuityGap,
                facts: ["transport.vehicles", "transport.alternatives"] + (TransportReadiness.needsAccessibleTransport(h) ? ["people.needs.usesWheelchair"] : []))
        }
        if h.pets.contains(where: { $0.count > 0 }) {
            let fact = h.preparedness?.items["pets"]
            if includeSatisfied || !owns(fact) || !hasLocation(fact) { add("pets", facts: ["pets", "preparedness.pets"], values: ["item": "pets"], whyKey: owns(fact) ? "prep.location.why" : nil) }
        }
        return RecommendationRanker.rank(out)
    }
}
