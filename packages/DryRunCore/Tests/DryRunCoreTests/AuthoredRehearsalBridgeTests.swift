import Foundation
import Testing
@testable import DryRunCore

@Suite("Native authored playback commits canonical choices")
struct AuthoredRehearsalBridgeTests {
    @Test func allFamiliesAndHazardsPersistOnlyExplicitAnswersAndReceiptSnapshots() throws {
        for household in SampleHouseholds.all {
            for scenario in SimFixtures.library.scenarios {
                let input = SimFixtures.input(household, scenario.id)
                var session = try AuthoredRehearsalBridge.initialize(id: AuthoredRehearsalBridge.sessionPrefix + scenario.id,
                    input: input, library: SimFixtures.library)
                #expect(session.initial.choices.isEmpty)
                #expect(!session.commits.contains { $0.actor == "user" })
                let choices = scenario.choicePoints.filter {
                    Applicability.holds($0.when, household: household, home: input.home, variants: input.variants)
                }.sorted { ($0.minute, $0.id) < ($1.minute, $1.id) }
                for choice in choices {
                    let receipt = try AuthoredRehearsalBridge.choose(choice.defaultOptionID, at: choice.id, in: &session, library: SimFixtures.library)
                    #expect(receipt.snapshot.simMinute == choice.minute)
                    let projection = try AuthoredRehearsalBridge.projection(session, engine: SimFixtures.engine, library: SimFixtures.library)
                    let boundary = try #require(projection.events.firstIndex { $0.id == "evt.\(choice.id)" }) + 1
                    let snapshot = try #require(projection.snapshots.last { $0.revealedEventCount == boundary })
                    #expect(snapshot.spatialState == receipt.snapshot.spatialState)
                    #expect(snapshot.services == receipt.snapshot.services)
                    #expect(snapshot.resources == receipt.snapshot.resources)
                    #expect(projection.input.choices[choice.id] == choice.defaultOptionID)
                    let restored = try DryRunJSON.decoder().decode(SimulationSession.self, from: DryRunJSON.encoder().encode(session))
                    #expect(try restored.query(library: SimFixtures.library) == receipt)
                }
                #expect(session.commits.filter { $0.actor == "user" }.count == choices.count)
                #expect(session.initial == input)
            }
        }
    }

    @Test func outOfOrderDuplicateAndWrongVariantAnswersAreAtomic() throws {
        let input = SimFixtures.input(SampleHouseholds.oak, "home-fire")
        var session = try AuthoredRehearsalBridge.initialize(id: "order", input: input, library: SimFixtures.library)
        let before = try session.query(library: SimFixtures.library)
        #expect(throws: SessionError.invalidCommand) {
            try AuthoredRehearsalBridge.choose("call-from-outside", at: "choice.home-fire.outside", in: &session, library: SimFixtures.library)
        }
        #expect(try session.query(library: SimFixtures.library) == before)
        _ = try AuthoredRehearsalBridge.choose("get-out", at: "choice.home-fire.first-move", in: &session, library: SimFixtures.library)
        let accepted = try session.query(library: SimFixtures.library)
        #expect(throws: SessionError.invalidCommand) {
            try AuthoredRehearsalBridge.choose("get-out", at: "choice.home-fire.first-move", in: &session, library: SimFixtures.library)
        }
        #expect(try session.query(library: SimFixtures.library) == accepted)
        var leak = SimFixtures.input(SampleHouseholds.oak, "flash-flood", variants: ["householdLeak"])
        leak.spatialOptions = .init(floodAffectedSpaceIDs: ["sp-kitchen"], floodIsHouseholdLeak: true)
        var leakSession = try AuthoredRehearsalBridge.initialize(id: "leak", input: leak, library: SimFixtures.library)
        #expect(throws: SessionError.invalidCommand) {
            try AuthoredRehearsalBridge.choose("leave-early", at: "choice.flash-flood.early", in: &leakSession, library: SimFixtures.library)
        }
    }

    @Test func fireReceiptAppearsOnlyAtItsAcceptedChoiceBoundary() throws {
        let input = SimFixtures.input(SampleHouseholds.oak, "home-fire")
        var session = try AuthoredRehearsalBridge.initialize(id: "fire-boundary", input: input, library: SimFixtures.library)
        let receipt = try AuthoredRehearsalBridge.choose("get-out", at: "choice.home-fire.first-move", in: &session, library: SimFixtures.library)
        let result = try AuthoredRehearsalBridge.projection(session, engine: SimFixtures.engine, library: SimFixtures.library)
        var cursor = RehearsalCursor(result: result)
        let boundary = try #require(result.events.firstIndex { $0.id == "evt.choice.home-fire.first-move" })
        while cursor.revealed < boundary { cursor.advance() }
        #expect(cursor.snapshotAtCursor?.spatialState?.occupants?.allSatisfy { $0.exteriorExitPortalID == nil } != false)
        cursor.advance()
        #expect(cursor.snapshotAtCursor?.spatialState == receipt.snapshot.spatialState)
        #expect(receipt.snapshot.spatialState?.occupants?.contains { $0.exteriorExitPortalID != nil } == true)
        #expect(receipt.snapshot.spatialState?.occupants?.allSatisfy { !$0.accountedOutside } == true)
    }
}
