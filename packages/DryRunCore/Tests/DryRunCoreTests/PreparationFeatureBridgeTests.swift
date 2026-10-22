import Foundation
import Testing
@testable import DryRunCore

/// Writes the native preparation-feature requests (parsed by services/ai-orchestrator/test/native-bridge.test.ts) and
/// checks that a model answer can only reorder and explain the household's own Prepare list.
@Suite("Native preparation feature bridge") struct PreparationFeatureBridgeTests {
    static let date = Date(timeIntervalSince1970: 1_792_000_000)

    func rubric() throws -> RubricDefinition {
        try JSONDecoder().decode(RubricDefinition.self, from: Data(contentsOf: SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
    }

    func summary(_ h: HouseholdProfile, home: HomeModel?) throws -> NextStepsSummary {
        let results = try SimFixtures.scenarioIDs.map { try SimFixtures.run(h, $0) }
        return NextSteps.summarize(results, household: h, home: home, referenceDate: Self.date)
    }

    @Test(arguments: SampleHouseholds.all.map(\.id))
    func requestsAreMinimizedAndRecorded(_ id: String) throws {
        let h = try #require(SampleHouseholds.all.first { $0.id == id })
        let request = try PreparationFeatureBridge.request(requestID: "native-prep-\(id)", household: h, home: SampleHomes.ranch,
                                                           inventory: InventoryLedger(), rubric: rubric(), at: Self.date)
        #expect(request.synthetic && request.role == "preparation")
        #expect(Set(request.context.taskCatalog.map(\.actionID)).isSubset(of: Set(request.context.allowedActionIDs)))
        let data = try DryRunJSON.encoder().encode(request)
        let dir = SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/native-bridge", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("feature-request-preparation-\(id).json"))
        let json = String(decoding: data, as: UTF8.self)
        for secret in [h.displayName] + h.contacts.compactMap(\.phone) + h.people.map(\.alias) where !secret.isEmpty {
            #expect(!json.contains(secret), "leaked \(secret)")
        }
    }

    /// A recorded live Gemini answer to the Oak request: accepted against Oak's own list, shown without internal IDs.
    @Test func recordedLiveAnswerIsAcceptedAndReadable() throws {
        struct Recorded: Decodable { struct Response: Decodable { var proposal: PreparationFeatureBridge.Output }; var response: Response }
        let url = SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/live-preparation/oak-2026-10-20.json")
        let output = try JSONDecoder().decode(Recorded.self, from: Data(contentsOf: url)).response.proposal
        let h = SampleHouseholds.oak
        let p = PreparationFeatureBridge.accept(output, summary: try summary(h, home: SampleHomes.ranch), household: h)
        #expect(p.ranked.first?.stepID == "prep.medicalBackup|equipment.eq-oxygen")
        #expect(p.rejectedCount == 0 && p.ranked.count == output.tasks.count)
        for text in p.ranked.map(\.why) + [p.question ?? ""] {
            #expect(!text.contains("eq-oxygen") && !text.contains("bk-station"), "\(text)")
        }
        #expect(p.ranked[0].why.contains("Portable battery station") || p.ranked[0].why.contains("oxygen concentrator"))
    }

    @Test func aRealHouseholdIsNeverSent() throws {
        var real = SampleHouseholds.oak; real.isFictional = false
        #expect(throws: SessionError.self) {
            try PreparationFeatureBridge.request(requestID: "r", household: real, home: nil, inventory: InventoryLedger(), rubric: rubric())
        }
    }

    @Test func onlyCurrentPrepareItemsAreAcceptedAndTiersAreKept() throws {
        let h = SampleHouseholds.oak
        let s = try summary(h, home: SampleHomes.ranch)
        let lastTier = try #require(s.toDo.last), firstTier = try #require(s.toDo.first)
        #expect(lastTier.recommendation.tier > firstTier.recommendation.tier)
        func task(_ step: NextStep, _ why: String = "Recorded fact → implication → action.") -> PreparationFeatureBridge.Output.Task {
            .init(id: step.id, actionID: step.recommendation.actionID, subjectID: step.recommendation.subjectID ?? "household", why: why)
        }
        let output = PreparationFeatureBridge.Output(tasks: [
            task(lastTier),
            .init(id: "prep.invented", actionID: "prep.invented", subjectID: "household", why: "Not on the list."),
            .init(id: "x", actionID: "prep.bespoke", subjectID: "household", why: "An idea.",
                  bespoke: .init(title: "Label the cooler", fact: "f", implication: "i", action: "a", completionCheck: "c")),
        ], question: "Where is the cooler kept?")
        let p = PreparationFeatureBridge.accept(output, summary: s)
        #expect(p.ranked.map(\.stepID) == [lastTier.id])
        #expect(p.ideas.map(\.title) == ["Label the cooler"])
        #expect(p.rejectedCount == 1)
        // A mismatched subject is refused even with a valid ID; a repeated step counts once.
        var wrongSubject = task(firstTier); wrongSubject.subjectID = "equipment.other"
        let twice = PreparationFeatureBridge.accept(.init(tasks: [task(firstTier), task(firstTier), wrongSubject]), summary: s)
        #expect(twice.ranked.count == 1 && twice.rejectedCount == 2)
        // Ranking the lowest-tier item first still leaves every more urgent item above it.
        let ordered = PreparationFeatureBridge.order(s.toDo, by: p)
        #expect(ordered.map(\.recommendation.tier) == s.toDo.map(\.recommendation.tier))
        #expect(Set(ordered.map(\.id)) == Set(s.toDo.map(\.id)))
        // Within a tier, the model's choice leads.
        let sameTier = s.toDo.filter { $0.recommendation.tier == firstTier.recommendation.tier }
        if sameTier.count > 1, let later = sameTier.last {
            let promoted = PreparationFeatureBridge.order(s.toDo, by: PreparationFeatureBridge.accept(.init(tasks: [task(later)]), summary: s))
            #expect(promoted.first?.id == later.id)
        }
    }
}
