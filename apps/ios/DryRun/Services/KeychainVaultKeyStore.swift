import DryRunVault
import Foundation
import Security

/// Stores the single random 256-bit vault key in the Keychain.
/// - kSecAttrAccessibleWhenUnlockedThisDeviceOnly: unreadable while locked; never migrates to another device
///   or into backups. Consequence (documented): a replacement phone cannot open an old vault.
/// - No iCloud Keychain sync (kSecAttrSynchronizable is false).
public struct KeychainVaultKeyStore: VaultKeyStore {
    private let service: String
    private let account = "household-vault-key"

    public init(service: String = "org.dryrun.app.vault") { self.service = service }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
    }

    public func loadKey() throws(VaultKeyError) -> VaultKeyMaterial {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let dict = item as? [String: Any], let data = dict[kSecValueData as String] as? Data, data.count == 32 else {
                throw .other("malformed key item")
            }
            let keyID = (dict[kSecAttrLabel as String] as? String) ?? "unlabelled"
            return VaultKeyMaterial(keyID: keyID, rawKey: data)
        case errSecItemNotFound:
            throw .missing
        case errSecInteractionNotAllowed:
            // Device locked (data protection). This is NOT corruption and NOT key loss.
            throw .unavailableWhileLocked
        default:
            throw .other("SecItemCopyMatching \(status)")
        }
    }

    public func createKey() throws(VaultKeyError) -> VaultKeyMaterial {
        let material = VaultKeyMaterial.generate()
        var query = baseQuery
        query[kSecValueData as String] = material.rawKey
        query[kSecAttrLabel as String] = material.keyID
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess: return material
        case errSecInteractionNotAllowed: throw .unavailableWhileLocked
        case errSecDuplicateItem: throw .other("key already exists; refusing to overwrite")
        default: throw .other("SecItemAdd \(status)")
        }
    }

    public func deleteKey() throws(VaultKeyError) {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .other("SecItemDelete \(status)") }
    }
}
