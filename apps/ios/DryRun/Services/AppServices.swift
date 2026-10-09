import Foundation
import Network
import AVFoundation
import CoreLocation
import DryRunCore
#if canImport(RoomPlan)
import RoomPlan
#endif

enum ContentLocator {
    struct Missing: Error, CustomStringConvertible { var description: String { "Bundled content folder is missing" } }
    /// The repository `content/` folder is bundled as a folder reference (see project.yml).
    static func contentRoot() throws -> URL {
        guard let url = Bundle.main.url(forResource: "content", withExtension: nil) else { throw Missing() }
        return url
    }
}

/// Independent capability checks. LiDAR scanning, the on-device model, camera/location permission,
/// and network are separate facts; none is inferred from another or from a device marketing name.
@MainActor
@Observable
final class CapabilityService {
    private(set) var roomCaptureSupported = false
    private(set) var cameraStatus: AVAuthorizationStatus = .notDetermined
    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var isOnline = true
    private(set) var explanationModel: ExplanationAvailability = .unavailable(reason: "Not checked")
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "dryrun.network"))
    }

    func refresh() {
        #if canImport(RoomPlan)
        roomCaptureSupported = RoomCaptureSession.isSupported
        #else
        roomCaptureSupported = false
        #endif
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        locationStatus = CLLocationManager().authorizationStatus
        explanationModel = ExplanationService.availability()
    }
}

/// Plaintext PDF exports exist only for an explicit preview/share/print, carry complete file protection,
/// are excluded from backup, and are purged on dismissal, on background, and on delete-all.
enum TemporaryExports {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dryrun-exports", isDirectory: true)
    }

    static func write(_ data: Data, name: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.protectionKey: FileProtectionType.complete])
        var url = directory.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return url
    }

    static func purgeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
