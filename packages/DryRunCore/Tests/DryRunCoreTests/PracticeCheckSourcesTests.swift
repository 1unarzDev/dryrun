import Foundation
import Testing
@testable import DryRunCore

@Suite("Native practice check sources from the household's actual facts") struct PracticeCheckSourcesTests {
    let library = SimFixtures.library

    func begin(_ household: HouseholdProfile, home: HomeModel, variant: String) throws -> (IntegratedAIState, PracticeAttempt) {
        let sources = try PracticeCheckSources.prepare(attemptID: "check", variantID: variant, household: household, home: home,
                                                       contentVersion: "2026.10.0", library: library)
        var state = IntegratedAIState(sessions: sources)
        let attempt = try state.beginPracticeCheck(id: "check", variantID: variant, sessionIDs: sources.map(\.id), library: library)
        return (state, attempt)
    }

    @Test(arguments: ["practice-check-a/2", "practice-check-b/2"])
    func sourcesFreezeAndAnchoredAnswersEarnPracticeCredit(_ variant: String) throws {
        let household = SampleHouseholds.oak
        var (state, attempt) = try begin(household, home: SampleHomes.ranch, variant: variant)
        let order = IntegratedAIState.practiceOrder(variant)
        for competency in order {
            let session = try #require(try state.activePracticeCheckSession(attemptID: attempt.id, library: library))
            let command: SessionCommand
            switch competency {
            case "initialResponse": command = .init(kind: "choose", target: "choice.home-fire.first-move", value: "get-out")
            case "communication": command = .init(kind: "contact", target: try #require(household.contacts.first { $0.isComplete }).id)
            case "continuity": command = .init(kind: "useStoredWater", value: "essential")
            default:
                // Adaptation: a move the family might choose; the anchor decides whether it is assessable here.
                let room = try #require(SampleHomes.ranch.spaces.first { $0.kind == .livingRoom })
                command = .init(kind: "moveTo", target: household.people[0].id, value: room.id)
            }
            let observation = try state.submitPracticeAction(attemptID: attempt.id, competencyID: competency,
                commit: SessionCommit(id: "answer-\(competency)", actor: "user", baseRevision: session.revision, commands: [command]), library: library)
            #expect(observation.feedbackRevealed == false)
            _ = try state.revealPracticeFeedback(attemptID: attempt.id, actionID: observation.actionID)
        }
        #expect(try state.activePracticeCheckSession(attemptID: attempt.id, library: library) == nil)
        let rubric = try JSONDecoder().decode(RubricDefinition.self, from: Data(contentsOf: SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
        let assessments = try HouseholdAssessment.assess(household: household, home: SampleHomes.ranch, inventory: nil, at: Date())
        let card = try state.compileScorecard(rubric: rubric, assessments: assessments, library: library)
        // The three non-spatial anchors are supported for this household; each correct answer is worth 25.
        #expect(card.practice >= 75)
        #expect(card.practiceAssessed >= 3)
        attempt = try #require(state.practiceAttempts.last)
        #expect(attempt.observations?.count == 4)
    }

    @Test func anUnsafeFirstMoveEarnsZeroAndCannotBeRerolled() throws {
        var (state, attempt) = try begin(SampleHouseholds.oak, home: SampleHomes.ranch, variant: "practice-check-a/2")
        let session = try #require(try state.activePracticeCheckSession(attemptID: attempt.id, library: library))
        let observation = try state.submitPracticeAction(attemptID: attempt.id, competencyID: "initialResponse",
            commit: SessionCommit(id: "unsafe", actor: "user", baseRevision: session.revision,
                                  commands: [.init(kind: "choose", target: "choice.home-fire.first-move", value: "grab-belongings")]), library: library)
        #expect(observation.credit == 0)
        // Asking to begin again resumes the same attempt with its recorded answer.
        let resumed = try state.beginPracticeCheck(id: "another", variantID: "practice-check-b/2", sessionIDs: [], library: library)
        #expect(resumed.id == attempt.id)
        #expect(resumed.observations?.first?.credit == 0)
    }

    @Test func noHomeMeansNoCheckRatherThanASampleLayout() {
        #expect(throws: SessionError.self) {
            try PracticeCheckSources.prepare(attemptID: "x", variantID: "practice-check-a/2", household: SampleHouseholds.oak, home: nil,
                                             contentVersion: "2026.10.0", library: library)
        }
    }
}
