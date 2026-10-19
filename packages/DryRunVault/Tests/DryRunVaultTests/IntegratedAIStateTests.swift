import Foundation
import Testing
import DryRunCore
@testable import DryRunVault
@Suite("Additive integrated AI vault payload") struct IntegratedAIStateTests {
 @Test func legacyPayloadAndVersionedSidecarRoundTrip() throws {
  let date=Date(timeIntervalSince1970:1792368000)
  let legacy=VaultPayload(household:SampleHouseholds.oak,home:SampleHomes.ranch,savedAt:date)
  var json=try JSONSerialization.jsonObject(with:DryRunJSON.encoder().encode(legacy)) as! [String:Any]
  json.removeValue(forKey:"integratedAIState")
  let decoded=try DryRunJSON.decoder().decode(VaultPayload.self,from:JSONSerialization.data(withJSONObject:json))
  #expect(decoded.integratedAIState==nil);#expect(decoded.household?.id==legacy.household?.id)
  var updated=decoded;updated.integratedAIState=try DryRunJSON.encoder().encode(IntegratedAIState())
  let restored=try DryRunJSON.decoder().decode(VaultPayload.self,from:DryRunJSON.encoder().encode(updated))
  #expect(try DryRunJSON.decoder().decode(IntegratedAIState.self,from:restored.integratedAIState!).schemaVersion==1)
  #expect(restored.home==legacy.home);#expect(restored.household==legacy.household)
 }
 @Test func frozenPracticeSituationsAndWrongFirstAnswerSurviveEncryptedSave() async throws {
  struct Recording:Decodable {
   struct Branch:Decodable {var state:IntegratedAIState;enum CodingKeys:String,CodingKey {case state="final"}}
   var branches:[Branch]
  }
  var root=URL(fileURLWithPath:#filePath)
  for _ in 0..<5 {root.deleteLastPathComponent()}
  let recording=try DryRunJSON.decoder().decode(Recording.self,from:Data(contentsOf:root.appendingPathComponent("fixtures/ai/practice-phases.json")))
  let state=try #require(recording.branches.last?.state)
  let encoded=try DryRunJSON.encoder().encode(state)
  var payload=canaryPayload();payload.integratedAIState=encoded
  let fixture=Fixture();defer {try? FileManager.default.removeItem(at:fixture.root)}
  try await fixture.repo.save(payload)
  let loaded=try #require(try await fixture.repo.load())
  #expect(loaded.integratedAIState==encoded)
  let restored=try DryRunJSON.decoder().decode(IntegratedAIState.self,from:#require(loaded.integratedAIState))
  #expect(restored.practiceAttempts[0].phaseSources?.count==4)
  #expect(restored.practiceAttempts[0].observations?[0].credit==0)
  #expect(restored.practiceAttempts[0].observations?.count==4)
  for (_,bytes) in allFileBytes(under:fixture.root) {
   #expect(!contains(bytes,canary));#expect(!contains(bytes,"practice-check-a/1"));#expect(!contains(bytes,"phase-initialResponse"))
  }
 }

}
