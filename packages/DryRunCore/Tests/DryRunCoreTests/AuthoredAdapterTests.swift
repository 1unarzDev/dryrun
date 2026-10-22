import Foundation
import Testing
@testable import DryRunCore

@Suite("Authored adapter compatibility") struct AuthoredAdapterTests {
 @Test func preservesLegacyResultsOutsideVersionedSpatialArrivalFields()throws {
  // Captured from the pre-adapter execute loop at 69c15e5, including every encoded result field.
  let hashes=try DryRunJSON.decoder().decode([String:String].self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/authored-adapter-reference.json")))
  for (name,household) in [("oak",SampleHouseholds.oak),("lake",SampleHouseholds.lake)] {
   for scenarioID in SimFixtures.scenarioIDs {
    let scenario=SimFixtures.library.scenario(scenarioID)!
    for alternate in [false,true] {
     var input=SimFixtures.input(household,scenarioID)
     // This choice was added after the historical capture and requires the new
     // cooling-followup variant. Preserve the exact old input, including old unused choices.
     if alternate {for point in scenario.choicePoints where point.id != "choice.heat-grid-strain.powered-evening" {input.choices[point.id]=point.options.last?.id}}
     var actual=try SimFixtures.engine.run(input)
     // egress-portal-graph/3 changed only exclusions no fixture home exercises (blocked doorway, outside answer on an
     // interior opening); the historical capture recorded /2. Project the version label back, nothing else.
     #expect(actual.routes.allSatisfy { $0.algorithmVersion == RouteResult.algorithmVersion })
     for i in actual.routes.indices { actual.routes[i].algorithmVersion = "egress-portal-graph/2" }
     for i in actual.snapshots.indices {
      for j in (actual.snapshots[i].spatialState?.routes ?? []).indices { actual.snapshots[i].spatialState?.routes[j].algorithmVersion = "egress-portal-graph/2" }
     }
     let key=name+"/"+scenarioID+(alternate ? "/alternate" : "/default")
     let spatial = [.homeFire, .tornado, .flashFlood].contains(scenario.hazard)
     if !spatial {
      #expect(StableDigest.of(try DryRunJSON.encoder().encode(actual))==hashes[key], "Unchanged historical contract key: \(key)")
     } else {
      // The historical fixture stays unchanged. Occupancy is a deliberately added
      // optional field; require the rest of each old result to remain byte-identical,
      // except the explicitly versioned successful tornado arrival route.
      var historicalProjection = actual
      var previousStage: String?
      for index in historicalProjection.snapshots.indices {
       historicalProjection.snapshots[index].spatialState?.occupants = nil
       if let stage = historicalProjection.snapshots[index].spatialState?.stageID {
        if stage.hasPrefix("evt.choice."), let previousStage {
         // The new scene revision identifies the actual arrival/accounting choice.
         historicalProjection.snapshots[index].spatialState?.stageID = previousStage
        } else { previousStage = stage }
       }
      }
      for index in historicalProjection.decisions.indices where historicalProjection.decisions[index].id == "choice.home-fire.outside" {
       for optionIndex in historicalProjection.decisions[index].options.indices where historicalProjection.decisions[index].options[optionIndex].id == "call-from-outside" {
        // Legacy advice did not require an exterior occupant; new advice does.
        historicalProjection.decisions[index].options[optionIndex].isRecommended = true
       }
      }
      if scenario.hazard == .tornado && !alternate {
       let shelter = try #require(ShelterSuitability.confirmedRoom(in: SimFixtures.home)?.id)
       #expect(actual.routes.allSatisfy { $0.request.purpose == .interiorShelter && $0.request.destinationSpaceID == shelter })
       for person in household.people {
        if let state = actual.snapshots.last?.spatialState?.occupants?.first(where: { $0.personID == person.id }), state.shelteredSpaceID != nil {
         #expect(state.shelteredSpaceID == shelter && state.currentSpaceID == shelter)
         #expect(actual.routes.first { $0.request.personID == person.id }?.request.startSpaceID == shelter)
        }
       }
       #expect(actual.input.household == household)
       #expect(actual.input.home == SimFixtures.home)
      } else {
       #expect(StableDigest.of(try DryRunJSON.encoder().encode(historicalProjection))==hashes[key], "Projected historical contract key: \(key)")
      }
      #expect(actual.snapshots.compactMap(\.spatialState).allSatisfy { Set(($0.occupants ?? []).map(\.personID)) == Set(household.people.map(\.id)) })
     }
    }
   }
  }
 }
}
