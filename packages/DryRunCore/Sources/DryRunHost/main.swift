import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import DryRunCore

struct HostRequest: Decodable {
    var intent:UserActionIntent?
    var submission:ActionSubmission?
    var aiState:IntegratedAIState?
    var attemptID:String?
    var variantID:String?
    var competencyID:String?
    var feedbackActionID:String?
    var resourceTasks:[PreparationTaskProposal]?
    var strategyDependencies:[ResourceStrategyDependency]?
    var concernProposal:HomeConcernProposal?
    var imageManifest:RoomImageManifest?
    var concernDecision:ConcernDecision?
    var concernID:String?
    var selectedPortalIDs:[String]?
    var allowHypothetical:Bool?
    var op: String
    var session: SimulationSession?
    var commit: SessionCommit?
    var proposal:DirectorProposal?
    var binding:AgentContextBinding?
    var sample: String?
    var scenarioID: String?
    var input: RehearsalInput?
    var rubric: RubricDefinition?
    var assessments: [CriterionAssessment]?
    var attempts: [PracticeAttempt]?
    var inventory: InventoryLedger?
    var inventoryItems:[InventoryItem]?
    var profileIDs: [String]?
    var stressFindings:[StressTestFinding]?
    var intervention: Intervention?
    var tool:SessionToolRequest?
}
struct HostResponse: Encodable {
    var resourceStrategyKey:ResourceStrategyKey?
    var concernTasks:[ConcernTaskLink]?
    var intentResult:IntentCommitReceipt?
    var aiState:IntegratedAIState?
    var session: SimulationSession
    var receipt: SessionReceipt
    var profiles: [AuthoredEvent]
    var directorProfiles:[DirectorProfileDescriptor]?
    var householdContext: HouseholdContextSnapshot
    var homeScene: HomeSceneContext?
    var preparationActions: [String]
    var taskCatalog:[PreparationTaskProposal]?
    var assessments: [CriterionAssessment]?
    var scorecard: PreparednessScorecard?
    var gaps: [SupplyGap]?
    var stress: StressTestFinding?
    var tool:SessionToolResponse?
    var inventory:InventoryLedger?
}
let scenarioDirectory=URL(fileURLWithPath:CommandLine.arguments.dropFirst().first ?? "content/scenarios")
let library=try ScenarioLibrary.load(from:scenarioDirectory)
let decoder = DryRunJSON.decoder()
let sourceContentVersion=(try? decoder.decode(ContentManifest.self,from:Data(contentsOf:scenarioDirectory.deletingLastPathComponent().appendingPathComponent("manifest.json"))))?.contentVersion ?? "unversioned-custom-pack"
let encoder = DryRunJSON.encoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
while let line = readLine() {
    do {
        let request = try decoder.decode(HostRequest.self, from: Data(line.utf8))
        guard ["initialize","query","tool","commit","directorCommit","interpretCommit","fallback","preview","assess","inventory","confirmInventory","stress","practiceBegin","practiceSubmit","practiceFeedback","reviewConcern","concernExercise","resourceKey"].contains(request.op) else {throw SessionError.invalidCommand}
        var session: SimulationSession
        if request.op == "initialize" {
            let household = request.sample == "lake" ? SampleHouseholds.lake : request.sample == "pine" ? SampleHouseholds.pine : SampleHouseholds.oak
            guard let scenario = library.scenario(request.input?.scenarioID ?? request.scenarioID ?? "freeze-power-loss") else { throw SessionError.invalidCommand }
            let input = request.input ?? RehearsalInput(household: household, home: SampleHomes.ranch, scenarioID: scenario.id,
                scenarioVersion: scenario.version, contentVersion: sourceContentVersion, seed: 7)
            session = try SimulationSession.initialize(id:"synthetic-session",initial:input,library:library)
        } else {
            guard let supplied = request.session else { throw SessionError.invalidCommand }; session = supplied
        }
        var intentResult:IntentCommitReceipt?
        if request.op=="interpretCommit" {
            guard let intent=request.intent,let submission=request.submission else {throw SessionError.invalidCommand}
            intentResult=try intent.commit(submission:submission,to:&session,library:library)
        }
        var aiState=request.aiState
        var concernTasks:[ConcernTaskLink]?
        if request.op=="reviewConcern" {
            guard let proposal=request.concernProposal,let manifest=request.imageManifest,let decision=request.concernDecision,
                  let rubric=request.rubric,let home=session.initial.home else {throw SessionError.invalidCommand}
            if aiState==nil {aiState=IntegratedAIState()}
            let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
            try aiState!.reviewConcern(proposal,decision:decision,manifest:manifest,home:home,household:session.initial.household,rubric:rubric,library:library,at:date)
            concernTasks=aiState!.concernTasks(currentHome:home)
        }
        if request.op=="concernExercise" {
            guard let aiState,let id=request.concernID,let portals=request.selectedPortalIDs,let home=session.initial.home else {throw SessionError.invalidCommand}
            let seed=try aiState.concernExerciseSeed(concernID:id,scenarioID:session.initial.scenarioID,selectedPortalIDs:portals,allowHypothetical:request.allowHypothetical ?? false,home:home)
            session=try SimulationSession.initialize(id:"concern-exercise",initial:session.initial,library:library,inventory:session.inventory,concernSeed:seed)
        }
        if request.op.hasPrefix("practice") {
            if aiState==nil {aiState=IntegratedAIState(sessions:[session])}
            guard let attemptID=request.attemptID else {throw SessionError.invalidCommand}
            switch request.op {
            case "practiceBegin":
                guard let variantID=request.variantID else {throw SessionError.invalidCommand}
                try aiState!.beginPractice(id:attemptID,variantID:variantID,sessionID:session.id,library:library)
            case "practiceSubmit":
                guard let competency=request.competencyID,let commit=request.commit else {throw SessionError.invalidCommand}
                try aiState!.submitPracticeAction(attemptID:attemptID,competencyID:competency,commit:commit,library:library)
            case "practiceFeedback":
                guard let actionID=request.feedbackActionID else {throw SessionError.invalidCommand}
                try aiState!.revealPracticeFeedback(attemptID:attemptID,actionID:actionID)
            default:throw SessionError.invalidCommand
            }
            guard let captured=aiState!.sessions.first(where:{$0.id==session.id}) else {throw SessionError.invalidCommand}
            session=captured
        }
        var confirmedInventory:InventoryLedger?
        if request.op == "confirmInventory" {
            guard session.revision==0,let items=request.inventoryItems else {throw SessionError.invalidCommand}
            var input=session.initial,local=IntegratedAIState(inventory:request.inventory ?? InventoryLedger())
            let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
            try local.confirmInventory(items,household:&input.household,baseHouseholdRevision:input.household.revision,baseInventoryRevision:local.inventory.revision,at:date,persist:{_,_ in})
            session=SimulationSession(id:session.id,initial:input,inventory:SessionInventorySeed(ledger:local.inventory,asOf:date),directorPolicy:session.directorPolicy,concernSeed:session.concernSeed);confirmedInventory=local.inventory
        }
        if request.op == "commit", let commit = request.commit { try session.commit(commit, library: library) }
        if request.op == "directorCommit" {guard let proposal=request.proposal,let binding=request.binding else {throw SessionError.invalidCommand};try proposal.commit(to:&session,binding:binding,library:library,persist:{_ in})}
        if request.op == "fallback" { try session.commit(session.fallback(), library: library) }
        let receipt: SessionReceipt
        if request.op == "preview" { guard let commit=request.commit else {throw SessionError.invalidCommand}; receipt=try session.preview(commit,library:library) }
        else {receipt=try session.query(library:library)}
        let date = ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
        var assessments:[CriterionAssessment]?, scorecard:PreparednessScorecard?, gaps:[SupplyGap]?, stress:StressTestFinding?
        if request.op == "assess", let rubric=request.rubric {
            assessments = try request.assessments ?? HouseholdAssessment.assess(household:session.initial.household,home:session.initial.home,inventory:request.inventory,stressFindings:request.stressFindings ?? [],at:date)
            if let aiState {scorecard=try aiState.compileScorecard(rubric:rubric,assessments:assessments!,library:library)}
            else {scorecard = try ScoreCompiler.compile(rubric:rubric,assessments:assessments!,attempts:request.attempts ?? [])}
        }
        if request.op == "inventory" || request.op == "confirmInventory", let inventory=confirmedInventory ?? request.inventory {gaps = [try inventory.waterGap(people:session.initial.household.people.count,at:date)]}
        if request.op == "stress" {stress = try PlanStressTester.execute(initial:session.initial,profileIDs:request.profileIDs ?? [],library:library,intervention:request.intervention,inventory:session.inventory,concernSeed:session.concernSeed)}
        var resourceStrategyKey:ResourceStrategyKey?
        if request.op=="resourceKey" {
            guard let inventory=request.inventory ?? session.inventory?.ledger,let tasks=request.resourceTasks else {throw SessionError.invalidCommand}
            let gap=try inventory.waterGap(people:session.initial.household.people.count,at:date)
            resourceStrategyKey=try ResourceStrategyKey.normalized(gaps:[gap],tasks:tasks,transport:HouseholdContextSnapshot(session.initial.household).transport,
                limitedBudget:session.initial.household.supplies.limitedBudget,regionID:session.initial.household.regionID,dependencies:request.strategyDependencies ?? [])
        }
        let response = HostResponse(resourceStrategyKey:resourceStrategyKey,concernTasks:concernTasks,intentResult:intentResult,aiState:aiState,session: session, receipt: receipt, profiles: library.scenario(session.initial.scenarioID)!.events.filter { Applicability.holds($0.when, household:session.initial.household,home:session.initial.home,variants:session.initial.variants) }, directorProfiles:library.scenario(session.initial.scenarioID).map{scenario in scenario.events.filter{Applicability.holds($0.when,household:session.initial.household,home:session.initial.home,variants:session.initial.variants)}.map{DirectorProfileDescriptor($0,in:scenario)}}, householdContext: HouseholdContextSnapshot(session.initial.household), homeScene: session.initial.home.map(HomeSceneContext.init), preparationActions: BaselinePreparedness.evaluate(household:session.initial.household,home:session.initial.home,referenceDate:date).map(\.actionID), taskCatalog:request.rubric.map{PreparationTaskCatalog.build(household:session.initial.household,home:session.initial.home,rubric:$0,at:date)}, assessments:assessments, scorecard:scorecard, gaps:gaps, stress:stress, tool:try request.tool.map{try session.executeTool($0,library:library)},inventory:confirmedInventory)
        print(String(decoding: try encoder.encode(response), as: UTF8.self))
        fflush(nil)
    } catch { print("{\"error\":\"\(error is SessionError ? String(describing: error) : "invalid_request")\"}"); fflush(nil) }
}
