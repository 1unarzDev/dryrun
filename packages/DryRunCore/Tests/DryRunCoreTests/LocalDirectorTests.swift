import Foundation
import Testing
@testable import DryRunCore

@Suite("Offline local director over incremental sessions") struct LocalDirectorTests {
    /// Drives a whole exercise: the local director proposes, the "family" answers each due choice with `answer`.
    func drive(_ household: HouseholdProfile, _ scenarioID: String, home: HomeModel = SampleHomes.ranch,
               answer: (ChoicePoint) -> String = { $0.defaultOptionID }) throws -> (SimulationSession, SessionReceipt, [String: String], Int) {
        let library = SimFixtures.library
        var session = try SimulationSession.initialize(id: "local-\(scenarioID)", initial: SimFixtures.input(household, scenarioID, home: home), library: library)
        var receipt = try session.query(library: library)
        var answers: [String: String] = [:], decisions = 0
        for _ in 0..<64 {
            if receipt.finished { break }
            if receipt.directorState?.awaitingUserAction == true {
                decisions += 1
                if let choice = LocalDirector.dueChoice(session: session, receipt: receipt, library: library) {
                    #expect(answers[choice.id] == nil, "a choice is offered once")
                    let option = answer(choice)
                    answers[choice.id] = option
                    receipt = try session.commit(.init(id: "user-\(session.revision)", actor: "user", baseRevision: session.revision,
                                                       commands: [.init(kind: "choose", target: choice.id, value: option)]), library: library)
                } else {
                    Issue.record("the local director paused with no authored choice due")
                    break
                }
                continue
            }
            let next = try #require(LocalDirector.nextCommit(session: session, receipt: receipt, library: library))
            #expect(next.actor == "director")
            receipt = try session.commit(next, library: library)
        }
        return (session, receipt, answers, decisions)
    }

    @Test(arguments: SimFixtures.scenarioIDs) func everyScenarioFinishesAndOffersEachApplicableChoiceOnce(_ scenarioID: String) throws {
        let (session, receipt, answers, _) = try drive(SampleHouseholds.oak, scenarioID)
        #expect(receipt.finished)
        let scenario = SimFixtures.library.scenario(scenarioID)!
        let applicable = scenario.choicePoints.filter { LocalDirector.applies($0.when, session) }.map(\.id)
        #expect(Set(answers.keys) == Set(applicable))
        // Replay from the committed log alone reproduces the final receipt; no director is consulted.
        let decoded = try DryRunJSON.decoder().decode(SimulationSession.self, from: DryRunJSON.encoder().encode(session))
        #expect(try decoded.query(library: SimFixtures.library) == receipt)
    }

    @Test(arguments: SimFixtures.scenarioIDs) func localDirectorFiresTheSameAuthoredEventsAsTheAuthoredRun(_ scenarioID: String) throws {
        let (_, receipt, answers, _) = try drive(SampleHouseholds.oak, scenarioID)
        let authored = try SimFixtures.run(SampleHouseholds.oak, scenarioID, choices: answers)
        let authoredIDs = Set(authored.events.map(\.id).filter { $0.hasPrefix("evt.") })
        let localIDs = Set(receipt.events.map(\.id).filter { $0.hasPrefix("evt.") })
        #expect(authoredIDs.isSubset(of: localIDs), "missing: \(authoredIDs.subtracting(localIDs).sorted())")
    }

    /// When a decision is shown, every authored event due by the choice's minute has already happened (the alarm
    /// sounds before "the smoke alarm sounds, what is the first move?").
    @Test(arguments: SimFixtures.scenarioIDs) func eventsDueByAChoiceFireBeforeItIsAsked(_ scenarioID: String) throws {
        let library = SimFixtures.library
        let scenario = library.scenario(scenarioID)!
        var session = try SimulationSession.initialize(id: "order-\(scenarioID)", initial: SimFixtures.input(SampleHouseholds.oak, scenarioID), library: library)
        var receipt = try session.query(library: library)
        for _ in 0..<64 where !receipt.finished {
            if receipt.directorState?.awaitingUserAction == true {
                let choice = try #require(LocalDirector.dueChoice(session: session, receipt: receipt, library: library))
                let fired = Set(receipt.events.map(\.id))
                let expected = scenario.events.filter { LocalDirector.applies($0.when, session) && $0.minute <= choice.minute }.map(\.id)
                #expect(Set(expected).isSubset(of: fired), "\(choice.id) asked before \(Set(expected).subtracting(fired).sorted())")
                receipt = try session.commit(.init(id: "u-\(session.revision)", actor: "user", baseRevision: session.revision,
                                                   commands: [.init(kind: "choose", target: choice.id, value: choice.defaultOptionID)]), library: library)
            } else {
                receipt = try session.commit(try #require(LocalDirector.nextCommit(session: session, receipt: receipt, library: library)), library: library)
            }
        }
        #expect(receipt.finished)
    }

    @Test func differentAnswersProduceDifferentCommittedSituations() throws {
        let scenario = SimFixtures.library.scenario("freeze-power-loss")!
        let first = try #require(scenario.choicePoints.first { $0.options.count > 1 })
        let a = try drive(SampleHouseholds.oak, "freeze-power-loss") { $0.id == first.id ? $0.options[0].id : $0.defaultOptionID }
        let b = try drive(SampleHouseholds.oak, "freeze-power-loss") { $0.id == first.id ? $0.options[1].id : $0.defaultOptionID }
        #expect(a.1.contextDigest != b.1.contextDigest)
    }

    @Test func directorWaitsForTheFamilyAndNeverAnswersForIt() throws {
        let library = SimFixtures.library
        var session = try SimulationSession.initialize(id: "wait", initial: SimFixtures.input(SampleHouseholds.oak, "home-fire"), library: library)
        var receipt = try session.query(library: library)
        while receipt.directorState?.awaitingUserAction != true {
            receipt = try session.commit(try #require(LocalDirector.nextCommit(session: session, receipt: receipt, library: library)), library: library)
        }
        #expect(LocalDirector.nextCommit(session: session, receipt: receipt, library: library) == nil)
        #expect(!session.commits.contains { $0.actor == "director" && $0.commands.contains { $0.kind == "choose" } })
        #expect(LocalDirector.dueChoice(session: session, receipt: receipt, library: library) != nil)
    }
}
