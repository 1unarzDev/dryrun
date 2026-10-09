import Foundation
import Testing
@testable import DryRunCore

@Suite("Rehearsal cursor and stale-result gate")
struct PlanSessionTests {
    static func result(choices: [String: String] = [:]) -> RehearsalResult {
        let h = SampleHouseholds.oak
        let home = PlanBuilderTests.tinyHome()
        let input = RehearsalInput(household: h, home: home, scenarioID: "s", scenarioVersion: "1", contentVersion: "1", choices: choices)
        let link = EvidenceLink(ruleID: "rule.test")
        let events = [
            SimulationEvent(id: "e1", simMinute: 0, phaseID: "p", titleKey: "k", evidence: link),
            SimulationEvent(id: "e2", simMinute: 30, phaseID: "p", titleKey: "k", evidence: link),
            SimulationEvent(id: "e3", simMinute: 90, phaseID: "p", titleKey: "k", evidence: link),
        ]
        let decision = DecisionPoint(id: "d1", simMinute: 30, promptKey: "p", options: [
            .init(id: "a", labelKey: "a", feedbackKey: "fa", isRecommended: true),
            .init(id: "b", labelKey: "b", feedbackKey: "fb", isRecommended: false),
        ])
        return RehearsalResult(input: input, events: events, snapshots: [], decisions: [decision], routes: [],
                               recommendations: [], unknowns: [], engineVersion: "t")
    }

    @Test("Cursor stops at an unanswered decision and resumes after the re-run includes the choice")
    func cursorStopsAtDecision() {
        var c = RehearsalCursor(result: Self.result())
        c.advanceUntilDecisionOrEnd()
        #expect(c.revealed == 1, "event at minute 30 must wait for the decision at minute 30")
        #expect(c.pendingDecision?.id == "d1")
        c.advance()
        #expect(c.revealed == 1, "advance is blocked while a decision is pending")
        c.replace(result: Self.result(choices: ["d1": "a"]))
        #expect(c.revealed == 1, "re-running with the choice keeps the user's place")
        #expect(c.pendingDecision == nil)
        c.advanceUntilDecisionOrEnd()
        #expect(c.isFinished)
        #expect(c.currentMinute == 90)
    }

    @Test("A late result from an older request is rejected; so is a result for an older household revision")
    func gateRejectsStale() {
        var gate = LatestRequestGate()
        let k1 = RevisionKey(householdID: "h", householdRevision: 1, homeID: "m", homeRevision: 1, contentVersion: "c", algorithmVersion: "a")
        var k2 = k1; k2.householdRevision = 2
        let older = gate.begin(for: k1)
        let newer = gate.begin(for: k1)
        #expect(!gate.shouldApply(older, current: k1), "older request finishing late must not apply")
        #expect(gate.shouldApply(newer, current: k1))
        #expect(!gate.shouldApply(newer, current: k2), "household edited while computing: drop the result")
        gate.invalidate()
        #expect(!gate.shouldApply(newer, current: k1), "invalidate (edit/delete-all) drops outstanding work")
    }
}
