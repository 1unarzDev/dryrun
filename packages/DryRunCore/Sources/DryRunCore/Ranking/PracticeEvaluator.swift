import Foundation

/// Narrow versioned anchors. Unsupported situations remain unassessed, never guessed by a model.
public enum PracticeEvaluator {
    public static let version = "dryrun.practice-anchors/2"
    public static let legacyVersion = "dryrun.practice-anchors/1"
    public static func evaluate(competencyID:String,actionID:String,session:SimulationSession,library:ScenarioLibrary,evaluatorVersion:String = version) throws -> PracticeAnswer {
        guard [version,legacyVersion].contains(evaluatorVersion) else {throw SessionError.invalidCommand}
        guard let index=session.commits.firstIndex(where:{$0.id==actionID && $0.actor=="user"}),
              session.commits[index].commands.count==1 else {throw SessionError.invalidCommand}
        var prefix=SimulationSession(id:session.id,initial:session.initial,inventory:session.inventory,directorPolicy:session.directorPolicy,concernSeed:session.concernSeed,dependencyPolicy:session.dependencyPolicy)
        var history=[try prefix.query(library:library)]
        for commit in session.commits.prefix(index) {history.append(try prefix.commit(commit,library:library))}
        let before=try prefix.query(library:library)
        let action=session.commits[index]
        let after=try prefix.commit(action,library:library)
        let command=action.commands[0]
        let credit:Double
        switch (competencyID,command.kind) {
        case ("initialResponse","useStoredWater"):
            guard session.initial.scenarioID=="water-outage",before.snapshot.services[Svc.waterSupply] == .unavailable else {throw SessionError.invalidCommand}
            credit=command.value=="essential" ? 1 : 0
        case ("communication","contact"):
            guard let id=command.target,session.initial.household.contacts.contains(where:{$0.id==id && $0.isComplete}) else {throw SessionError.invalidCommand}
            // A recorded contact alone cannot establish a working communications channel.
            guard after.snapshot.services[Svc.handset] == .operational,
                  after.snapshot.services[Svc.cellular] == .operational else {throw SessionError.invalidCommand}
            credit=1
        case ("adaptation","moveTo"):
            if evaluatorVersion == legacyVersion {
                guard let id=command.target, let old=before.routes.first(where:{$0.request.personID==id}),
                      old.primary==nil,let route=after.routes.first(where:{$0.request.personID==id}) else {throw SessionError.invalidCommand}
                credit=route.primary == nil ? 0 : 1
            } else {
                credit=try adaptation(command:command,before:before,after:after,history:history,home:session.initial.home)
            }
        case ("continuity","allocatePower"):
            guard let id=command.target,session.initial.household.equipment.contains(where:{$0.id==id && $0.isEssential}) else {throw SessionError.invalidCommand}
            guard before.snapshot.services[Svc.homePower] == .unavailable,
                  let deviceState=after.snapshot.services[Svc.device(id)],deviceState != .unknown,
                  !after.snapshot.unknowns.contains(where:{$0.contains(id)}) else {throw SessionError.invalidCommand}
            credit=deviceState == .operational && command.value != "none" ? 1 : 0
        default:throw SessionError.invalidCommand
        }
        return PracticeAnswer(competencyID:competencyID,credit:credit,committedActionID:actionID,beforeFeedback:true)
    }
    /// Egress-only anchor. A committed blockage must invalidate a previously verified path
    /// from the same starting room. An unchanged route, a model claim or an arbitrary safe
    /// movement cannot establish adaptation. Shelter/refuge anchors remain unassessed.
    private static func adaptation(command:SessionCommand,before:SessionReceipt,after:SessionReceipt,history:[SessionReceipt],home:HomeModel?)throws->Double {
        guard let id=command.target,let destination=command.value,
              let current=before.routes.first(where:{$0.request.personID==id}),
              current.request.purpose == nil || current.request.purpose == .outdoorEgress,
              destination != current.request.startSpaceID else {throw SessionError.invalidCommand}
        let blockedSpaces=Set(current.request.exclusions.blockedSpaceIDs)
        let blockedPortals=Set(current.request.exclusions.blockedPortalIDs)
        guard !blockedSpaces.isEmpty || !blockedPortals.isEmpty,
              history.contains(where:{ receipt in
                  receipt.routes.contains(where:{ old in
                      guard old.request.personID==id,old.request.startSpaceID==current.request.startSpaceID,
                            old.request.purpose == nil || old.request.purpose == .outdoorEgress,
                            old.homeFingerprint==current.homeFingerprint,let path=old.primary,path.verificationNeeded.isEmpty else {return false}
                      return !blockedSpaces.isDisjoint(with:path.spaceSequence) || !blockedPortals.isDisjoint(with:path.portalSequence)
                  })
              }) else {throw SessionError.invalidCommand}
        guard let result=after.routes.first(where:{$0.request.personID==id}) else {throw SessionError.invalidCommand}
        // The host rejects an unsafe/unreachable move without changing the actual starting room.
        guard result.request.startSpaceID==destination,let path=result.primary else {
            if result.noRouteReason == .blockedByScenario {return 0}
            throw SessionError.invalidCommand
        }
        guard path.verificationNeeded.isEmpty else {throw SessionError.invalidCommand}
        guard let home,HomeFingerprint.of(home)==current.homeFingerprint else {throw SessionError.invalidCommand}
        let movement=EgressPlanner().plan(RouteRequest(personID:id,startSpaceID:current.request.startSpaceID,
            mobility:current.request.mobility,exclusions:current.request.exclusions,purpose:.helperReach,destinationSpaceID:destination),in:home)
        guard let movementPath=movement.primary,movementPath.verificationNeeded.isEmpty else {throw SessionError.invalidCommand}
        let supportedPaths=[current.primary,current.alternative].compactMap{$0}.filter{$0.verificationNeeded.isEmpty}
        guard supportedPaths.contains(where:{$0.spaceSequence.dropFirst().contains(destination)}) else {throw SessionError.invalidCommand}
        return 1
    }

}
