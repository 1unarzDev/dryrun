import Foundation

/// Narrow versioned anchors. Unsupported situations remain unassessed, never guessed by a model.
public enum PracticeEvaluator {
    public static func evaluate(competencyID:String,actionID:String,session:SimulationSession,library:ScenarioLibrary) throws -> PracticeAnswer {
        guard let index=session.commits.firstIndex(where:{$0.id==actionID && $0.actor=="user"}),
              session.commits[index].commands.count==1 else {throw SessionError.invalidCommand}
        var prefix=SimulationSession(id:session.id,initial:session.initial,inventory:session.inventory,directorPolicy:session.directorPolicy,concernSeed:session.concernSeed)
        for commit in session.commits.prefix(index) {try prefix.commit(commit,library:library)}
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
            guard let id=command.target, let old=before.routes.first(where:{$0.request.personID==id}),
                  old.primary==nil,let route=after.routes.first(where:{$0.request.personID==id}) else {throw SessionError.invalidCommand}
            credit=route.primary == nil ? 0 : 1
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
}
