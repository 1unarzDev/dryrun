import Foundation
import Testing
@testable import DryRunCore

/// Replays the Gemini-directed turn committed on the iPhone (fictional apartment complex, home fire):
/// local alarm turn → family answers "get out" → director advanceIncident(fire-origin@1), advance(2), requestDecision.
@Suite("Replay of the phone's Gemini-directed fire turn") struct GeminiTurnReplayTests {
    @Test func eachRouteUpdateIsReportedOncePerPerson() throws {
        let library = SimFixtures.library
        var session = try SimulationSession.initialize(id: "phone-replay", initial: SimFixtures.input(SampleHouseholds.oak, "home-fire", home: SampleHomes.apartmentComplex), library: library)
        var receipt = try session.query(library: library)
        receipt = try session.commit(try #require(LocalDirector.nextCommit(session: session, receipt: receipt, library: library)), library: library)
        receipt = try session.commit(.init(id: "user-get-out", actor: "user", baseRevision: session.revision,
                                           commands: [.init(kind: "choose", target: "choice.home-fire.first-move", value: "get-out")]), library: library)
        let before = receipt.events.count
        receipt = try session.commit(.init(id: "gemini-turn", actor: "director", baseRevision: session.revision, commands: [
            .init(kind: "advanceIncident", target: "evt.home-fire.fire-origin", minute: 1, hazard: .homeFire),
            .init(kind: "advance", minute: 2), .init(kind: "requestDecision")]), library: library)
        let fresh = receipt.events.dropFirst(before)
        let keys = fresh.map { "\($0.titleKey)|\($0.templateValues.sorted { $0.key < $1.key })" }
        #expect(Set(keys).count == keys.count, "duplicate event text in one turn")
    }
}
