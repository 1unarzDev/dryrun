import DryRunVault
import Foundation

/// Applies FileProtectionType.complete and excludes private files from device/iCloud backup.
/// Verified on the FINAL file after each atomic replace (DryRunVault.AtomicFile calls isProtected).
/// Must be verified on a physical device: the simulator does not enforce data protection.
public struct VaultFileProtection: FileProtectionApplying {
    public init() {}

    public func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
    }

    public func isProtected(_ url: URL) throws -> Bool {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let protection = attrs[.protectionKey] as? FileProtectionType
        let excluded = try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false
        return protection == .complete && excluded
    }
}

extension VaultLocations {
    /// Application Support/DryRun. Private subtree is excluded from backup; public cache is a sibling.
    public static func appDefault() throws -> VaultLocations {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return VaultLocations(root: base.appendingPathComponent("DryRun", isDirectory: true))
    }
}
