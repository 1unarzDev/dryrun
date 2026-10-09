import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum AtomicFile {
    /// Writes to a sibling temp file, protects it, renames over the destination (atomic on the same
    /// volume), then re-applies and verifies protection on the FINAL path. If any step fails the
    /// previous destination file is untouched and the temp file is removed.
    static func write(_ data: Data, to destination: URL, protection: FileProtectionApplying?) throws {
        let dir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let temp = dir.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            guard FileManager.default.createFile(atPath: temp.path, contents: data) else {
                throw VaultError.writeFailed("could not create temporary file")
            }
            try protection?.protect(temp)
            guard rename(temp.path, destination.path) == 0 else {
                throw VaultError.writeFailed("rename failed errno=\(errno)")
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        if let protection {
            try protection.protect(destination)
            guard try protection.isProtected(destination) else {
                throw VaultError.fileProtectionFailed("protection not present on final file")
            }
        }
    }
}
