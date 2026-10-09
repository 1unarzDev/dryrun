import DryRunCore
import Foundation

/// Everything private the app retains. Sealed as a whole; never written in plaintext.
public struct VaultPayload: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var household: HouseholdProfile?
    public var home: HomeModel?
    /// Plans the household chose to keep. Stored as encoded documents keyed by revision.
    public var retainedPlans: [RetainedPlan]
    /// Cached rehearsal results; stale entries are invalid once household/home/content revisions change.
    public var rehearsalResults: [CachedRehearsal]
    public var savedAt: Date

    public init(household: HouseholdProfile? = nil, home: HomeModel? = nil, retainedPlans: [RetainedPlan] = [],
                rehearsalResults: [CachedRehearsal] = [], savedAt: Date = Date()) {
        self.schemaVersion = Self.currentSchemaVersion
        self.household = household; self.home = home; self.retainedPlans = retainedPlans
        self.rehearsalResults = rehearsalResults; self.savedAt = savedAt
    }

    /// Drops plans/results whose revision key no longer matches the current household/home/content.
    /// Editing a door, need, device, or supply must never leave an old "good" result available.
    public mutating func pruneStale(current: RevisionKey) {
        retainedPlans.removeAll { !$0.revisionKey.matchesInputs(of: current) }
        rehearsalResults.removeAll { !$0.revisionKey.matchesInputs(of: current) }
    }
}

public struct RetainedPlan: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var revisionKey: RevisionKey
    public var locale: String
    public var scenarioIDs: [String]
    public var generatedAt: Date
    /// Encoded PlanDocument (lead-owned type), kept opaque here.
    public var document: Data
    public init(id: String, revisionKey: RevisionKey, locale: String, scenarioIDs: [String], generatedAt: Date, document: Data) {
        self.id = id; self.revisionKey = revisionKey; self.locale = locale; self.scenarioIDs = scenarioIDs
        self.generatedAt = generatedAt; self.document = document
    }
}

public struct CachedRehearsal: Codable, Sendable, Hashable {
    public var revisionKey: RevisionKey
    public var scenarioID: String
    public var result: Data
    public init(revisionKey: RevisionKey, scenarioID: String, result: Data) {
        self.revisionKey = revisionKey; self.scenarioID = scenarioID; self.result = result
    }
}

extension RevisionKey {
    /// Same household/home/content revisions. Algorithm version is compared too: a new engine invalidates.
    public func matchesInputs(of other: RevisionKey) -> Bool {
        householdID == other.householdID && householdRevision == other.householdRevision
            && homeID == other.homeID && homeRevision == other.homeRevision
            && contentVersion == other.contentVersion && algorithmVersion == other.algorithmVersion
    }
}

/// Authenticated (not encrypted) envelope header. Its exact bytes are the AES-GCM associated data,
/// so changing any metadata field makes decryption fail.
public struct VaultEnvelopeHeader: Codable, Sendable, Hashable {
    public static let magicValue = "DRYRUN-VAULT"
    public static let currentFormatVersion = 1

    public var magic: String
    public var formatVersion: Int
    public var payloadSchemaVersion: Int
    public var keyID: String
    public var algorithm: String
    public var createdAt: Date

    public init(payloadSchemaVersion: Int, keyID: String, createdAt: Date) {
        self.magic = Self.magicValue; self.formatVersion = Self.currentFormatVersion
        self.payloadSchemaVersion = payloadSchemaVersion; self.keyID = keyID
        self.algorithm = "AES-GCM-256"; self.createdAt = createdAt
    }
}

public enum VaultError: Error, Sendable, Equatable {
    /// Device locked / key not accessible right now. NOT corruption; try again after unlock.
    case keyUnavailableWhileLocked
    /// A vault file exists but its key is gone (e.g. restored to a new phone). Data is not readable;
    /// the file is preserved and onboarding must not pretend this is a fresh start.
    case keyLost(preservedVault: URL)
    /// Ciphertext or header failed authentication/parsing. The original stays in place; `recoveryCopy` is
    /// non-nil only if an additional copy was actually written to recovery/.
    case corrupted(recoveryCopy: URL?, reason: String)
    /// The vault was sealed with a different key than the one in the key store. Original kept (and copied).
    case keyMismatch(expected: String, found: String, recoveryCopy: URL?)
    /// The key is available (device unlocked) but the vault file could not be read (permissions, I/O).
    case readFailed(String)
    case migrationFailed(fromVersion: Int, reason: String)
    case unsupportedNewerVersion(Int)
    case fileProtectionFailed(String)
    case writeFailed(String)
}
