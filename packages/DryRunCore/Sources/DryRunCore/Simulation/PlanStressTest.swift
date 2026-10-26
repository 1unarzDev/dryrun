import Foundation
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
}
public enum PlanStressTester {
    /// Same recorded external schedule for intervention comparisons. Never a fresh director reroll.
    public static func execute(initial:RehearsalInput,profileIDs:[String],library:ScenarioLibrary,intervention:Intervention?=nil,inventory:SessionInventorySeed?=nil,concernSeed:ConcernExerciseSeed?=nil) throws -> StressTestFinding {
        guard let scenario=library.scenario(initial.scenarioID),!profileIDs.isEmpty,profileIDs.count<=8 else {throw SessionError.invalidCommand}
        var schedule:[SessionCommand]=[]
        for id in profileIDs {
            guard let event=scenario.events.first(where:{$0.id==id}) else {throw SessionError.invalidCommand}
            schedule.append(SessionCommand(kind:"schedule",target:id,minute:event.minute))
        }
        // The host may stop at depletion; bounded repeated advances reach the same final horizon.
        func run(_ input:RehearsalInput)throws->SessionReceipt {
            var session=SimulationSession(id:"stress",initial:input,inventory:inventory,concernSeed:concernSeed)
            try session.commit(SessionCommit(id:"schedule",actor:"director",baseRevision:0,commands:schedule),library:library)
            var receipt=try session.query(library:library)
            for n in 0..<64 where receipt.snapshot.simMinute<scenario.durationMinutes {
                receipt=try session.commit(SessionCommit(id:"advance-\(n)",actor:"director",baseRevision:session.revision,commands:[SessionCommand(kind:"advance",minute:scenario.durationMinutes)]),library:library)
            }
            return receipt
        }
        let concernDigest=try concernSeed.map{StableDigest.of(try DryRunJSON.encoder().encode($0))}
        let baseline=try run(initial)
        var retest:SessionReceipt?
        if let intervention {
            var copy=initial;copy.interventions.append(intervention);retest=try run(copy)
        }
        let shared=baseline.routes.flatMap(\.sharedChokepoints)
        let unmet=Set(baseline.snapshot.unmetRequirements)
        let criterion = !shared.isEmpty || unmet.contains(where:{$0.hasPrefix("req.egress")}) ? "escape"
            : unmet.contains("req.water") ? "water"
            : unmet.contains(where:{$0.hasPrefix("req.power") || $0.hasPrefix("req.refrigeration")}) ? "device"
            : unmet.contains(where:{$0.hasPrefix("req.comms")}) ? "contact" : "advisory"
        let sharedPower=initial.household.backupPower.filter{b in initial.household.equipment.filter{$0.compatibleBackupIDs.contains(b.id)}.count>1}.map{ "backup.\($0.id)" }

        return StressTestFinding(id:"stress|\(initial.scenarioID)|\(profileIDs.joined(separator:"|"))"+(concernDigest.map{"|concern|\($0)"} ?? ""),objectiveID:criterion,subjectIDs:initial.household.people.map(\.id),
            dependencyIDs:Array(Set(shared+sharedPower+baseline.snapshot.unmetRequirements)).sorted(),evidenceIDs:[baseline.contextDigest],
            assumptions:["Reviewed educational incident profiles; not a prediction of real failure"]+(concernSeed != nil ? ["User-selected hypothetical concern opening exclusions; outside the scored robustness envelope"]:[]),criterionID:criterion,failed:!baseline.snapshot.unmetRequirements.isEmpty || !shared.isEmpty,
            baseline:baseline,controlledRetest:retest,schedule:schedule,dependencies:SimulationSession(id:"stress-inspect",initial:initial).dependencyInspection(receipt:baseline),sourceHouseholdDigest:StableDigest.of(try DryRunJSON.encoder().encode(initial.household)),sourceHomeFingerprint:initial.home.map(HomeFingerprint.of),sourceInventoryDigest:try inventory.map{StableDigest.of(try DryRunJSON.encoder().encode($0))},sourceConcernDigest:concernDigest)
    }
}
