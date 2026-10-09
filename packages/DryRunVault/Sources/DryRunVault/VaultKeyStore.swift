import Foundation

public struct VaultKeyMaterial: Sendable, Equatable {
    public var keyID: String
    /// 256-bit symmetric key bytes.
    public var rawKey: Data
    public init(keyID: String, rawKey: Data) { self.keyID = keyID; self.rawKey = rawKey }

    public static func generate() -> VaultKeyMaterial {
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        return VaultKeyMaterial(keyID: UUID().uuidString, rawKey: raw)
    }

    var symmetricKey: SymmetricKey { SymmetricKey(data: rawKey) }
}

public enum VaultKeyError: Error, Sendable, Equatable {
    /// Keychain says the item exists but is inaccessible (device locked).
    case unavailableWhileLocked
    /// No key stored.
    case missing
    case other(String)
}

/// Stores the single random vault key. The iOS implementation uses Keychain with
/// kSecAttrAccessibleWhenUnlockedThisDeviceOnly (apps/ios/DryRun/Services/KeychainVaultKeyStore.swift).
public protocol VaultKeyStore: Sendable {
    func loadKey() throws(VaultKeyError) -> VaultKeyMaterial
    func createKey() throws(VaultKeyError) -> VaultKeyMaterial
    func deleteKey() throws(VaultKeyError)
}

/// Test double. Can simulate a locked device.
public final class InMemoryVaultKeyStore: VaultKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: VaultKeyMaterial?
    private var locked = false

    public init(key: VaultKeyMaterial? = nil) { self.key = key }

    public func setLocked(_ value: Bool) { lock.withLock { locked = value } }
    public var storedKey: VaultKeyMaterial? { lock.withLock { key } }

    public func loadKey() throws(VaultKeyError) -> VaultKeyMaterial {
        lock.lock(); defer { lock.unlock() }
        if locked { throw .unavailableWhileLocked }
        guard let key else { throw .missing }
        return key
    }

    public func createKey() throws(VaultKeyError) -> VaultKeyMaterial {
        lock.lock(); defer { lock.unlock() }
        if locked { throw .unavailableWhileLocked }
        let new = VaultKeyMaterial.generate()
        key = new
        return new
    }

    public func deleteKey() throws(VaultKeyError) {
        lock.withLock { key = nil }
    }
}
