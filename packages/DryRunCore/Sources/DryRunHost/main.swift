import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import DryRunCore

struct HostRequest: Decodable {
    var op: String
    var session: SimulationSession?
    var commit: SessionCommit?
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
    var session: SimulationSession
    var receipt: SessionReceipt
    var profiles: [AuthoredEvent]
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
let library = try ScenarioLibrary.load(from: URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "content/scenarios"))
let decoder = DryRunJSON.decoder()
let encoder = DryRunJSON.encoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
while let line = readLine() {
    do {
        let request = try decoder.decode(HostRequest.self, from: Data(line.utf8))
        var session: SimulationSession
        if request.op == "initialize" {
            let household = request.sample == "lake" ? SampleHouseholds.lake : request.sample == "pine" ? SampleHouseholds.pine : SampleHouseholds.oak
            guard let scenario = library.scenario(request.scenarioID ?? "freeze-power-loss") else { throw SessionError.invalidCommand }
            let input = request.input ?? RehearsalInput(household: household, home: SampleHomes.ranch, scenarioID: scenario.id,
                scenarioVersion: scenario.version, contentVersion: "2026.10.2", seed: 7)
            session = SimulationSession(id: "synthetic-session", initial: input)
        } else {
            guard let supplied = request.session else { throw SessionError.invalidCommand }; session = supplied
        }
        var confirmedInventory:InventoryLedger?
        if request.op == "confirmInventory" {
            guard session.revision==0,let items=request.inventoryItems else {throw SessionError.invalidCommand}
            var input=session.initial,local=IntegratedAIState(inventory:request.inventory ?? InventoryLedger())
            let date=ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
            try local.confirmInventory(items,household:&input.household,baseHouseholdRevision:input.household.revision,baseInventoryRevision:local.inventory.revision,at:date,persist:{_,_ in})
            session=SimulationSession(id:session.id,initial:input,inventory:SessionInventorySeed(ledger:local.inventory,asOf:date));confirmedInventory=local.inventory
        }
        if request.op == "commit", let commit = request.commit { try session.commit(commit, library: library) }
        if request.op == "fallback" { try session.commit(session.fallback(), library: library) }
        let receipt: SessionReceipt
        if request.op == "preview" { guard let commit=request.commit else {throw SessionError.invalidCommand}; receipt=try session.preview(commit,library:library) }
        else {receipt=try session.query(library:library)}
        let date = ISO8601DateFormatter().date(from:"2026-10-19T00:00:00Z")!
        var assessments:[CriterionAssessment]?, scorecard:PreparednessScorecard?, gaps:[SupplyGap]?, stress:StressTestFinding?
        if request.op == "assess", let rubric=request.rubric {
            assessments = try request.assessments ?? HouseholdAssessment.assess(household:session.initial.household,home:session.initial.home,inventory:request.inventory,stressFindings:request.stressFindings ?? [],at:date)
            scorecard = try ScoreCompiler.compile(rubric:rubric,assessments:assessments!,attempts:request.attempts ?? [])
        }
        if request.op == "inventory" || request.op == "confirmInventory", let inventory=confirmedInventory ?? request.inventory {gaps = [try inventory.waterGap(people:session.initial.household.people.count,at:date)]}
        if request.op == "stress" {stress = try PlanStressTester.execute(initial:session.initial,profileIDs:request.profileIDs ?? [],library:library,intervention:request.intervention,inventory:session.inventory)}
        let response = HostResponse(session: session, receipt: receipt, profiles: library.scenario(session.initial.scenarioID)!.events.filter { Applicability.holds($0.when, household:session.initial.household,home:session.initial.home,variants:session.initial.variants) }, householdContext: HouseholdContextSnapshot(session.initial.household), homeScene: session.initial.home.map(HomeSceneContext.init), preparationActions: BaselinePreparedness.evaluate(household:session.initial.household,home:session.initial.home,referenceDate:date).map(\.actionID), taskCatalog:request.rubric.map{PreparationTaskCatalog.build(household:session.initial.household,home:session.initial.home,rubric:$0,at:date)}, assessments:assessments, scorecard:scorecard, gaps:gaps, stress:stress, tool:try request.tool.map{try session.executeTool($0,library:library)},inventory:confirmedInventory)
        print(String(decoding: try encoder.encode(response), as: UTF8.self))
        fflush(nil)
    } catch { print("{\"error\":\"\(error is SessionError ? String(describing: error) : "invalid_request")\"}"); fflush(nil) }
}
