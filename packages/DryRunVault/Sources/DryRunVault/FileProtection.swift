import Foundation

/// Applies and verifies at-rest protection on private files.
/// iOS: FileProtectionType.complete + isExcludedFromBackup (apps/ios/DryRun/Services/VaultFileProtection.swift).
public protocol FileProtectionApplying: Sendable {
    func protect(_ url: URL) throws
    /// True only if the file at `url` currently carries the required protection and backup exclusion.
    func isProtected(_ url: URL) throws -> Bool
}

/// Test double: records which paths were protected; can be told to fail.
public final class RecordingFileProtection: FileProtectionApplying, @unchecked Sendable {
    private let lock = NSLock()
    private var protected: Set<String> = []
    private var failNext = false

    public init() {}

    public func failNextProtect() { lock.withLock { failNext = true } }

    public func protect(_ url: URL) throws {
        try lock.withLock {
            if failNext { failNext = false; throw VaultError.fileProtectionFailed("injected failure") }
            protected.insert(url.standardizedFileURL.path)
        }
    }

    public func isProtected(_ url: URL) throws -> Bool {
        lock.withLock { protected.contains(url.standardizedFileURL.path) }
    }

    /// Simulates attributes being lost when a file is replaced by a new inode.
    public func forget(_ url: URL) { _ = lock.withLock { protected.remove(url.standardizedFileURL.path) } }
}
