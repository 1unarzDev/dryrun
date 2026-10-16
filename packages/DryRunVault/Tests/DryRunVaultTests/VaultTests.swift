import DryRunCore
@testable import DryRunVault
import Foundation
import Testing

let canary = "CANARY-7f3a-PRIVATE-HOUSEHOLD-ALIAS"

func makeTempRoot() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dryrun-vault-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func canaryPayload() -> VaultPayload {
    var hh = SampleHouseholds.oak
    hh.people[0].alias = canary
    hh.privateLocation = PrivateLocation(addressLine: "\(canary) 123 Fictional Rd", latitude: 32.2, longitude: -98.2)
    return VaultPayload(household: hh)
}

func allFileBytes(under root: URL) -> [(URL, Data)] {
    guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
    var out: [(URL, Data)] = []
    for case let url as URL in e {
        if let d = FileManager.default.contents(atPath: url.path), !d.isEmpty { out.append((url, d)) }
    }
    return out
}

func contains(_ data: Data, _ needle: String) -> Bool {
    data.range(of: Data(needle.utf8)) != nil
}

struct Fixture {
    let root = makeTempRoot()
    let keys = InMemoryVaultKeyStore()
    let protection = RecordingFileProtection()
    var repo: HouseholdVaultRepository {
        HouseholdVaultRepository(locations: VaultLocations(root: root), keyStore: keys, protection: protection)
    }
}

@Suite("Encrypted household vault")
struct VaultTests {
    @Test func schemaVersionOnePayloadWithoutSavedPlacesStillLoads() throws {
        let legacy = Data("""
        {"schemaVersion":1,"household":null,"home":null,"retainedPlans":[],"rehearsalResults":[],"savedAt":"2026-10-09T00:00:00Z"}
        """.utf8)
        let payload = try DryRunJSON.decoder().decode(VaultPayload.self, from: legacy)
        #expect(payload.savedPlaces.isEmpty)
        #expect(payload.schemaVersion == 1)
    }

    @Test func roundTripAndNoPlaintextOnDisk() async throws {
        let f = Fixture()
        let repo = f.repo
        try await repo.save(canaryPayload())
        let loaded = try await repo.load()
        #expect(loaded?.household?.people[0].alias == canary)
        let files = allFileBytes(under: f.root)
        #expect(!files.isEmpty)
        for (url, data) in files {
            #expect(!contains(data, canary), "plaintext canary found in \(url.lastPathComponent)")
            #expect(!contains(data, "Fictional Rd"))
        }
        // No leftover temp files after atomic replace.
        #expect(files.allSatisfy { !$0.0.lastPathComponent.hasSuffix(".tmp") })
    }

    @Test func finalFileIsProtectedAfterAtomicReplace() async throws {
        let f = Fixture()
        try await f.repo.save(canaryPayload())
        try await f.repo.save(canaryPayload()) // second save replaces the inode
        #expect(try f.protection.isProtected(VaultLocations(root: f.root).vaultFile))
    }

    @Test func eachSaveUsesFreshNonce() async throws {
        let f = Fixture()
        let url = VaultLocations(root: f.root).vaultFile
        let payload = canaryPayload()
        try await f.repo.save(payload)
        let a = try Data(contentsOf: url)
        try await f.repo.save(payload)
        let b = try Data(contentsOf: url)
        #expect(a != b)
    }

    @Test func tamperedCiphertextFailsWithoutDestroyingVault() async throws {
        let f = Fixture()
        let url = VaultLocations(root: f.root).vaultFile
        try await f.repo.save(canaryPayload())
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count - 5] ^= 0xFF
        try bytes.write(to: url)
        do {
            _ = try await f.repo.load()
            Issue.record("tampered vault loaded")
        } catch {
            guard case .corrupted(let recovery?, _) = error else { Issue.record("wrong error \(error)"); return }
            #expect(FileManager.default.fileExists(atPath: recovery.path))
            #expect(try Data(contentsOf: recovery) == bytes)
        }
        // Original still present (not reset to empty).
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func tamperedHeaderMetadataFailsAuthentication() async throws {
        let f = Fixture()
        let url = VaultLocations(root: f.root).vaultFile
        try await f.repo.save(canaryPayload())
        var bytes = try Data(contentsOf: url)
        let s = String(decoding: bytes, as: UTF8.self)
        // Change the authenticated header's createdAt year without changing its length.
        guard let r = s.range(of: "\"createdAt\" : \"20") else { Issue.record("header not found"); return }
        let offset = s.utf8.distance(from: s.startIndex, to: r.upperBound)
        bytes[offset] = UInt8(ascii: "9")
        try bytes.write(to: url)
        await #expect(throws: VaultError.self) { _ = try await f.repo.load() }
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func lockedKeyIsNotCorruption() async throws {
        let f = Fixture()
        try await f.repo.save(canaryPayload())
        f.keys.setLocked(true)
        await #expect(throws: VaultError.keyUnavailableWhileLocked) { _ = try await f.repo.load() }
        await #expect(throws: VaultError.keyUnavailableWhileLocked) { try await f.repo.save(VaultPayload()) }
        // No recovery copies were made: locked is not corruption.
        #expect(!FileManager.default.fileExists(atPath: VaultLocations(root: f.root).recoveryDir.path))
        f.keys.setLocked(false)
        #expect(try await f.repo.load()?.household?.people[0].alias == canary)
    }

    @Test func keyLossIsNotSilentEmptyOnboarding() async throws {
        let f = Fixture()
        let url = VaultLocations(root: f.root).vaultFile
        try await f.repo.save(canaryPayload())
        let before = try Data(contentsOf: url)
        try f.keys.deleteKey()
        await #expect(throws: VaultError.keyLost(preservedVault: url)) { _ = try await f.repo.load() }
        // Saving must not mint a new key and overwrite the orphaned vault.
        await #expect(throws: VaultError.keyLost(preservedVault: url)) { try await f.repo.save(VaultPayload()) }
        #expect(try Data(contentsOf: url) == before)
        #expect(f.keys.storedKey == nil)
    }

    @Test func firstLaunchReturnsNil() async throws {
        let f = Fixture()
        #expect(try await f.repo.load() == nil)
    }

    @Test func failedAtomicSavePreservesPriorData() async throws {
        let f = Fixture()
        try await f.repo.save(canaryPayload())
        f.protection.failNextProtect()
        var changed = canaryPayload()
        changed.household?.displayName = "changed"
        await #expect(throws: VaultError.self) { try await f.repo.save(changed) }
        let loaded = try await f.repo.load()
        #expect(loaded?.household?.displayName == "Oak household (fictional)")
        let leftovers = allFileBytes(under: f.root).filter { $0.0.lastPathComponent.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test func failedMigrationPreservesData() async throws {
        let f = Fixture()
        try await f.repo.save(canaryPayload())
        let url = VaultLocations(root: f.root).vaultFile
        let before = try Data(contentsOf: url)
        struct Boom: Error {}
        let v2 = HouseholdVaultRepository(locations: VaultLocations(root: f.root), keyStore: f.keys, protection: f.protection,
                                          migrations: [1: { _ in throw Boom() }], currentSchemaVersion: 2)
        await #expect(throws: VaultError.self) { _ = try await v2.load() }
        #expect(try Data(contentsOf: url) == before)
        // The old app version can still read it.
        #expect(try await f.repo.load()?.household?.id == "hh-oak")
    }

    @Test func successfulMigrationRuns() async throws {
        let f = Fixture()
        try await f.repo.save(canaryPayload())
        let v2 = HouseholdVaultRepository(locations: VaultLocations(root: f.root), keyStore: f.keys, protection: f.protection,
                                          migrations: [1: { $0 }], currentSchemaVersion: 2)
        #expect(try await v2.load()?.household?.id == "hh-oak")
    }

    @Test func newerVaultIsRefusedNotOverwritten() async throws {
        let f = Fixture()
        let v2 = HouseholdVaultRepository(locations: VaultLocations(root: f.root), keyStore: f.keys, protection: f.protection,
                                          currentSchemaVersion: 2)
        try await v2.save(canaryPayload())
        await #expect(throws: VaultError.unsupportedNewerVersion(2)) { _ = try await f.repo.load() }
    }

    @Test func exportIsOnlyPlaintextAndCleanupRemovesIt() async throws {
        let f = Fixture()
        try await f.repo.save(canaryPayload())
        let pdf = Data("%PDF-1.7 \(canary)".utf8)
        let exportURL = try await f.repo.makeExportFile(named: "plan.pdf", data: pdf)
        #expect(try f.protection.isProtected(exportURL))
        let plaintextHits = allFileBytes(under: f.root).filter { contains($0.1, canary) }.map(\.0.lastPathComponent)
        #expect(plaintextHits == ["plan.pdf"])
        await f.repo.cleanupExports()
        #expect(!FileManager.default.fileExists(atPath: exportURL.path))
        #expect(allFileBytes(under: f.root).allSatisfy { !contains($0.1, canary) })
    }

    @Test func derivedCacheInvalidatesOnRevisionChange() async throws {
        let f = Fixture()
        let k1 = RevisionKey(householdID: "hh-oak", householdRevision: 1, homeID: "home-sample-ranch", homeRevision: 1,
                             contentVersion: "2026.10.0", algorithmVersion: "egress-portal-graph/1")
        var k2 = k1; k2.homeRevision = 2
        try await f.repo.storeDerived(Data("route \(canary)".utf8), name: "route-fire", revision: k1)
        #expect(try await f.repo.loadDerived(name: "route-fire", revision: k1) != nil)
        #expect(try await f.repo.loadDerived(name: "route-fire", revision: k2) == nil)
        for (_, d) in allFileBytes(under: f.root) { #expect(!contains(d, canary)) }
    }

    @Test func pruneStaleDropsResultsForOldRevisions() {
        let k1 = RevisionKey(householdID: "h", householdRevision: 1, homeID: "m", homeRevision: 1, contentVersion: "c", algorithmVersion: "a")
        var k2 = k1; k2.householdRevision = 2
        var p = VaultPayload(rehearsalResults: [CachedRehearsal(revisionKey: k1, scenarioID: "home-fire", result: Data())])
        p.retainedPlans = [RetainedPlan(id: "p", revisionKey: k1, locale: "en", scenarioIDs: [], generatedAt: Date(), document: Data())]
        p.pruneStale(current: k2)
        #expect(p.rehearsalResults.isEmpty && p.retainedPlans.isEmpty)
    }

    @Test func deleteAllPurgesPrivateButKeepsPublic() async throws {
        let f = Fixture()
        let loc = VaultLocations(root: f.root)
        let k = RevisionKey(householdID: "h", householdRevision: 1, homeID: "m", homeRevision: 1, contentVersion: "c", algorithmVersion: "a")
        try await f.repo.save(canaryPayload())
        try await f.repo.storeDerived(Data("x".utf8), name: "d", revision: k)
        _ = try await f.repo.makeExportFile(named: "plan.pdf", data: Data("pdf".utf8))
        try FileManager.default.createDirectory(at: loc.recoveryDir, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: loc.recoveryDir.appendingPathComponent("r.vault"))
        try FileManager.default.createDirectory(at: loc.publicCache, withIntermediateDirectories: true)
        let publicFile = loc.publicCache.appendingPathComponent("pack-tx-statewide.json")
        try Data("{}".utf8).write(to: publicFile)

        try await f.repo.deleteAll()

        for url in [loc.vaultFile, loc.derivedDir, loc.exportsDir, loc.recoveryDir] {
            #expect(!FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) survived")
        }
        #expect(f.keys.storedKey == nil)
        #expect(FileManager.default.fileExists(atPath: publicFile.path))
        // After delete-all, a fresh start is legitimate.
        #expect(try await f.repo.load() == nil)
    }
}

@Suite("Vault review fixes (docs/lanes/review-privacy.md)")
struct VaultReviewFixTests {
    @Test func unreadableFileWithKeyIsNotLocked() async throws {
        guard getuid() != 0 else { return } // root ignores permissions
        let f = Fixture()
        let url = VaultLocations(root: f.root).vaultFile
        try await f.repo.save(canaryPayload())
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        do {
            _ = try await f.repo.load()
            Issue.record("unreadable vault loaded")
        } catch {
            #expect(error != .keyUnavailableWhileLocked)
            guard case .readFailed = error else { Issue.record("expected readFailed, got \(error)"); return }
        }
    }

    @Test func saveRefusesToOverwriteVaultSealedWithAnotherKey() async throws {
        let f = Fixture()
        let url = VaultLocations(root: f.root).vaultFile
        try await f.repo.save(canaryPayload())
        let before = try Data(contentsOf: url)
        let otherKeys = InMemoryVaultKeyStore(key: VaultKeyMaterial.generate())
        let repoB = HouseholdVaultRepository(locations: VaultLocations(root: f.root), keyStore: otherKeys, protection: f.protection)
        do {
            try await repoB.save(VaultPayload())
            Issue.record("overwrote a vault sealed with another key")
        } catch {
            guard case .keyMismatch(_, _, let copy?) = error else { Issue.record("wrong error \(error)"); return }
            #expect(try Data(contentsOf: copy) == before)
        }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func saveRefusesToOverwriteCorruptVaultUnlessExplicit() async throws {
        let f = Fixture()
        let url = VaultLocations(root: f.root).vaultFile
        try await f.repo.save(canaryPayload())
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count - 3] ^= 0x01
        try bytes.write(to: url)
        await #expect(throws: VaultError.self) { try await f.repo.save(VaultPayload()) }
        #expect(try Data(contentsOf: url) == bytes)
        // Explicit start-over keeps a recovery copy, then replaces.
        try await f.repo.save(VaultPayload(), overwriteUnreadable: true)
        #expect(try await f.repo.load()?.household == nil)
        let recovery = try FileManager.default.contentsOfDirectory(at: VaultLocations(root: f.root).recoveryDir, includingPropertiesForKeys: nil)
        #expect(recovery.count == 1)
        #expect(try Data(contentsOf: recovery[0]) == bytes)
    }

    @Test func repeatedLoadsOfCorruptVaultKeepOneRecoveryCopy() async throws {
        let f = Fixture()
        let loc = VaultLocations(root: f.root)
        try await f.repo.save(canaryPayload())
        var bytes = try Data(contentsOf: loc.vaultFile)
        bytes[bytes.count - 1] ^= 0x01
        try bytes.write(to: loc.vaultFile)
        for _ in 0 ..< 3 { _ = try? await f.repo.load() }
        let recovery = try FileManager.default.contentsOfDirectory(at: loc.recoveryDir, includingPropertiesForKeys: nil)
        #expect(recovery.count == 1)
    }

    @Test func recoveryCopyIsNotClaimedWhenItCouldNotBeWritten() async throws {
        let f = Fixture()
        let loc = VaultLocations(root: f.root)
        try await f.repo.save(canaryPayload())
        var bytes = try Data(contentsOf: loc.vaultFile)
        bytes[bytes.count - 1] ^= 0x01
        try bytes.write(to: loc.vaultFile)
        // Make recovery/ impossible to create: a regular file in its place.
        try Data("x".utf8).write(to: loc.recoveryDir)
        do {
            _ = try await f.repo.load()
            Issue.record("corrupt vault loaded")
        } catch {
            guard case .corrupted(let copy, _) = error else { Issue.record("wrong error \(error)"); return }
            #expect(copy == nil)
        }
        #expect(try Data(contentsOf: loc.vaultFile) == bytes)
    }

    @Test func exportFailingVerificationIsRemoved() async throws {
        let f = Fixture()
        let failing = VerifyFailingProtection()
        let repo = HouseholdVaultRepository(locations: VaultLocations(root: f.root), keyStore: f.keys, protection: failing)
        await #expect(throws: VaultError.self) { _ = try await repo.makeExportFile(named: "plan.pdf", data: Data("%PDF \(canary)".utf8)) }
        #expect(allFileBytes(under: f.root).allSatisfy { !contains($0.1, canary) })
    }

    @Test func removeExportIgnoresSiblingDirectories() async throws {
        let f = Fixture()
        let loc = VaultLocations(root: f.root)
        let sibling = loc.privateRoot.appendingPathComponent("exports-other", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let file = sibling.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: file)
        await f.repo.removeExport(file)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func deleteAllRemovesOrphanedTempFiles() async throws {
        let f = Fixture()
        let loc = VaultLocations(root: f.root)
        try await f.repo.save(canaryPayload())
        let orphan = loc.privateRoot.appendingPathComponent(".household.vault.\(UUID().uuidString).tmp")
        try Data("ciphertext".utf8).write(to: orphan)
        try await f.repo.deleteAll()
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }
}

/// Protects nothing and reports unprotected: simulates verification failure after rename.
final class VerifyFailingProtection: FileProtectionApplying, @unchecked Sendable {
    func protect(_ url: URL) throws {}
    func isProtected(_ url: URL) throws -> Bool { false }
}
