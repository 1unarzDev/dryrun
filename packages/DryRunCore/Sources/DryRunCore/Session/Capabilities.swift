import Foundation

public enum PermissionState: String, Codable, Sendable, Hashable {
    case notDetermined, denied, restricted, authorized
}

/// Independent device facts. None is inferred from another (LiDAR ≠ Apple Intelligence ≠ "Pro" model name).
public struct CapabilitySnapshot: Codable, Sendable, Hashable {
    public var roomCaptureSupported: Bool
    public var camera: PermissionState
    public var location: PermissionState
    public var online: Bool
    public var explanationModelAvailable: Bool
    public init(roomCaptureSupported: Bool, camera: PermissionState, location: PermissionState, online: Bool,
                explanationModelAvailable: Bool) {
        self.roomCaptureSupported = roomCaptureSupported; self.camera = camera; self.location = location
        self.online = online; self.explanationModelAvailable = explanationModelAvailable
    }
}

public enum ScanAvailability: String, Codable, Sendable, Hashable {
    /// LiDAR capture supported; camera permission will be requested when the flow opens.
    case available
    /// Supported, but camera access was denied/restricted. Point to Settings; manual layout still works.
    case cameraDenied
    /// Device cannot run RoomPlan. Manual layout and the sample home are the paths.
    case unsupportedDevice
}

public enum AlertsMode: String, Codable, Sendable, Hashable { case live, cachedOnly }
public enum ExplanationMode: String, Codable, Sendable, Hashable { case onDeviceModelOptional, templatesOnly }
public enum RegionSelectionMode: String, Codable, Sendable, Hashable { case manualPicker, manualPickerOrLocation }

/// What the app offers for a given set of capabilities. Required features never depend on optional ones:
/// rehearsals, recommendations, the home view, manual layout, and saved plans are always available.
public struct CapabilityPlan: Codable, Sendable, Hashable {
    public var scan: ScanAvailability
    public var manualLayoutAvailable: Bool
    public var rehearsalsAvailable: Bool
    public var plansAvailable: Bool
    public var alerts: AlertsMode
    public var explanations: ExplanationMode
    public var regionSelection: RegionSelectionMode
    public var mapTilesMayBeUnavailable: Bool

    public static func make(_ c: CapabilitySnapshot) -> CapabilityPlan {
        let scan: ScanAvailability
        if !c.roomCaptureSupported { scan = .unsupportedDevice }
        else if c.camera == .denied || c.camera == .restricted { scan = .cameraDenied }
        else { scan = .available }
        let locationUsable = c.location == .authorized || c.location == .notDetermined
        return CapabilityPlan(
            scan: scan,
            manualLayoutAvailable: true,
            rehearsalsAvailable: true,
            plansAvailable: true,
            alerts: c.online ? .live : .cachedOnly,
            explanations: c.explanationModelAvailable ? .onDeviceModelOptional : .templatesOnly,
            regionSelection: locationUsable ? .manualPickerOrLocation : .manualPicker,
            mapTilesMayBeUnavailable: !c.online
        )
    }
}
