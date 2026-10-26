import XCTest
import DryRunCore
import DryRunVault
@testable import DryRun

@MainActor
final class VaultSidecarRecoveryTests: XCTestCase {
    func testNewerPracticeStateRequiresRecoveryWithoutChangingEncryptedFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = VaultLocations(root: root)
        let repository = HouseholdVaultRepository(locations: locations, keyStore: InMemoryVaultKeyStore(),
                                                  protection: RecordingFileProtection())
        var future = IntegratedAIState()
        future.schemaVersion += 1
        let bytes = try DryRunJSON.encoder().encode(future)
        try await repository.save(VaultPayload(household: SampleHouseholds.oak, home: SampleHomes.ranch,
                                               integratedAIState: bytes))
        let original = try Data(contentsOf: locations.vaultFile)
        let store = VaultPrivateDataStore(repository: repository)
        guard case .needsRecovery = await store.load() else {
            XCTFail("Newer practice data must not become an editable empty state")
            return
        }
        XCTAssertTrue(try Data(contentsOf: locations.vaultFile) == original)
        let retained = try await repository.load()
        XCTAssertTrue(retained?.integratedAIState == bytes)
    }
}
