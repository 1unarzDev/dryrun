import Foundation
import Testing
@testable import DryRunCore

@Suite("Capability matrix")
struct PlanCapabilityTests {
    static let full = CapabilitySnapshot(roomCaptureSupported: true, camera: .notDetermined, location: .notDetermined,
                                         online: true, explanationModelAvailable: true)

    @Test("No LiDAR: scanning unavailable, but manual layout, rehearsals, and plans remain")
    func noLidar() {
        var c = Self.full; c.roomCaptureSupported = false
        let p = CapabilityPlan.make(c)
        #expect(p.scan == .unsupportedDevice)
        #expect(p.manualLayoutAvailable && p.rehearsalsAvailable && p.plansAvailable)
        #expect(p.explanations == .onDeviceModelOptional, "LiDAR absence says nothing about the language model")
    }

    @Test("Model unavailable on a LiDAR device: templates only, scanning unaffected")
    func noModel() {
        var c = Self.full; c.explanationModelAvailable = false
        let p = CapabilityPlan.make(c)
        #expect(p.explanations == .templatesOnly)
        #expect(p.scan == .available)
    }

    @Test("Camera denied is distinct from unsupported hardware")
    func cameraDenied() {
        var c = Self.full; c.camera = .denied
        #expect(CapabilityPlan.make(c).scan == .cameraDenied)
        c.roomCaptureSupported = false
        #expect(CapabilityPlan.make(c).scan == .unsupportedDevice)
    }

    @Test("Location denied: manual region picker still works")
    func locationDenied() {
        var c = Self.full; c.location = .denied
        #expect(CapabilityPlan.make(c).regionSelection == .manualPicker)
    }

    @Test("Offline: cached alerts only; every required feature still available")
    func offline() {
        var c = Self.full; c.online = false
        let p = CapabilityPlan.make(c)
        #expect(p.alerts == .cachedOnly && p.mapTilesMayBeUnavailable)
        #expect(p.rehearsalsAvailable && p.plansAvailable && p.manualLayoutAvailable)
    }

    @Test("Worst case (no LiDAR, no model, everything denied, offline) keeps the full core product")
    func worstCase() {
        let p = CapabilityPlan.make(CapabilitySnapshot(roomCaptureSupported: false, camera: .restricted, location: .denied,
                                                       online: false, explanationModelAvailable: false))
        #expect(p.rehearsalsAvailable && p.plansAvailable && p.manualLayoutAvailable)
        #expect(p.scan == .unsupportedDevice && p.alerts == .cachedOnly && p.explanations == .templatesOnly)
    }
}
