import Foundation
import DryRunCore

/// What the app keeps privately. Everything here lives only inside the encrypted vault.
struct PrivateSnapshot: Sendable, Equatable {
    var household: HouseholdProfile
    var home: HomeModel
    var savedPlan: PlanDocument?
}

enum PrivateLoadResult: Sendable, Equatable {
    case empty
    case loaded(PrivateSnapshot)
    /// Key unavailable while the device is locked. Distinct from corruption.
    case locked
    /// Corrupt/tampered/unmigratable data or missing key with existing ciphertext. The original is preserved.
    case needsRecovery(String)
}

/// Narrow app-facing interface over the vault so views never touch crypto or files directly.
protocol PrivateDataStore: Sendable {
    func load() async -> PrivateLoadResult
    func save(_ snapshot: PrivateSnapshot) async throws
    func deleteAll() async throws
}

/// Used for SwiftUI previews and UI tests only. Holds nothing on disk.
actor InMemoryPrivateDataStore: PrivateDataStore {
    private var snapshot: PrivateSnapshot?
    init(snapshot: PrivateSnapshot? = nil) { self.snapshot = snapshot }
    func load() async -> PrivateLoadResult { snapshot.map { .loaded($0) } ?? .empty }
    func save(_ snapshot: PrivateSnapshot) async throws { self.snapshot = snapshot }
    func deleteAll() async throws { snapshot = nil }
}
