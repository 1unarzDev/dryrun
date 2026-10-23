import Foundation
import Testing
@testable import DryRunCore

@Suite("Family by hazard committed rehearsal coverage")
struct ScenarioFamilyMatrixTests {
    @Test func everySelectableFamilyHasTwoCommittedGatesAcrossVariedHomes() throws {
        #expect(SampleHouseholds.all.map(\.id) == ["hh-oak", "hh-lake", "hh-pine"])
        for family in SampleHouseholds.all {
            for scenario in SimFixtures.library.scenarios {
                for home in SampleHomes.all {
                    var input = SimFixtures.input(family, scenario.id, home: home)
                    // Family needs remain intact; map origins to this layout explicitly rather
                    // than silently depending on ranch-specific bedroom IDs.
                    var spatial = input.effectiveSpatialOptions
                    for (index, person) in family.people.enumerated() {
                        spatial.startingSpaceIDs[person.id] = home.spaces[index % home.spaces.count].id
                    }
                    input.spatialOptions = spatial
                    var session = try SimulationSession.initialize(id: "matrix-\(family.id)-\(scenario.id)-\(home.id)", initial: input, library: SimFixtures.library)
                    let gates = scenario.choicePoints.filter {
                        Applicability.holds($0.when, household: family, home: home, variants: input.variants)
                    }
                    #expect(gates.count >= 2)
                    for gate in gates.prefix(2) {
                        let proposal = SessionCommit(id: gate.id, actor: "user", baseRevision: session.revision,
                            commands: [.init(kind: "choose", target: gate.id, value: gate.defaultOptionID)])
                        let before = try session.query(library: SimFixtures.library)
                        let preview = try session.preview(proposal, library: SimFixtures.library)
                        #expect(try session.query(library: SimFixtures.library) == before)
                        let committed = try session.commit(proposal, library: SimFixtures.library)
                        #expect(committed == preview)
                        #expect(committed.contextDigest != before.contextDigest)
                        #expect(committed.events.contains { $0.id == "evt.\(gate.id)" })
                        #expect(throws: SessionError.duplicate) { try session.commit(proposal, library: SimFixtures.library) }
                    }
                    let restored = try DryRunJSON.decoder().decode(SimulationSession.self, from: DryRunJSON.encoder().encode(session))
                    #expect(try restored.query(library: SimFixtures.library) == session.query(library: SimFixtures.library))
                    #expect(session.initial.household == family)
                }
            }
        }
    }

    @Test func regionalFloodAndHouseholdLeakChoicesCannotCrossVariants() throws {
        for leak in [false, true] {
            var input = SimFixtures.input(SampleHouseholds.oak, "flash-flood")
            var spatial = input.effectiveSpatialOptions
            spatial.floodIsHouseholdLeak = leak
            input.spatialOptions = spatial
            var session = try SimulationSession.initialize(id: "variant", initial: input, library: SimFixtures.library)
            let before = try session.query(library: SimFixtures.library)
            let choice = leak ? "choice.flash-flood.early" : "choice.household-leak.help"
            let option = leak ? "leave-early" : "get-help"
            #expect(throws: SessionError.invalidCommand) {
                try session.commit(.init(id: "wrong-variant", actor: "user", baseRevision: 0,
                    commands: [.init(kind: "choose", target: choice, value: option)]), library: SimFixtures.library)
            }
            #expect(try session.query(library: SimFixtures.library) == before)
        }
    }

    @Test func shelterRecommendationRequiresAReachableRoomForEveryOccupant() throws {
        let family = SampleHouseholds.oak
        let accessible = try SimFixtures.run(family, "tornado")
        var blockedHome = SampleHomes.ranch
        blockedHome.portals.removeAll { $0.id == "pt-closet-hall" }
        let blocked = try SimFixtures.run(family, "tornado", home: blockedHome)
        func recommended(_ result: RehearsalResult) -> Bool {
            result.decisions.first { $0.id == "choice.tornado.warning" }?.options.first { $0.id == "go-to-shelter" }?.isRecommended == true
        }
        #expect(recommended(accessible))
        #expect(!recommended(blocked))
        #expect(blocked.routes.allSatisfy { $0.primary == nil })
        // The room itself remains a recorded candidate. The missing connection causes
        // the changed decision; deleting the candidate would conceal the access gap.
        #expect(ShelterSuitability.confirmedRoom(in: blockedHome) != nil)
    }

    @Test func waterAllocationChangesLaterCommittedQuantityWithoutChangingTheInitialSnapshot() throws {
        var input = SimFixtures.input(SampleHouseholds.oak, "water-outage")
        input.household.people = Array(input.household.people.prefix(1))
        input.household.supplies.storedWaterGallons = .confirmed(1)
        var source = try SimulationSession.initialize(id: "water-pair", initial: input, library: SimFixtures.library)
        try source.commit(.init(id: "outage", actor: "director", baseRevision: 0,
            commands: [.init(kind: "schedule", target: "evt.water-outage.well-pump-failure", minute: 0), .init(kind: "advance", minute: 0)]), library: SimFixtures.library)
        func projected(_ policy: String) throws -> SessionReceipt {
            var copy = source
            try copy.commit(.init(id: "allocate", actor: "user", baseRevision: 1,
                commands: [.init(kind: "useStoredWater", value: policy)]), library: SimFixtures.library)
            return try copy.commit(.init(id: "later", actor: "director", baseRevision: 2,
                commands: [.init(kind: "advance", minute: 720)]), library: SimFixtures.library)
        }
        let essential = try projected("essential"), all = try projected("all")
        #expect(essential.snapshot.resources["res.water.stored"]?.amount == 0.5)
        #expect(all.snapshot.resources["res.water.stored"]?.amount == 0)
        #expect(try source.query(library: SimFixtures.library).snapshot.resources["res.water.stored"]?.amount == 1)
    }
}
