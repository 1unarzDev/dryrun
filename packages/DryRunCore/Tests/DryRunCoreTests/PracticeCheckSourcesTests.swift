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

    @Test func theSecondSetAsksDifferentQuestionsThanTheFirst() throws {
        let household = SampleHouseholds.oak
        func scenarios(_ variant: String) throws -> [String: String] {
            let sources = try PracticeCheckSources.prepare(attemptID: "x", variantID: variant, household: household, home: SampleHomes.ranch,
                                                           contentVersion: "2026.10.0", library: library)
            return Dictionary(uniqueKeysWithValues: zip(IntegratedAIState.practiceOrder(variant), sources.map(\.initial.scenarioID)))
        }
        let first = try scenarios("practice-check-a/2"), second = try scenarios(PracticeCheckSources.secondSetVariant)
        #expect(first["initialResponse"] == "home-fire" && second["initialResponse"] == "tornado")
        #expect(first["communication"] == "water-outage" && second["communication"] == "tornado")
        #expect(first["adaptation"] == "home-fire" && second["adaptation"] == "freeze-power-loss")
        #expect(first["continuity"] == "water-outage" && second["continuity"] == "freeze-power-loss")
        // Without essential equipment to power, continuity stays the assessable stored-water situation.
        var noDevices = household; noDevices.equipment = noDevices.equipment.map { var e = $0; e.isEssential = false; return e }
        let fallback = try PracticeCheckSources.prepare(attemptID: "y", variantID: PracticeCheckSources.secondSetVariant, household: noDevices,
                                                        home: SampleHomes.ranch, contentVersion: "2026.10.0", library: library)
        #expect(fallback[0].initial.scenarioID == "water-outage")
        // The fictional sample home starts on set A, a scanned home on set B, and later checks alternate.
        #expect(PracticeCheckSources.variant(previousChecks: 0) == "practice-check-a/2")
        #expect(PracticeCheckSources.variant(previousChecks: 0, scannedHome: true) == PracticeCheckSources.secondSetVariant)
        #expect(PracticeCheckSources.variant(previousChecks: 1, scannedHome: true) == "practice-check-a/2")
    }

    @Test func secondSetAnchoredAnswersEarnPracticeCredit() throws {
        var household = SampleHouseholds.oak
        // A fully documented device and backup, so the powered outcome is known rather than unknown.
        household.equipment[0].compatibleBackupIDs = ["bk-station"]
        household.equipment[0].documentedBackupRuntimeHours = .confirmed(4)
        household.equipment[0].powerWatts = .confirmed(10)
        household.backupPower[0].setupConfirmed = .confirmed(true)
        let variant = PracticeCheckSources.secondSetVariant
        var (state, attempt) = try begin(household, home: SampleHomes.ranch, variant: variant)
        var credits: [String: Double?] = [:]
        for competency in IntegratedAIState.practiceOrder(variant) {
            let session = try #require(try state.activePracticeCheckSession(attemptID: attempt.id, library: library))
            let command: SessionCommand
            switch competency {
            case "initialResponse":
                #expect(PracticeCheckSources.authoredChoice(session, competency: competency, library: library)?.id == "choice.tornado.warning")
                command = .init(kind: "choose", target: "choice.tornado.warning", value: "go-to-shelter")
            case "communication": command = .init(kind: "contact", target: try #require(household.contacts.first { $0.isComplete }).id)
            case "continuity": command = .init(kind: "allocatePower", target: "eq-oxygen", value: "bk-station")
            default:
                #expect(PracticeCheckSources.authoredChoice(session, competency: competency, library: library)?.id == "choice.freeze-power-loss.keep-warm")
                command = .init(kind: "choose", target: "choice.freeze-power-loss.keep-warm", value: "layer-up")
            }
            let observation = try state.submitPracticeAction(attemptID: attempt.id, competencyID: competency,
                commit: SessionCommit(id: "answer-\(competency)", actor: "user", baseRevision: session.revision, commands: [command]), library: library)
            credits[competency] = observation.credit
            _ = try state.revealPracticeFeedback(attemptID: attempt.id, actionID: observation.actionID)
        }
        #expect(credits["initialResponse"] == 1)
        #expect(credits["communication"] == 1)
        #expect(credits["continuity"] == 1)
        #expect(credits["adaptation"] == 1)
        attempt = try #require(state.practiceAttempts.last)
        #expect(attempt.observations?.count == 4)
        _ = try state.validatePhasedPractice(attempt, library: library)
    }

    @Test func unsafeTornadoAndIndoorHeatingChoicesEarnZero() throws {
        var (state, attempt) = try begin(SampleHouseholds.oak, home: SampleHomes.ranch, variant: PracticeCheckSources.secondSetVariant)
        for competency in IntegratedAIState.practiceOrder(PracticeCheckSources.secondSetVariant) {
            let session = try #require(try state.activePracticeCheckSession(attemptID: attempt.id, library: library))
            let command = switch competency {
            case "initialResponse": SessionCommand(kind: "choose", target: "choice.tornado.warning", value: "go-outside")
            case "adaptation": SessionCommand(kind: "choose", target: "choice.freeze-power-loss.keep-warm", value: "generator-indoors")
            default: SessionCommand(kind: "wait")
            }
            let observation = try state.submitPracticeAction(attemptID: attempt.id, competencyID: competency,
                commit: SessionCommit(id: "a-\(competency)", actor: "user", baseRevision: session.revision, commands: [command]), library: library)
            if ["initialResponse", "adaptation"].contains(competency) { #expect(observation.credit == 0) }
            _ = try state.revealPracticeFeedback(attemptID: attempt.id, actionID: observation.actionID)
        }
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
