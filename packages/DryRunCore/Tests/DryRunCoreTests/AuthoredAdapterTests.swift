import Foundation
import Testing
@testable import DryRunCore

@Suite("Authored adapter compatibility") struct AuthoredAdapterTests {
 @Test func preservesTwentyFourLegacyRuns()throws {
  // Captured from the pre-adapter execute loop at 69c15e5, including every encoded result field.
  let hashes=try DryRunJSON.decoder().decode([String:String].self,from:Data(contentsOf:SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/authored-adapter-reference.json")))
  for (name,household) in [("oak",SampleHouseholds.oak),("lake",SampleHouseholds.lake)] {
   for scenarioID in SimFixtures.scenarioIDs {
    let scenario=SimFixtures.library.scenario(scenarioID)!
    for alternate in [false,true] {
     var input=SimFixtures.input(household,scenarioID)
     if alternate {for point in scenario.choicePoints {input.choices[point.id]=point.options.last?.id}}
     let actual=try SimFixtures.engine.run(input)
     let key=name+"/"+scenarioID+(alternate ? "/alternate" : "/default")
     #expect(StableDigest.of(try DryRunJSON.encoder().encode(actual))==hashes[key])
    }
   }
  }
 }
}
