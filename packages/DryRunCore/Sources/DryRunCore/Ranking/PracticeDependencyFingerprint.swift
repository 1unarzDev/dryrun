import Foundation

public extension IntegratedAIState {
    /// Dependencies are scoped to an anchor. Cosmetic labels, names and timestamps do not revoke evidence.
    /// The immutable source snapshot stays intact; current applicability is a separate projection.
    static func practiceDependencyFingerprint(check:HazardPracticeCheck,household:HouseholdProfile,home:HomeModel?)throws->String {
        func json<T:Encodable>(_ value:T)throws->Any {try JSONSerialization.jsonObject(with:DryRunJSON.encoder().encode(value),options:[.fragmentsAllowed])}
        let people=household.people.sorted{$0.id<$1.id}.map {p in
            ["id":p.id,"age":p.ageBand.rawValue,"needs":p.needs.map(\.rawValue).sorted().joined(separator:"|"),"helper":p.helperPersonID ?? "","room":p.sleepingSpaceID ?? ""]
        }
        var relevant:[String:Any]=["check":check.id,"household":household.id]
        switch check.actionKind {
        case "escape","accountOutside","reachHigherRefuge","reachShelter","accompanyEscape","accompanyShelter":
            relevant["people"]=people;relevant["home"]=try json(home);relevant["dwelling"]=household.housing.homeType.rawValue
        case "contact":relevant["contacts"]=try json(household.contacts);relevant["channels"]=try json(household.communications)
        case "allocatePower":
            relevant["equipment"]=try json(household.equipment);relevant["backups"]=try json(household.backupPower)
            relevant["housing"]=try json(household.housing)
        case "warmLayers":relevant["warmth"]=try json(household.preparedness?.items["warmth"]);relevant["housing"]=try json(household.housing)
        case "reduceSolarGain":relevant["home"]=try json(home);relevant["housing"]=try json(household.housing)
        case "leaveEarly","cooledAlternative":relevant["transport"]=try json(household.transport);relevant["people"]=people;relevant["housing"]=try json(household.housing)
        default:
            if check.scenarioID=="water-outage" {relevant["water"]=try json(household.supplies.storedWaterGallons);relevant["waterSource"]=household.housing.waterSource.rawValue}
            else {relevant["home"]=try json(home);relevant["transport"]=try json(household.transport)}
        }
        let cosmetic=Set(["label","alias","displayName","customRelationship","revision","updatedAt","checkedAt","reviewedAt","verifiedAt","recordedAt","legacyOriginalLabel","labelIsCustom","completenessNote","note","notes","isFictional"])
        func clean(_ value:Any)->Any {
            if let dict=value as? [String:Any] {return dict.filter{!cosmetic.contains($0.key)}.mapValues(clean)}
            if let array=value as? [Any] {return array.map(clean)}
            return value
        }
        return StableDigest.of(try JSONSerialization.data(withJSONObject:clean(relevant),options:[.sortedKeys]))
    }
    func pendingHazardChecks(household:HouseholdProfile,home:HomeModel?)throws->[HazardPracticeCheck] {
        try HazardPracticeCheck.bank.filter {check in
            guard let latest=practiceAttempts.filter({$0.checkID==check.id && $0.observations?.isEmpty==false}).max(by:{$0.sequence<$1.sequence}),
                  let source=latest.source,let session=sessions.first(where:{$0.id==source.sessionID}) else {return true}
            return try Self.practiceDependencyFingerprint(check:check,household:household,home:home) != Self.practiceDependencyFingerprint(check:check,household:session.initial.household,home:session.initial.home)
        }
    }
    func currentPracticeEvidence(household:HouseholdProfile,home:HomeModel?,library:ScenarioLibrary)throws->[PracticeAttempt] {
        try eligiblePracticeAttempts(library:library).map {attempt in
            guard let check=HazardPracticeCheck.bank.first(where:{$0.id==attempt.checkID}),let source=attempt.source,
                  let session=sessions.first(where:{$0.id==source.sessionID}) else {return attempt}
            var current=attempt
            if try Self.practiceDependencyFingerprint(check:check,household:household,home:home) != Self.practiceDependencyFingerprint(check:check,household:session.initial.household,home:session.initial.home) {
                // Keep the latest anchor in the compiler, explicitly ineligible. Never fall back to an older best score.
                for index in current.answers.indices {current.answers[index].beforeFeedback=false}
            }
            return current
        }
    }
}
