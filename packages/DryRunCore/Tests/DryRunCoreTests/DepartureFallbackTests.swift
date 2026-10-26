import Foundation
import Testing
@testable import DryRunCore

@Suite("Completed departure survives provider loss") struct DepartureFallbackTests {
    @Test func fallbackEndsTheActualHomeBoundaryWithoutApplyingPendingEvents()throws {
        let helper=SixHazardExperienceTests()
        for (hazard,action,event) in [
            ("flash-flood","leaveEarly","evt.flash-flood.warning"),
            ("freeze-power-loss","heatedAlternative","evt.freeze-power-loss.grid-loss"),
            ("heat-grid-strain","cooledAlternative","evt.heat-grid-strain.outage")
        ] {
            var session=try helper.session(hazard)
            let originalHousehold=session.initial.household
            // Pending events remain part of the durable log, but must not be
            // applied to this family after departure to an unmodeled destination.
            let profile=try #require(SimFixtures.library.scenario(hazard)?.events.first{$0.id==event || $0.rule==RuleID.setExternal})
            _=try helper.act(&session,[.init(kind:"schedule",target:profile.id,minute:60)],actor:"director")
            let departed=try helper.act(&session,[.init(kind:action,target:"alternative")])
            #expect(departed.experience?.relocated==true)
            let proposal=try session.fallback(library:SimFixtures.library)
            #expect(proposal.commands.map(\.kind)==["finish"])
            #expect(throws:SessionError.persistence){try session.commit(proposal,library:SimFixtures.library,persist:{_ in throw SessionError.persistence})}
            #expect(try session.query(library:SimFixtures.library)==departed)
            let finished=try session.commit(proposal,library:SimFixtures.library)
            #expect(finished.finished)
            #expect(finished.snapshot==departed.snapshot)
            #expect(finished.experience==departed.experience)
            #expect(finished.pending==departed.pending)
            #expect(finished.routes==departed.routes)
            #expect(session.initial.household==originalHousehold)
            let restored=try DryRunJSON.decoder().decode(SimulationSession.self,from:DryRunJSON.encoder().encode(session))
            #expect(try restored.query(library:SimFixtures.library)==finished)
            #expect(throws:SessionError.finished){try restored.fallback(library:SimFixtures.library)}
        }
    }
    @Test func unfinishedFloodStillOffersTheSameHomeDecision()throws {
        let session=try SixHazardExperienceTests().session("flash-flood")
        let before=try session.query(library:SimFixtures.library)
        let proposal=try session.fallback(library:SimFixtures.library)
        #expect(!proposal.commands.contains{$0.kind=="finish"})
        #expect(try session.query(library:SimFixtures.library)==before)
    }
    @Test func localFireRequiresSeparateRosterAndTornadoRequiresEveryArrival()throws {
        let helper=SixHazardExperienceTests()
        for hazard in ["home-fire","tornado"] {
            var session=try helper.session(hazard)
            for person in session.initial.household.people {
                let current=try session.query(library:SimFixtures.library)
                let command=try #require(current.experience?.feasibleCommands?.first{$0.target==person.id && $0.kind==(hazard=="home-fire" ? "escape":"reachShelter")})
                _=try helper.act(&session,[command])
                if person.id != session.initial.household.people.last!.id {
                    #expect(try session.fallback(library:SimFixtures.library).commands.last?.kind != "finish")
                }
            }
            if hazard=="home-fire" {
                #expect(try session.fallback(library:SimFixtures.library).commands.last?.kind != "finish")
                for person in session.initial.household.people {_=try helper.act(&session,[.init(kind:"accountOutside",target:person.id)])}
            }
            let before=try session.query(library:SimFixtures.library)
            let proposal=try session.fallback(library:SimFixtures.library)
            #expect(proposal.commands.map(\.kind)==["finish"])
            let finished=try session.commit(proposal,library:SimFixtures.library)
            #expect(finished.finished);#expect(finished.snapshot==before.snapshot);#expect(finished.experience==before.experience)
        }
    }
}
