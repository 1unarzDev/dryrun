import Foundation
/// A proposed preparation applied only to a copied exercise before the fixed external schedule.
public struct StressRetestPlan:Codable,Sendable {
    public var version:String
    public var commands:[SessionCommand]
    public init(commands:[SessionCommand]){self.version="dryrun.stress-retest/1";self.commands=commands}
}
/// Host comparison at the common final horizon. Unknowns are never an implicit successful result.
public struct StressRetestComparison:Codable,Sendable {
    public var version:String = "dryrun.stress-comparison/1"
    public var baselineMinute:Int
    public var retestMinute:Int
    public var commonHorizonReached:Bool
    public var resolvedRequirementIDs:[String]
    public var remainingRequirementIDs:[String]
    public var newlyUnmetRequirementIDs:[String]
    public var remainingUnknownIDs:[String]
}
public struct StressTestFinding: Codable, Sendable {
    public var id:String; public var objectiveID:String; public var subjectIDs:[String]; public var dependencyIDs:[String]
    public var evidenceIDs:[String]; public var assumptions:[String]; public var criterionID:String
    public var failed:Bool; public var baseline:SessionReceipt; public var controlledRetest:SessionReceipt?
    public var schedule:[SessionCommand]
    public var dependencies:[DependencyInspection]
    public var sourceHouseholdDigest:String
    public var sourceHomeFingerprint:String?
    public var sourceInventoryDigest:String?
    public var sourceConcernDigest:String?
    public var retestPlan:StressRetestPlan?
    public var retestIntervention:Intervention?
    public var comparison:StressRetestComparison?
}
public enum PlanStressTester {
    /// Same recorded external schedule for intervention comparisons. Never a fresh director reroll.
    public static func execute(initial:RehearsalInput,profileIDs:[String],library:ScenarioLibrary,intervention:Intervention?=nil,inventory:SessionInventorySeed?=nil,concernSeed:ConcernExerciseSeed?=nil,dependencyPolicy:DependencyInspectionPolicy? = .recordedAccess,retestPlan:StressRetestPlan?=nil) throws -> StressTestFinding {
        guard let scenario=library.scenario(initial.scenarioID),!profileIDs.isEmpty,profileIDs.count<=8 else {throw SessionError.invalidCommand}
        if let retestPlan {
            // Preparation changes must use the same host validation/ownership as genuine user actions.
            // No time advancement, resource grants or director commands can masquerade as preparation.
            guard retestPlan.version=="dryrun.stress-retest/1",!retestPlan.commands.isEmpty,retestPlan.commands.count<=8,
                  retestPlan.commands.allSatisfy({command in
                      guard command.minute==nil,command.hazard==nil,command.durationMinutes==nil else {return false}
                      if command.kind=="useStoredWater" {return command.target==nil && ["essential","all"].contains(command.value)}
                      return ["takeSupply","transferSupply","moveTo","assignHelper","closeDoor","allocatePower"].contains(command.kind) && command.target?.isEmpty==false && command.value?.isEmpty==false
                  }) else {throw SessionError.invalidCommand}
        }
        var schedule:[SessionCommand]=[]
        for id in profileIDs {
            guard let event=scenario.events.first(where:{$0.id==id}) else {throw SessionError.invalidCommand}
            schedule.append(SessionCommand(kind:"schedule",target:id,minute:event.minute))
        }
        // The host may stop at depletion; bounded repeated advances reach the same final horizon.
        func run(_ input:RehearsalInput,preparation:StressRetestPlan?=nil)throws->(SessionReceipt,[DependencyInspection]) {
            var session=SimulationSession(id:"stress",initial:input,inventory:inventory,concernSeed:concernSeed,dependencyPolicy:dependencyPolicy)
            if let preparation {
                try session.commit(.init(id:"retest-preparation",actor:"user",baseRevision:0,commands:preparation.commands),library:library)
            }
            try session.commit(SessionCommit(id:"schedule",actor:"director",baseRevision:session.revision,commands:schedule),library:library)
            var receipt=try session.query(library:library)
            for n in 0..<64 where receipt.snapshot.simMinute<scenario.durationMinutes {
                receipt=try session.commit(SessionCommit(id:"advance-\(n)",actor:"director",baseRevision:session.revision,commands:[SessionCommand(kind:"advance",minute:scenario.durationMinutes)]),library:library)
            }
            return (receipt,try session.dependencyInspection(receipt:receipt,library:library))
        }
        let concernDigest=try concernSeed.map{StableDigest.of(try DryRunJSON.encoder().encode($0))}
        let (baseline,dependencies)=try run(initial)
        var retest:SessionReceipt?
        if intervention != nil || retestPlan != nil {
            var copy=initial
            if let intervention {copy.interventions.append(intervention)}
            retest=try run(copy,preparation:retestPlan).0
        }
        let comparison:StressRetestComparison? = retest.flatMap {receipt in
            guard dependencyPolicy == .recordedAccess || retestPlan != nil else {return nil}
            let before=Set(baseline.snapshot.unmetRequirements),after=Set(receipt.snapshot.unmetRequirements)
            return .init(baselineMinute:baseline.snapshot.simMinute,retestMinute:receipt.snapshot.simMinute,
                commonHorizonReached:baseline.snapshot.simMinute==scenario.durationMinutes && receipt.snapshot.simMinute==scenario.durationMinutes,
                resolvedRequirementIDs:before.subtracting(after).sorted(),remainingRequirementIDs:Array(after).sorted(),
                newlyUnmetRequirementIDs:after.subtracting(before).sorted(),remainingUnknownIDs:receipt.snapshot.unknowns.sorted())
        }
        let shared=baseline.routes.flatMap(\.sharedChokepoints)
        let unmet=Set(baseline.snapshot.unmetRequirements)
        let criterion = !shared.isEmpty || unmet.contains(where:{$0.hasPrefix("req.egress")}) ? "escape"
            : unmet.contains("req.water") ? "water"
            : unmet.contains("req.food") ? "food"
            : unmet.contains(where:{$0.hasPrefix("req.power") || $0.hasPrefix("req.refrigeration")}) ? "device"
            : unmet.contains(where:{$0.hasPrefix("req.comms")}) ? "contact" : "advisory"
        let sharedPower=initial.household.backupPower.filter{b in initial.household.equipment.filter{$0.compatibleBackupIDs.contains(b.id)}.count>1}.map{ "backup.\($0.id)" }

        return StressTestFinding(id:"stress|\(initial.scenarioID)|\(profileIDs.joined(separator:"|"))"+(concernDigest.map{"|concern|\($0)"} ?? ""),objectiveID:criterion,subjectIDs:initial.household.people.map(\.id),
            dependencyIDs:Array(Set(shared+sharedPower+baseline.snapshot.unmetRequirements)).sorted(),evidenceIDs:[baseline.contextDigest],
            assumptions:["Reviewed educational incident profiles; not a prediction of real failure"]+(concernSeed != nil ? ["User-selected hypothetical concern opening exclusions; outside the scored robustness envelope"]:[]),criterionID:criterion,failed:!baseline.snapshot.unmetRequirements.isEmpty || !shared.isEmpty,
            baseline:baseline,controlledRetest:retest,schedule:schedule,dependencies:dependencies,sourceHouseholdDigest:StableDigest.of(try DryRunJSON.encoder().encode(initial.household)),sourceHomeFingerprint:initial.home.map(HomeFingerprint.of),sourceInventoryDigest:try inventory.map{StableDigest.of(try DryRunJSON.encoder().encode($0))},sourceConcernDigest:concernDigest,retestPlan:retestPlan,
            retestIntervention:dependencyPolicy == .recordedAccess || retestPlan != nil ? intervention:nil,comparison:comparison)
    }
}
