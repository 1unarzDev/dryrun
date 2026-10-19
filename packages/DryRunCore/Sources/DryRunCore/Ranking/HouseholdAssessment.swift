import Foundation
/// Compiles accepted local evidence into rubric predicates. Council output cannot write these facts.
public enum HouseholdAssessment {
    private static func all(_ values:[Bool?])->Bool? {
        if values.contains(where:{$0==false}) {return false}
        return values.isEmpty || values.contains(where:{$0==nil}) ? nil:true
    }
    private static func any(_ values:[Bool?])->Bool? {
        if values.contains(where:{$0==true}) {return true}
        return values.isEmpty || values.contains(where:{$0==nil}) ? nil:false
    }
    private static func requiresAssistance(_ p:Person)->Bool {
        p.requiresStepFreeRoute || p.needs.contains(.needsHelperToEvacuate) || p.needs.contains(.deafOrHardOfHearing) || p.ageBand == .infant || p.ageBand == .child
    }
    public static let version="dryrun.household-assessment/3"
    public static func assess(household h:HouseholdProfile,home:HomeModel?,inventory:InventoryLedger?,places:[SavedPlace]=[],stressFindings:[StressTestFinding]=[],at date:Date) throws -> [CriterionAssessment] {
        var results:[CriterionAssessment]=[]
        func append(_ id:String,_ values:[String:Bool?],evidence:[String],notApplicable:String?=nil){
            results.append(CriterionAssessment(criterionID:id,predicates:values.compactMapValues{$0},evidenceIDs:evidence,notApplicableRule:notApplicable,assessmentVersion:version))
        }
        let smoke=h.preparedness?.items["smokeAlarms"]
        append("alarms",["present":smoke?.available.confirmedValue,"location":smoke.map{!$0.location.isEmpty},"coverage":smoke?.coverageReviewed?.confirmedValue,
            "checked":smoke?.checkedAt.map{date.timeIntervalSince($0)>=0 && date.timeIntervalSince($0)<30*86400}],evidence:["preparedness.smokeAlarms"])
        if let home {
            let routes=h.people.map{p in EgressPlanner().plan(RouteRequest(personID:p.id,startSpaceID:p.sleepingSpaceID ?? "unknown",mobility:p.requiresStepFreeRoute ? .wheelchair : .walking),in:home)}
            let confirmedRoutes:[Bool?]=routes.map {route in
                guard let path=route.primary,path.verificationNeeded.isEmpty else {return nil}
                return true
            }
            let independent:[Bool?]=routes.map {route in
                guard route.primary?.verificationNeeded.isEmpty==true else {return nil}
                if route.alternativeStatus == .independent,route.alternative?.verificationNeeded.isEmpty==true {return true}
                if home.completeness == .complete,route.alternativeStatus == .sharesChokepoint {return false}
                // Missing/unknown geometry or a missing confirmed alternative does not prove that
                // a household has no usable alternative. Review it; do not invent a known failure.
                return nil
            }
            append("escape",["confirmedExit":all(confirmedRoutes),"independentAlternative":all(independent),"reviewed":h.preparedness?.items["clearExits"]?.available.confirmedValue],evidence:["home|\(home.id)|\(home.revision)","preparedness.clearExits"])
            // Use the same recorded tornado planning choice and interior-purpose route rules as rehearsal.
            // A missing/invalid candidate is unknown, never evidence that the household has no refuge.
            let shelter=ShelterSuitability.confirmedRoom(in:home)
            let shelterRoutes:[Bool?]=h.people.map {person in
                guard let shelter else {return nil}
                let route=EgressPlanner().plan(RouteRequest(personID:person.id,startSpaceID:person.sleepingSpaceID ?? "unknown",mobility:person.requiresStepFreeRoute ? .wheelchair:.walking,purpose:.interiorShelter,destinationSpaceID:shelter.id),in:home)
                guard let path=route.primary,path.verificationNeeded.isEmpty else {return nil}
                return true
            }
            append("shelter",["suitable":shelter == nil ? nil:true,"reachable":all(shelterRoutes)],evidence:["home|\(home.id)|\(home.revision)","home.tornadoShelterCandidate"])
        }
        let water=try inventory?.waterGap(people:h.people.count,at:date)
        let waterItems=inventory?.items.filter{$0.category=="water"} ?? []
        let waterAccess=any(waterItems.map {item in
            item.expiresAt.map{$0<=date}==true ? false:item.accessible.confirmedValue
        })
        append("water",["quantity":water.flatMap{$0.deficit.map{$0==0}},"accessible":waterAccess],evidence:["inventory.water"])
        let foodItems=inventory?.items.filter{$0.category=="food"} ?? []
        let foodAccess=any(foodItems.map {item in
            item.expiresAt.map{$0<=date}==true ? false:item.accessible.confirmedValue
        })
        let foodQuantity:Bool?
        if !foodItems.isEmpty,let inventory {
            foodQuantity=try inventory.householdFoodGap(personIDs:h.people.map(\.id),at:date).deficit.map{$0==0}
        } else {foodQuantity=h.supplies.shelfStableFoodDays.confirmedValue.map{$0>=3}}
        // A location string records where to look, not whether the household can access usable food.
        append("food",["quantity":foodQuantity,"accessible":foodAccess],evidence:["supplies.shelfStableFoodDays","inventory.food"])
        append("essentials",["light":h.supplies.flashlights.confirmedValue.map{$0>0},"firstAid":h.supplies.firstAidKit.confirmedValue,"sanitation":h.preparedness?.items["sanitation"]?.available.confirmedValue],evidence:["supplies","preparedness.sanitation"])
        // Missing a contact is unknown, not proof no support exists.
        append("contact",["usableContact":h.contacts.contains{$0.isComplete} ? true : nil,"offlineAccess":h.preparedness?.items["reconnect"]?.available.confirmedValue],evidence:["contacts","preparedness.reconnect"])
        let near=places.contains{$0.homeID==h.stableHomeID && $0.purpose == .outsideMeetingPoint}
        let backup=places.contains{$0.homeID==h.stableHomeID && $0.purpose == .backupMeetingPlace}
        append("meetups",["near":near ? true : nil,"backup":backup ? true : nil,"transport":any(h.transport.vehicles.map{TransportReadiness.vehicleAvailability($0,household:h)}+h.transport.alternatives.map{TransportReadiness.alternativeAvailability($0,household:h)})],evidence:["savedPlaces","transport"])
        let assisted=h.people.filter{requiresAssistance($0)}
        append("assistance",["assigned":all(assisted.map {person in person.helperPersonID.map {id in id != person.id && h.people.contains{$0.id==id}}})],evidence:["people.assistance"],notApplicable:assisted.isEmpty ? "no-assistance-needs" : nil)
        let devices=h.equipment.filter{$0.isEssential && $0.requiresElectricalPower}
        let explicitAbsence=devices.contains{h.preparedness?.items["device|\($0.id)"]?.available.confirmedValue==false}
        let ready=devices.allSatisfy{MedicalBackupReadiness.isReady($0,in:h)}
        // Missing compatible IDs/documents does not establish confirmed absence.
        append("device",["approvedAlternative":explicitAbsence ? false : ready && !devices.isEmpty ? true : nil,"capacity":ready && !devices.isEmpty ? true : nil],evidence:["equipment","backupPower"],notApplicable:devices.isEmpty ? "no-essential-device" : nil)
        let care=h.people.contains{requiresAssistance($0)}
        append("care",[:],evidence:["people.needs"],notApplicable:care ? nil : "no-care-needs")
        append("pets",["transport":all(h.pets.map{$0.carrierAvailable.confirmedValue})],evidence:["pets"],notApplicable:h.pets.isEmpty ? "no-pets" : nil)
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
