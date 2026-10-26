import Foundation

/// Short source-bound checks share the existing attempt log, receipts and fixed competency budget.
/// These anchors assess educational commands, never certify real-world safety or physical ability.
public struct HazardPracticeCheck:Codable,Sendable,Equatable {
    public var id:String
    public var scenarioID:String
    public var competencyID:String
    public var actionKind:String
    public var prompt:String
    func accepts(_ kind:String,composed:Bool)->Bool {
        kind==actionKind || (composed && ((actionKind=="escape" && kind=="accompanyEscape") || (actionKind=="reachShelter" && kind=="accompanyShelter")))
    }
    public static let bank:[HazardPracticeCheck]=[
        .init(id:"fire.escape/1",scenarioID:"home-fire",competencyID:"initialResponse",actionKind:"escape",prompt:"Choose a supported exit for a household member from their current room."),
        .init(id:"fire.account/1",scenarioID:"home-fire",competencyID:"communication",actionKind:"accountOutside",prompt:"Account for an escaped member at the recorded outside meetup."),
        .init(id:"tornado.shelter/1",scenarioID:"tornado",competencyID:"initialResponse",actionKind:"reachShelter",prompt:"Reach the recorded shelter using a supported approach."),
        .init(id:"tornado.alert/1",scenarioID:"tornado",competencyID:"communication",actionKind:"contact",prompt:"Practice contacting a complete recorded contact while a channel is available."),
        .init(id:"flood.depart/1",scenarioID:"flash-flood",competencyID:"adaptation",actionKind:"leaveEarly",prompt:"Use the recorded departure arrangement while exercise access remains available."),
        .init(id:"flood.gap/1",scenarioID:"flash-flood",competencyID:"adaptation",actionKind:"identifyGap",prompt:"Identify the modeled access or higher-refuge planning gap."),
        .init(id:"freeze.power/1",scenarioID:"freeze-power-loss",competencyID:"continuity",actionKind:"allocatePower",prompt:"Allocate a compatible recorded backup to an essential device during loss of power."),
        .init(id:"freeze.warmth/1",scenarioID:"freeze-power-loss",competencyID:"adaptation",actionKind:"warmLayers",prompt:"Use recorded warmth preparations during modeled heat loss."),
        .init(id:"heat.shade/1",scenarioID:"heat-grid-strain",competencyID:"adaptation",actionKind:"reduceSolarGain",prompt:"Select a recorded windowed room for the exercise shading assumption."),
        .init(id:"heat.alternative/1",scenarioID:"heat-grid-strain",competencyID:"continuity",actionKind:"cooledAlternative",prompt:"Use a recorded alternative while its access dependencies are available."),
        .init(id:"water.activity/1",scenarioID:"water-outage",competencyID:"initialResponse",actionKind:"useWater",prompt:"Choose an allowed supply and explicit exercise quantity for a household activity."),
        .init(id:"water.gap/1",scenarioID:"water-outage",competencyID:"continuity",actionKind:"identifyGap",prompt:"Identify the actual water quality, service or stored-supply gap.")
    ]
}
public extension IntegratedAIState {
    /// Completed checks leave this queue; explicit review of prior feedback remains in practiceAttempts.
    var pendingHazardChecks:[HazardPracticeCheck] {
        HazardPracticeCheck.bank.filter {check in !practiceAttempts.contains{$0.checkID==check.id && $0.observations?.isEmpty==false}}
    }
    func availableHazardChecks(in session:SimulationSession,library:ScenarioLibrary)throws->[HazardPracticeCheck] {
        let receipt=try session.query(library:library)
        return try pendingHazardChecks(household:session.initial.household,home:session.initial.home).filter {check in
            check.scenarioID==session.initial.scenarioID && receipt.experience?.feasibleCommands?.contains(where:{check.accepts($0.kind,composed:HazardExperience.level(session.mechanicsVersion)>=5)})==true
                && (check.actionKind != "warmLayers" || receipt.snapshot.services[Svc.heat] != .operational)
                && (check.actionKind != "allocatePower" || receipt.snapshot.services[Svc.homePower] == .unavailable)
        }
    }
    @discardableResult mutating func beginHazardCheck(id:String,checkID:String,sessionID:String,library:ScenarioLibrary,retest:Bool=false,
        persist:(IntegratedAIState)throws->Void={_ in})throws->PracticeAttempt {
        if let existing=practiceAttempts.first(where:{$0.checkID != nil && $0.observations?.isEmpty==true}) {return existing}
        guard !practiceAttempts.contains(where:{$0.checkID==nil && $0.archivedUnverified != true && ($0.observations?.count ?? $0.answers.count)<4}) else {throw SessionError.invalidCommand}
        guard !id.isEmpty,!practiceAttempts.contains(where:{$0.id==id}),
              let check=HazardPracticeCheck.bank.first(where:{$0.id==checkID}),
              let session=sessions.first(where:{$0.id==sessionID}),session.initial.scenarioID==check.scenarioID,
              session.mechanicsVersion.map({HazardExperience.supportedVersions.contains($0)})==true,session.concernSeed==nil,
              !session.commits.contains(where:{$0.actor=="user" && $0.commands.contains(where:{check.accepts($0.kind,composed:HazardExperience.level(session.mechanicsVersion)>=5)})}),
              !practiceAttempts.contains(where:{$0.source?.sessionID==sessionID}) else {throw SessionError.invalidCommand}
        let receipt=try session.query(library:library)
        guard !receipt.finished else {throw SessionError.finished}
        // An explicit retest bypasses retirement only, never the actual state/affordance prerequisites.
        guard receipt.experience?.feasibleCommands?.contains(where:{check.accepts($0.kind,composed:HazardExperience.level(session.mechanicsVersion)>=5)})==true,
              check.actionKind != "warmLayers" || receipt.snapshot.services[Svc.heat] != .operational,
              check.actionKind != "allocatePower" || receipt.snapshot.services[Svc.homePower] == .unavailable else {throw SessionError.invalidCommand}
        guard try retest || availableHazardChecks(in:session,library:library).contains(where:{$0.id==checkID}) else {throw SessionError.invalidCommand}
        var attempt=PracticeAttempt(id:id,sequence:(practiceAttempts.map(\.sequence).max() ?? 0)+1,variantID:"hazard-check/1",answers:[])
        attempt.checkID=checkID;attempt.checkVariant=practiceAttempts.filter{$0.checkID==checkID}.count.isMultiple(of:2) ? "a":"b";attempt.observations=[]
        attempt.source = .init(contractVersion:"dryrun.practice-capture/1",sessionID:sessionID,initialDigest:try Self.practiceSourceDigest(session),startingRevision:session.revision,startingEventSequence:receipt.eventSequence,evaluatorVersion:HazardExperience.level(session.mechanicsVersion)>=5 ? "dryrun.hazard-checks/2":"dryrun.hazard-checks/1",startingReceiptDigest:receipt.contextDigest)
        var candidate=self;candidate.practiceAttempts.append(attempt)
        try persist(candidate);self=candidate;return attempt
    }
    /// The actual first response and score refresh are persisted together before feedback is shown.
    /// Infeasible commands record an unsupported attempt with zero credit; no physical default is applied.
    @discardableResult mutating func submitHazardCheck(attemptID:String,commit:SessionCommit,library:ScenarioLibrary,
        rubric:RubricDefinition,assessments:[CriterionAssessment],persist:(IntegratedAIState)throws->Void={_ in})throws->PracticeObservation {
        guard let index=practiceAttempts.firstIndex(where:{$0.id==attemptID}),practiceAttempts[index].observations?.isEmpty==true,
              let source=practiceAttempts[index].source,let checkID=practiceAttempts[index].checkID,
              let check=HazardPracticeCheck.bank.first(where:{$0.id==checkID}),
              let si=sessions.firstIndex(where:{$0.id==source.sessionID}),commit.actor=="user",commit.commands.count==1,
              commit.baseRevision==source.startingRevision,sessions[si].revision==source.startingRevision,
              !practiceAttempts.flatMap({$0.observations ?? []}).contains(where:{$0.actionID==commit.id}) else {throw SessionError.invalidCommand}
        _=try validateHazardCheck(practiceAttempts[index],library:library)
        var candidate=self;var accepted=commit
        do {_=try candidate.sessions[si].preview(commit,library:library)}
        catch SessionError.invalidCommand {accepted.commands=[.init(kind:"unsupported")]}
        let receipt=try candidate.sessions[si].commit(accepted,library:library)
        let credit=try Self.hazardCheckCredit(check,source:source,session:candidate.sessions[si],library:library)
        let observation=PracticeObservation(competencyID:check.competencyID,actionID:commit.id,acceptedRevision:receipt.revision,receiptDigest:receipt.contextDigest,credit:credit,feedbackRevealed:false)
        candidate.practiceAttempts[index].observations=[observation]
        candidate.practiceAttempts[index].answers=[.init(competencyID:check.competencyID,credit:credit,committedActionID:commit.id,beforeFeedback:true)]
        let score=try candidate.compileScorecard(rubric:rubric,assessments:assessments,library:library,currentHousehold:candidate.sessions[si].initial.household,currentHome:candidate.sessions[si].initial.home)
        candidate.scorecards.append(score)
        try persist(candidate);self=candidate;return observation
    }
    func validateHazardCheck(_ attempt:PracticeAttempt,library:ScenarioLibrary)throws->PracticeAttempt {
        guard attempt.variantID=="hazard-check/1",let check=HazardPracticeCheck.bank.first(where:{$0.id==attempt.checkID}),
              let source=attempt.source,
              let session=sessions.first(where:{$0.id==source.sessionID}),session.initial.scenarioID==check.scenarioID,
              source.evaluatorVersion==(HazardExperience.level(session.mechanicsVersion)>=5 ? "dryrun.hazard-checks/2":"dryrun.hazard-checks/1"),
              session.mechanicsVersion.map({HazardExperience.supportedVersions.contains($0)})==true,session.concernSeed==nil,
              source.initialDigest==(try Self.practiceSourceDigest(session)),source.startingRevision>=0,source.startingRevision<=session.revision,
              let observations=attempt.observations,observations.count<=1,
              session.revision>=source.startingRevision+observations.count,
              !observations.isEmpty || session.revision==source.startingRevision else {throw SessionError.invalidCommand}
        var prefix=SimulationSession(id:session.id,initial:session.initial,inventory:session.inventory,directorPolicy:session.directorPolicy,concernSeed:session.concernSeed,dependencyPolicy:session.dependencyPolicy,mechanicsVersion:session.mechanicsVersion)
        for commit in session.commits.prefix(source.startingRevision) {try prefix.commit(commit,library:library)}
        let baseline=try prefix.query(library:library)
        guard baseline.contextDigest==source.startingReceiptDigest,baseline.eventSequence==source.startingEventSequence,
              !prefix.commits.contains(where:{$0.actor=="user" && $0.commands.contains(where:{check.accepts($0.kind,composed:HazardExperience.level(session.mechanicsVersion)>=5)})}) else {throw SessionError.stale}
        var accepted=attempt;accepted.answers=[]
        if let observation=observations.first {
            let command=session.commits[source.startingRevision]
            // Freeze grading at the actual first-response receipt. Later user
            // actions, director incidents or finish may continue the same exercise;
            // none can erase or improve this already recorded observation.
            let receipt=try prefix.commit(command,library:library)
            let credit=try Self.hazardCheckCredit(check,source:source,session:prefix,library:library)
            guard command.actor=="user",command.commands.count==1,observation.competencyID==check.competencyID,
                  observation.actionID==command.id,observation.acceptedRevision==receipt.revision,
                  observation.receiptDigest==receipt.contextDigest,observation.credit==credit else {throw SessionError.invalidCommand}
            accepted.answers=[.init(competencyID:check.competencyID,credit:credit,committedActionID:command.id,beforeFeedback:true)]
        }
        return accepted
    }
    private static func hazardCheckCredit(_ check:HazardPracticeCheck,source:PracticeAttemptSource,session:SimulationSession,library:ScenarioLibrary)throws->Double {
        let commit=session.commits[source.startingRevision]
        guard commit.commands.count==1 else {throw SessionError.invalidCommand}
        let command=commit.commands[0]
        guard check.accepts(command.kind,composed:source.evaluatorVersion=="dryrun.hazard-checks/2") else {return 0}
        let receipt=try session.query(library:library)
        if command.kind=="contact" {return receipt.snapshot.services[Svc.handset] == .operational && receipt.snapshot.services[Svc.cellular] == .operational ? 1:0}
        if command.kind=="allocatePower" {
            guard let target=command.target,session.initial.household.equipment.contains(where:{$0.id==target && $0.isEssential}),receipt.snapshot.services[Svc.homePower] == .unavailable else {return 0}
            return receipt.snapshot.services[Svc.device(target)] == .operational && command.value != "none" ? 1:0
        }
        // The command reducer already checks route, supply, advisory, access and recorded preparation.
        // Thermal checks require an actual unmet conditioning dependency, not just clicking a label.
        if command.kind=="warmLayers" {return receipt.snapshot.services[Svc.heat] != .operational ? 1:0}
        return 1
    }
}
