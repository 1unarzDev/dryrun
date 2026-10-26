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
}
