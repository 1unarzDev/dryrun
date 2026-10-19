import Foundation
/// Compiles accepted local evidence into rubric predicates. Council output cannot write these facts.
public enum HouseholdAssessment {
    public static func assess(household h:HouseholdProfile,home:HomeModel?,inventory:InventoryLedger?,places:[SavedPlace]=[],stressFindings:[StressTestFinding]=[],at date:Date) throws -> [CriterionAssessment] {
        var results:[CriterionAssessment]=[]
        func append(_ id:String,_ values:[String:Bool?],evidence:[String],notApplicable:String?=nil){
            results.append(CriterionAssessment(criterionID:id,predicates:values.compactMapValues{$0},evidenceIDs:evidence,notApplicableRule:notApplicable))
        }
        let smoke=h.preparedness?.items["smokeAlarms"]
        append("alarms",["present":smoke?.available.confirmedValue,"location":smoke.map{!$0.location.isEmpty},"coverage":smoke?.coverageReviewed?.confirmedValue,
            "checked":smoke?.checkedAt.map{date.timeIntervalSince($0)>=0 && date.timeIntervalSince($0)<30*86400}],evidence:["preparedness.smokeAlarms"])
        if let home {
            let routes=h.people.map{p in EgressPlanner().plan(RouteRequest(personID:p.id,startSpaceID:p.sleepingSpaceID ?? "unknown",mobility:p.requiresStepFreeRoute ? .wheelchair : .walking),in:home)}
            append("escape",["confirmedExit":routes.isEmpty ? nil : routes.allSatisfy{$0.primary != nil},"independentAlternative":routes.isEmpty ? nil : routes.allSatisfy{$0.alternativeStatus == .independent},"reviewed":h.preparedness?.items["clearExits"]?.available.confirmedValue],evidence:["home|\(home.id)|\(home.revision)","preparedness.clearExits"])
        }
        let water=try inventory?.waterGap(people:h.people.count,at:date)
        let waterItems=inventory?.items.filter{$0.category=="water" && ($0.expiresAt.map{$0>date} ?? true)} ?? []
        let waterAccess:Bool?=waterItems.contains{$0.accessible.confirmedValue==true} ? true : waterItems.contains{$0.accessible.confirmedValue==false} ? false : nil
        append("water",["quantity":water.flatMap{$0.deficit.map{$0==0}},"accessible":waterAccess],evidence:["inventory.water"])
        append("food",["quantity":h.supplies.shelfStableFoodDays.confirmedValue.map{$0>=3},"accessible":h.preparedness?.items["food"].map{!$0.location.isEmpty}],evidence:["supplies.shelfStableFoodDays","preparedness.food"])
        append("essentials",["light":h.supplies.flashlights.confirmedValue.map{$0>0},"firstAid":h.supplies.firstAidKit.confirmedValue,"sanitation":h.preparedness?.items["sanitation"]?.available.confirmedValue],evidence:["supplies","preparedness.sanitation"])
        // Missing a contact is unknown, not proof no support exists.
        append("contact",["usableContact":h.contacts.contains{$0.isComplete} ? true : nil,"offlineAccess":h.preparedness?.items["reconnect"]?.available.confirmedValue],evidence:["contacts","preparedness.reconnect"])
        let near=places.contains{$0.homeID==h.stableHomeID && $0.purpose == .outsideMeetingPoint}
        let backup=places.contains{$0.homeID==h.stableHomeID && $0.purpose == .backupMeetingPlace}
        append("meetups",["near":near ? true : nil,"backup":backup ? true : nil,"transport":TransportReadiness.hasRecordedOption(h)],evidence:["savedPlaces","transport"])
        let assisted=h.people.filter{$0.requiresStepFreeRoute || $0.needs.contains(.needsHelperToEvacuate)}
        append("assistance",["assigned":assisted.isEmpty ? nil : assisted.allSatisfy{$0.helperPersonID != nil}],evidence:["people.assistance"],notApplicable:assisted.isEmpty ? "no-assistance-needs" : nil)
        let devices=h.equipment.filter{$0.isEssential && $0.requiresElectricalPower}
        let explicitAbsence=devices.contains{h.preparedness?.items["device|\($0.id)"]?.available.confirmedValue==false}
        let ready=devices.allSatisfy{MedicalBackupReadiness.isReady($0,in:h)}
        // Missing compatible IDs/documents does not establish confirmed absence.
        append("device",["approvedAlternative":explicitAbsence ? false : ready && !devices.isEmpty ? true : nil,"capacity":ready && !devices.isEmpty ? true : nil],evidence:["equipment","backupPower"],notApplicable:devices.isEmpty ? "no-essential-device" : nil)
        let care=h.people.contains{$0.ageBand == .infant || $0.needs.contains(.needsHelperToEvacuate)}
        append("care",[:],evidence:["people.needs"],notApplicable:care ? nil : "no-care-needs")
        append("pets",["transport":h.pets.isEmpty ? nil : h.pets.allSatisfy{$0.carrierAvailable.confirmedValue==true}],evidence:["pets"],notApplicable:h.pets.isEmpty ? "no-pets" : nil)
        append("review",["currentPlan":h.preparedness?.reviewedAt.map{date.timeIntervalSince($0)>=0 && date.timeIntervalSince($0)<180*86400}],evidence:["preparedness.reviewedAt"])
        // Approved graph robustness envelope only. Hypothetical depletion/closures cannot rewrite real supplies.
        let householdDigest=StableDigest.of(try DryRunJSON.encoder().encode(h))
        for finding in stressFindings where finding.sourceConcernDigest==nil && finding.criterionID=="escape" && finding.sourceHouseholdDigest==householdDigest && finding.sourceHomeFingerprint==home.map(HomeFingerprint.of) {
            guard finding.baseline.routes.contains(where:{!$0.sharedChokepoints.isEmpty}),let index=results.firstIndex(where:{$0.criterionID=="escape"}) else {continue}
            results[index].predicates["independentAlternative"]=false
            results[index].evidenceIDs=Array(Set(results[index].evidenceIDs+[finding.baseline.contextDigest])).sorted()
        }
        return results
    }
}
