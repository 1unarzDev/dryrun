import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum AtomicFile {
    /// Writes to a sibling temp file (created with complete protection where the platform supports it,
    /// flushed with fsync), protects it, renames over the destination (atomic on the same volume), then
    /// re-applies and verifies protection on the FINAL path. If any step before the rename fails, the
    /// previous destination is untouched and the temp file is removed. If final verification fails and
    /// `removeOnVerificationFailure` is set (plaintext exports), the unprotected file is deleted.
    static func write(_ data: Data, to destination: URL, protection: FileProtectionApplying?,
                      removeOnVerificationFailure: Bool = false) throws {
        let dir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let temp = dir.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            #if canImport(Darwin)
            let attributes: [FileAttributeKey: Any]? = protection == nil ? nil : [.protectionKey: FileProtectionType.complete]
            #else
            let attributes: [FileAttributeKey: Any]? = nil
            #endif
            guard FileManager.default.createFile(atPath: temp.path, contents: nil, attributes: attributes) else {
                throw VaultError.writeFailed("could not create temporary file")
            }
            let handle = try FileHandle(forWritingTo: temp)
            do {
                try handle.write(contentsOf: data)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
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
            var verified = false
            do {
                try protection.protect(destination)
                verified = try protection.isProtected(destination)
            } catch {
                verified = false
            }
            if !verified {
                if removeOnVerificationFailure { try? FileManager.default.removeItem(at: destination) }
                throw VaultError.fileProtectionFailed("protection not present on final file")
            }
        }
    }
}
