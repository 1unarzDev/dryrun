import Foundation
import Observation
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
            Task { @MainActor [weak self] in self?.isOnline = online }
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

    /// Pure, tested mapping (DryRunCore.CapabilityPlan) from independent device facts to offered flows.
    var plan: CapabilityPlan {
        CapabilityPlan.make(CapabilitySnapshot(
            roomCaptureSupported: roomCaptureSupported,
            camera: Self.permission(camera: cameraStatus),
            location: Self.permission(location: locationStatus),
            online: isOnline,
            explanationModelAvailable: explanationModel == .available))
    }

    static func permission(camera s: AVAuthorizationStatus) -> PermissionState {
        switch s {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }

    static func permission(location s: CLAuthorizationStatus) -> PermissionState {
        switch s {
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }
}

/// Plaintext PDF exports exist only for an explicit preview/share/print, carry complete file protection,
/// are excluded from backup, and are purged on dismissal, on background, and on delete-all.
enum TemporaryExports {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dryrun-exports", isDirectory: true)
    }

    /// Set while a preview/share/print may still read the file.
    @MainActor static var hasActiveExport = false
    @MainActor private static var activityReaders = 0
    @MainActor private static var purgeRequested = false
    @MainActor static func retainActivity() { activityReaders += 1 }
    @MainActor static func releaseActivity() {
        activityReaders = max(0, activityReaders - 1)
        if activityReaders == 0 && purgeRequested && !hasActiveExport { purgeAll() }
    }

    static func write(_ data: Data, name: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.protectionKey: FileProtectionType.complete])
        var url = directory.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            #if !targetEnvironment(simulator)
            // The simulator does not implement Data Protection; verify on devices only (see VERIFICATION.md).
            let protection = try fm.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType
            guard protection == .complete else { throw CocoaError(.fileWriteNoPermission) }
            #endif
        } catch {
            // Never leave an unprotected plaintext plan behind.
            try? fm.removeItem(at: url)
            throw error
        }
        return url
    }

    @MainActor static func purgeAll() {
        guard activityReaders == 0 else { purgeRequested = true; return }
        purgeRequested = false
        try? FileManager.default.removeItem(at: directory)
    }
}
