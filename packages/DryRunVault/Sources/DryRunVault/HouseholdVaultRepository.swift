import DryRunCore
import Foundation

/// On-device layout. `publicCache` is deliberately outside the private tree and survives delete-all.
public struct VaultLocations: Sendable {
    public var root: URL
    public init(root: URL) { self.root = root }
    public var privateRoot: URL { root.appendingPathComponent("private", isDirectory: true) }
    public var vaultFile: URL { privateRoot.appendingPathComponent("household.vault") }
    public var recoveryDir: URL { privateRoot.appendingPathComponent("recovery", isDirectory: true) }
    /// Encrypted derived private caches (route/plan renderings etc.).
    public var derivedDir: URL { privateRoot.appendingPathComponent("derived", isDirectory: true) }
    /// Plaintext exports created only for explicit preview/share/print.
    public var exportsDir: URL { privateRoot.appendingPathComponent("exports", isDirectory: true) }
    public var publicCache: URL { root.appendingPathComponent("public", isDirectory: true) }
}

/// Migrates a decoded-but-older payload JSON object to the current schema. Each step must be pure.
public typealias VaultMigration = @Sendable (_ json: Data) throws -> Data

public actor HouseholdVaultRepository {
    public let locations: VaultLocations
    private let keyStore: VaultKeyStore
    private let protection: FileProtectionApplying
    /// fromVersion -> migration to fromVersion + 1
    private let migrations: [Int: VaultMigration]
    private let currentSchemaVersion: Int
    private let now: @Sendable () -> Date

    public init(locations: VaultLocations, keyStore: VaultKeyStore, protection: FileProtectionApplying,
                migrations: [Int: VaultMigration] = [:], currentSchemaVersion: Int = VaultPayload.currentSchemaVersion,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.locations = locations; self.keyStore = keyStore; self.protection = protection
        self.migrations = migrations; self.currentSchemaVersion = currentSchemaVersion; self.now = now
    }

    // MARK: Load

    /// Returns nil only when no vault exists and no key exists (genuine first launch).
    /// Every other failure throws; it never returns an empty "successful" household.
    public func load() throws(VaultError) -> VaultPayload? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: locations.vaultFile.path) else { return nil }
        let key: VaultKeyMaterial
        do { key = try keyStore.loadKey() } catch {
            switch error {
            case .unavailableWhileLocked: throw .keyUnavailableWhileLocked
            case .missing: throw .keyLost(preservedVault: locations.vaultFile)
            case .other(let m): throw .writeFailed("key store: \(m)")
            }
        }
        // The key store already proved the device is unlocked, so an unreadable file is an I/O or
        // permissions problem, not "locked".
        let bytes = try readVaultBytes()
        let (header, json) = try open(bytes, key: key)
        return try migrateAndDecode(json, from: header.payloadSchemaVersion)
    }

    // MARK: Save

    /// Saves the payload. If a vault already exists, it must open with the current key first; a vault that
    /// cannot be read, is corrupt, or was sealed with another key is never silently replaced. Only an explicit
    /// start-over (`overwriteUnreadable: true`) may replace it, and a recovery copy is kept first.
    public func save(_ payload: VaultPayload, overwriteUnreadable: Bool = false) throws(VaultError) {
        let key = try keyForWriting()
        if FileManager.default.fileExists(atPath: locations.vaultFile.path) {
            do {
                let existing = try readVaultBytes()
                _ = try open(existing, key: key)
            } catch {
                guard overwriteUnreadable else { throw error }
                if let bytes = FileManager.default.contents(atPath: locations.vaultFile.path) {
                    _ = preserveRecoveryCopy(bytes)
                }
            }
        }
        var payload = payload
        payload.schemaVersion = currentSchemaVersion
        payload.savedAt = now()
        let json: Data
        do { json = try DryRunJSON.encoder().encode(payload) } catch { throw .writeFailed("encode: \(error)") }
        let sealed = try seal(json, key: key)
        do {
            try FileManager.default.createDirectory(at: locations.privateRoot, withIntermediateDirectories: true)
            try AtomicFile.write(sealed, to: locations.vaultFile, protection: protection)
        } catch let e as VaultError { throw e } catch { throw .writeFailed("\(error)") }
    }

    // MARK: Derived private caches

    /// Encrypted derived cache entry bound to a revision key. A different revision reads as a miss.
    public func storeDerived(_ data: Data, name: String, revision: RevisionKey) throws(VaultError) {
        let key = try keyForWriting()
        let wrapper = DerivedEntry(revision: revision, data: data)
        let json: Data
        do { json = try DryRunJSON.encoder().encode(wrapper) } catch { throw .writeFailed("\(error)") }
        let sealed = try seal(json, key: key)
        do {
            try AtomicFile.write(sealed, to: locations.derivedDir.appendingPathComponent(safeName(name)), protection: protection)
        } catch let e as VaultError { throw e } catch { throw .writeFailed("\(error)") }
    }

    public func loadDerived(name: String, revision: RevisionKey) throws(VaultError) -> Data? {
        let url = locations.derivedDir.appendingPathComponent(safeName(name))
        guard let bytes = FileManager.default.contents(atPath: url.path) else { return nil }
        let key: VaultKeyMaterial
        do { key = try keyStore.loadKey() } catch {
            if error == .unavailableWhileLocked { throw .keyUnavailableWhileLocked }
            return nil
        }
        guard let (_, json) = try? open(bytes, key: key, preserveOnFailure: false),
              let entry = try? DryRunJSON.decoder().decode(DerivedEntry.self, from: json),
              entry.revision.matchesInputs(of: revision) else { return nil }
        return entry.data
    }

    // MARK: Temporary plaintext exports

    /// The only plaintext private file the app writes, created for explicit preview/share/print.
    public func makeExportFile(named name: String, data: Data) throws(VaultError) -> URL {
        let url = locations.exportsDir.appendingPathComponent(safeName(name))
        do { try AtomicFile.write(data, to: url, protection: protection, removeOnVerificationFailure: true) }
        catch let e as VaultError { throw e } catch { throw .writeFailed("\(error)") }
        return url
    }

    public func removeExport(_ url: URL) {
        let dir = locations.exportsDir.standardizedFileURL.pathComponents
        let target = url.standardizedFileURL.pathComponents
        guard target.count > dir.count, Array(target.prefix(dir.count)) == dir else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Call on launch / after share sheet completes: removes all leftover plaintext exports.
    public func cleanupExports() {
        try? FileManager.default.removeItem(at: locations.exportsDir)
    }

    // MARK: Delete all

    /// Purges the whole private tree (vault, crash-orphaned temp files, recovery copies, derived caches,
    /// plaintext exports) and the key. Public downloaded packs live in a sibling directory and are kept.
    /// Copies the user already shared cannot be revoked.
    public func deleteAll() throws(VaultError) {
        let fm = FileManager.default
        if fm.fileExists(atPath: locations.privateRoot.path) {
            do { try fm.removeItem(at: locations.privateRoot) } catch { throw .writeFailed("delete private data: \(error)") }
        }
        do { try keyStore.deleteKey() } catch { throw .writeFailed("delete key: \(error)") }
    }

    // MARK: Internals

    private struct DerivedEntry: Codable { var revision: RevisionKey; var data: Data }

    private func safeName(_ name: String) -> String {
        let allowed = name.filter { $0.isLetter || $0.isNumber || "-_.".contains($0) }
        return allowed.isEmpty ? "unnamed" : String(allowed.prefix(120))
    }

    private func keyForWriting() throws(VaultError) -> VaultKeyMaterial {
        do { return try keyStore.loadKey() } catch {
            switch error {
            case .unavailableWhileLocked: throw .keyUnavailableWhileLocked
            case .other(let m): throw .writeFailed("key store: \(m)")
            case .missing:
                // Never mint a new key over an existing vault: that would orphan the household's data.
                if FileManager.default.fileExists(atPath: locations.vaultFile.path) {
                    throw .keyLost(preservedVault: locations.vaultFile)
                }
                do { return try keyStore.createKey() } catch {
                    throw error == .unavailableWhileLocked ? .keyUnavailableWhileLocked : .writeFailed("create key")
                }
            }
        }
    }

    /// File format: 4-byte big-endian header length | header JSON | AES-GCM combined (nonce|ciphertext|tag).
    private func seal(_ plaintext: Data, key: VaultKeyMaterial) throws(VaultError) -> Data {
        let header = VaultEnvelopeHeader(payloadSchemaVersion: currentSchemaVersion, keyID: key.keyID, createdAt: now())
        do {
            let headerBytes = try DryRunJSON.encoder().encode(header)
            // AES.GCM.seal generates a fresh random 96-bit nonce per call.
            let box = try AES.GCM.seal(plaintext, using: key.symmetricKey, authenticating: headerBytes)
            guard let combined = box.combined else { throw VaultError.writeFailed("no combined box") }
            var out = Data()
            var len = UInt32(headerBytes.count).bigEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
            out.append(headerBytes)
            out.append(combined)
            return out
        } catch let e as VaultError { throw e } catch { throw .writeFailed("seal: \(error)") }
    }

    private func open(_ bytes: Data, key: VaultKeyMaterial, preserveOnFailure: Bool = true) throws(VaultError)
        -> (VaultEnvelopeHeader, Data) {
        func fail(_ reason: String) -> VaultError {
            .corrupted(recoveryCopy: preserveOnFailure ? preserveRecoveryCopy(bytes) : nil, reason: reason)
        }
        guard bytes.count > 4 else { throw fail("truncated") }
        let len = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard len > 0, Int(len) <= 4096, bytes.count > 4 + Int(len) else { throw fail("bad header length") }
        let headerBytes = bytes.subdata(in: 4 ..< 4 + Int(len))
        let boxBytes = bytes.subdata(in: 4 + Int(len) ..< bytes.count)
        guard let header = try? DryRunJSON.decoder().decode(VaultEnvelopeHeader.self, from: headerBytes),
              header.magic == VaultEnvelopeHeader.magicValue else { throw fail("bad header") }
        guard header.formatVersion <= VaultEnvelopeHeader.currentFormatVersion else {
            throw .unsupportedNewerVersion(header.formatVersion)
        }
        guard header.keyID == key.keyID else {
            throw .keyMismatch(expected: key.keyID, found: header.keyID,
                               recoveryCopy: preserveOnFailure ? preserveRecoveryCopy(bytes) : nil)
        }
        do {
            let box = try AES.GCM.SealedBox(combined: boxBytes)
            let plain = try AES.GCM.open(box, using: key.symmetricKey, authenticating: headerBytes)
            return (header, plain)
        } catch {
            throw fail("authentication failed")
        }
    }

    private func migrateAndDecode(_ json: Data, from version: Int) throws(VaultError) -> VaultPayload {
        if version > currentSchemaVersion { throw .unsupportedNewerVersion(version) }
        var data = json
        var v = version
        while v < currentSchemaVersion {
            guard let step = migrations[v] else { throw .migrationFailed(fromVersion: v, reason: "no migration registered") }
            do { data = try step(data) } catch { throw .migrationFailed(fromVersion: v, reason: "\(error)") }
            v += 1
        }
        do { return try DryRunJSON.decoder().decode(VaultPayload.self, from: data) } catch {
            // Original file is untouched; nothing is written on a failed load/migration.
            throw .migrationFailed(fromVersion: version, reason: "decode: \(error)")
        }
    }

    /// Copies (never moves) the unreadable original into recovery/ so a later fix can retry. Named by content
    /// hash, so retries on the same bytes reuse one copy. Returns nil unless the copy really exists.
    private func preserveRecoveryCopy(_ bytes: Data) -> URL? {
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined().prefix(24)
        let url = locations.recoveryDir.appendingPathComponent("household-\(digest).vault")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        do { try AtomicFile.write(bytes, to: url, protection: protection) } catch { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func readVaultBytes() throws(VaultError) -> Data {
        do { return try Data(contentsOf: locations.vaultFile) } catch { throw .readFailed("\(error)") }
    }
}
