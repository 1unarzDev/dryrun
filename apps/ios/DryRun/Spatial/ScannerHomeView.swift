import SwiftUI
import RoomPlan
import AVFoundation
import DryRunCore

/// Home scanner: shows that this iPhone's LiDAR works (live depth), starts a RoomPlan scan, and summarizes the
/// scanned home. A scan is still only a proposal; it goes through the same confirmation pass as from Home.
struct ScannerHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var depth = LiDARDepthPreview()
    @State private var scanning = false
    @State private var showing3D = false
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private func t(_ key: String) -> String { model.localizer("spatial.scanner.\(key)") }

    private var lidar: Bool { LiDARDepthPreview.isSupported }
    private var roomPlan: Bool { RoomCaptureSession.isSupported }

    var body: some View {
        List {
            Section {
                Text(t("intro")).font(.callout)
                if !lidar || !roomPlan {
                    Label(t("sim"), systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section(t("device")) {
                status(t("lidar"), ok: lidar, value: t(lidar ? "yes" : "no"))
                status(t("roomplan"), ok: roomPlan, value: t(roomPlan ? "yes" : "no"))
                status(t("camera"), ok: cameraStatus == .authorized,
                       value: t(cameraStatus == .authorized ? "camera-on" : cameraStatus == .notDetermined ? "camera-ask" : "camera-off"))
            }
            if lidar { liveDepth }
            Section {
                Button {
                    depth.stop()
                    scanning = true
                } label: {
                    Label(t("scan"), systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!roomPlan || model.capabilities.plan.scan == .cameraDenied)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .accessibilityIdentifier("scanner.scan")
                Text(t("scan-detail")).font(.footnote).foregroundStyle(.secondary)
            }
            scannedHome
        }
        .navigationTitle(t("title"))
        .roomScanToHome(isPresented: $scanning)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { depth.stop() }
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
        .onDisappear { depth.stop() }
        .onChange(of: model.scopeSessionID) { _, _ in depth.stop(); scanning = false }
    }

    private func status(_ title: String, ok: Bool, value: String) -> some View {
        // A plain row: LabeledContent with a Label value stretched each row to a screen's height on device.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(ok ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(value).font(.footnote).foregroundStyle(ok ? Color.green : Color.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var liveDepth: some View {
        Section {
            if let sample = depth.sample {
                LiDARDepthImage(sample: sample)
                    .frame(maxWidth: .infinity, maxHeight: 300)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .accessibilityIdentifier("scanner.depthImage")
                LiDARDepthLegend(near: t("near"), far: t("far"))
                LabeledContent(t("center")) {
                    Text(sample.centerMeters.map(Self.distance) ?? "–")
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("scanner.centerDistance")
                LabeledContent(t("points"), value: sample.points.formatted())
                LabeledContent(t("confident"), value: sample.confidentShare.formatted(.percent.precision(.fractionLength(0))))
            } else if depth.running {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else if depth.interrupted {
                Text(t("interrupted")).font(.footnote).foregroundStyle(.secondary)
            }
            Button(depth.running ? t("live-stop") : t("live-start"),
                   systemImage: depth.running ? "stop.circle" : "sensor.tag.radiowaves.forward") {
                if depth.running { depth.stop() } else { Task { await startDepth() } }
            }
            .accessibilityIdentifier("scanner.liveDepth")
        } header: {
            Text(t("live"))
        } footer: {
            Text(t("live-detail"))
        }
    }

    @ViewBuilder private var scannedHome: some View {
        Section(t("result")) {
            if let home = model.home, home.source == .roomPlanScan {
                Picker("", selection: $showing3D) {
                    Text(SpatialStrings.text("2D plan", localizer: model.localizer)).tag(false)
                    Text(SpatialStrings.text("3D", localizer: model.localizer)).tag(true)
                }
                .pickerStyle(.segmented)
                Group {
                    if showing3D {
                        DollhouseView(home: home, routes: [], floorID: home.floors.first?.id)
                    } else {
                        FloorPlanView(home: home, routes: [], highlightedFloorID: home.floors.first?.id)
                    }
                }
                .frame(height: 280)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("scanner.result")
                let s = { (english: String) in SpatialStrings.text(english, localizer: model.localizer) }
                LabeledContent(s("Rooms"), value: "\(home.spaces.count)")
                LabeledContent(s("Doors and openings"), value: "\(home.portals.filter { $0.kind != .window }.count)")
                LabeledContent(s("Windows (not exits)"), value: "\(home.portals.filter { $0.kind == .window }.count)")
                LabeledContent(t("walls"), value: "\(home.walls.count)")
                LabeledContent(t("area"), value: Self.area(home.spaces.reduce(0) { $0 + Self.polygonArea($1.polygon) }))
                NavigationLink { HomeTabView() } label: { Label(t("open-home"), systemImage: "house") }
                Button(t("rehearse"), systemImage: "play.circle") { model.pendingTab = "rehearse" }
            } else {
                Text(t("no-scan")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func startDepth() async {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard cameraStatus == .authorized, scenePhase == .active, !scanning else { return }
        depth.start()
    }

    static func polygonArea(_ points: [Vec2]) -> Double {
        guard points.count > 2 else { return 0 }
        var sum = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Both systems: the demo family is in Texas, the sensor reports meters.
    static func distance(_ meters: Double) -> String {
        "\(meters.formatted(.number.precision(.fractionLength(2)))) m · \((meters * 3.28084).formatted(.number.precision(.fractionLength(1)))) ft"
    }

    static func area(_ squareMeters: Double) -> String {
        "\(squareMeters.formatted(.number.precision(.fractionLength(0)))) m² · \((squareMeters * 10.7639).formatted(.number.precision(.fractionLength(0)))) ft²"
    }
}

/// Scan → review → editor (confirm/correct) → save, as from Home. The scan is never saved without the editor's Save.
private struct RoomScanToHome: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    /// A finished scan waiting for the scan cover to finish dismissing before the editor sheet is presented.
    private struct CaptureTicket {
        let id = UUID()
        let scope: String
        let baseRevision: Int?
    }
    @State private var captureTicket: CaptureTicket?
    private struct ScanDraft: Identifiable {
        let id = UUID()
        let home: HomeModel
        let baseRevision: Int?
        let scope: String
    }
    @State private var pendingProposal: ScanDraft?
    @State private var draft: ScanDraft?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented, onDismiss: {
                // Presented from onDismiss because SwiftUI can drop a sheet requested while the cover is still dismissing.
                defer { pendingProposal = nil; captureTicket = nil }
                if let proposed = pendingProposal,
                   proposed.scope == model.scopeSessionID,
                   proposed.baseRevision == model.home?.revision {
                    draft = proposed
                }
            }) {
                if let ticket = captureTicket {
                    RoomScanFlowView { proposed in
                        guard captureTicket?.id == ticket.id,
                              ticket.scope == model.scopeSessionID,
                              ticket.baseRevision == model.home?.revision else { return }
                        guard let proposed else { isPresented = false; return }
                        pendingProposal = ScanDraft(home: proposed, baseRevision: ticket.baseRevision, scope: ticket.scope)
                        isPresented = false
                    }
                    .id(ticket.id)
                    .interactiveDismissDisabled()
                }
            }
            .onChange(of: isPresented, initial: true) { _, presented in
                if presented {
                    captureTicket = CaptureTicket(scope: model.scopeSessionID, baseRevision: model.home?.revision)
                }
            }
            .onChange(of: model.scopeSessionID) { _, _ in
                pendingProposal = nil; draft = nil; captureTicket = nil; isPresented = false
            }
            .sheet(item: $draft) { proposed in
                NavigationStack {
                    ManualHomeEditorView(home: proposed.home, selectedElementID: nil, savedBaseRevision: proposed.baseRevision, scopeSessionID: proposed.scope) { updated, baseRevision, scope in
                        let success = await model.updateHome(updated, baseRevision: baseRevision, scopeSessionID: scope)
                        if success { draft = nil }
                        return success
                    }
                }
                .interactiveDismissDisabled()
            }
    }
}

extension View {
    func roomScanToHome(isPresented: Binding<Bool>) -> some View { modifier(RoomScanToHome(isPresented: isPresented)) }
}
