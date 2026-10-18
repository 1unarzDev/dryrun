import Foundation
import DryRunCore
import DryRunVault

/// Bridges the app's narrow `PrivateDataStore` onto the encrypted `HouseholdVaultRepository`.
/// Lead-owned glue; crypto, key handling, and file protection live in DryRunVault (Agent C).
struct VaultPrivateDataStore: PrivateDataStore {
    let repository: HouseholdVaultRepository

    static func makeDefault() -> VaultPrivateDataStore {
        #if DEBUG && targetEnvironment(simulator)
        // Explicit simulator-only UI testing uses the real encrypted repository/Keychain bridge in a
        // unique namespace. It never reads, clears, or replaces the household's normal vault.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uiTestingVaultID"), index + 1 < arguments.count,
           let identifier = UUID(uuidString: arguments[index + 1]) {
            let testRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DryRunUITests", isDirectory: true)
                .appendingPathComponent(identifier.uuidString, isDirectory: true)
            return VaultPrivateDataStore(repository: HouseholdVaultRepository(locations: VaultLocations(root: testRoot),
                keyStore: KeychainVaultKeyStore(service: "org.dryrun.uitest.\(identifier.uuidString)"),
                protection: VaultFileProtection()))
        }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DryRun", isDirectory: true)
        let repo = HouseholdVaultRepository(locations: VaultLocations(root: support),
                                            keyStore: KeychainVaultKeyStore(),
                                            protection: VaultFileProtection())
        return VaultPrivateDataStore(repository: repo)
    }

    func load() async -> PrivateLoadResult {
        do {
            guard let payload = try await repository.load() else { return .empty }
            guard let household = payload.household, payload.hasValidHouseholdLayoutState else {
                // A vault file existed but is incomplete: never treat as a fresh start that the next save would overwrite.
                return .needsRecovery("The saved data is incomplete. It was kept unchanged.")
            }
            let plan = payload.retainedPlans.max { $0.generatedAt < $1.generatedAt }
                .flatMap { try? DryRunJSON.decoder().decode(PlanDocument.self, from: $0.document) }
            return .loaded(PrivateSnapshot(household: household, home: payload.home, savedPlan: plan,
                                           savedPlaces: payload.savedPlaces))
        } catch {
            switch error {
            case .keyUnavailableWhileLocked:
                return .locked
            case .keyLost:
                return .needsRecovery("The encryption key for this data is not on this device.")
            case .corrupted(_, let reason):
                return .needsRecovery("The stored file failed its integrity check (\(reason)). The original file was kept.")
            case .migrationFailed(let from, let reason):
                return .needsRecovery("Could not upgrade data from version \(from): \(reason). The original was kept.")
            case .unsupportedNewerVersion(let v):
                return .needsRecovery("The data was saved by a newer version of Dry Run (format \(v)). Update the app.")
            default:
                return .needsRecovery(String(describing: error))
            }
        }
    }

    func save(_ snapshot: PrivateSnapshot) async throws {
        var plans: [RetainedPlan] = []
        if let plan = snapshot.savedPlan {
            plans.append(RetainedPlan(id: "plan-\(plan.locale)", revisionKey: plan.revisionKey, locale: plan.locale,
                                      scenarioIDs: plan.scenarioIDs, generatedAt: plan.generatedAt,
                                      document: try DryRunJSON.encoder().encode(plan)))
        }
        try await repository.save(VaultPayload(household: snapshot.household, home: snapshot.home,
                                               retainedPlans: plans, savedPlaces: snapshot.savedPlaces,
                                               homeGeometryIntentionallyAbsent: snapshot.home == nil))
    }

    func deleteAll() async throws {
        try await repository.deleteAll()
    }
}
