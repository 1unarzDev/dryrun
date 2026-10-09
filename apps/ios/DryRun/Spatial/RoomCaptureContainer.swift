import SwiftUI
import RoomPlan
import DryRunCore

// RoomPlan capture for SwiftUI. AUTHORED, NOT COMPILED/DEVICE-TESTED in this environment.
// - Gated by RoomCaptureSession.isSupported (LiDAR), independent of every other capability.
// - Multiroom: one RoomCaptureView/ARSession for the whole visit. Between rooms we call
//   stop(pauseARSession: false) so the next room continues in the same world frame, then merge with
//   StructureBuilder. Independently scanned rooms are never positioned by guessing (ScanImport refuses).
// - Nothing is persisted from the camera: no RGB frames, no ARWorldMap, no USDZ unless a later feature needs it.

@MainActor
final class RoomCaptureController: NSObject, ObservableObject, RoomCaptureViewDelegate {
    enum Phase: Equatable { case idle, scanning, processing, finished, failed(String) }

    @Published var phase: Phase = .idle
    @Published private(set) var rooms: [CapturedRoom] = []
    let captureView: RoomCaptureView
    private var wantsAnotherRoom = false

    override init() {
        captureView = RoomCaptureView(frame: .zero)
        super.init()
        captureView.delegate = self
    }

    // RoomCaptureViewDelegate inherits NSCoding; this controller is never archived.
    nonisolated required init?(coder: NSCoder) { nil }
    nonisolated func encode(with coder: NSCoder) {}

    func start() {
        phase = .scanning
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    /// Finish the current room but keep the ARSession running so the next room shares its frame.
    func finishRoomAndContinue() {
        wantsAnotherRoom = true
        phase = .processing
        captureView.captureSession.stop(pauseARSession: false)
    }

    func finishScan() {
        wantsAnotherRoom = false
        phase = .processing
        captureView.captureSession.stop()
    }

    func cancel() {
        captureView.captureSession.stop()
        rooms = []
        phase = .idle
    }

    var hasFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool { true }

    nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        Task { @MainActor in
            if let error {
                // The session has ended. Forget "next room" so a later result is not mistaken for a continuation.
                self.wantsAnotherRoom = false
                self.phase = .failed(error.localizedDescription)
                return
            }
            self.rooms.append(processedResult)
            if self.wantsAnotherRoom {
                self.wantsAnotherRoom = false
                self.start()
            } else {
                self.phase = .finished
            }
        }
    }

    /// Merge into one structure (shared frame) and convert to a PROPOSED HomeModel.
    func makeProposedHome() async throws -> ScanImportResult {
        let homeID = "home-scan-\(UUID().uuidString.prefix(8).lowercased())"
        if rooms.count > 1 {
            let builder = StructureBuilder(options: [.beautifyObjects])
            let structure = try await builder.capturedStructure(from: rooms)
            let capture = RoomPlanMapping.capture(rooms: structure.rooms, sharedFrame: true, completed: true)
            return try ScanImport.importCapture(capture, homeID: homeID)
        }
        let capture = RoomPlanMapping.capture(rooms: rooms, sharedFrame: true, completed: phase == .finished)
        return try ScanImport.importCapture(capture, homeID: homeID)
    }
}

struct RoomCaptureContainer: UIViewRepresentable {
    let controller: RoomCaptureController
    func makeUIView(context: Context) -> RoomCaptureView { controller.captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

/// Full-screen scan flow. Calls `onFinish(nil)` on cancel or when unsupported.
struct RoomScanFlowView: View {
    let onFinish: (HomeModel?) -> Void
    @StateObject private var controller = RoomCaptureController()
    @State private var started = false
    @State private var result: ScanImportResult?
    @State private var errorText: String?

    init(onFinish: @escaping (HomeModel?) -> Void) { self.onFinish = onFinish }

    var body: some View {
        NavigationStack {
            Group {
                if !RoomCaptureSession.isSupported {
                    ContentUnavailableView {
                        Label("Scanning isn't available on this device", systemImage: "camera.metering.unknown")
                    } description: {
                        Text("Room scanning needs a LiDAR sensor. You can build your home manually instead; every other feature works the same.")
                    } actions: {
                        Button("Close") { onFinish(nil) }
                    }
                } else if let result {
                    reviewView(result)
                } else if !started {
                    intro
                } else {
                    ZStack(alignment: .bottom) {
                        RoomCaptureContainer(controller: controller).ignoresSafeArea()
                        controls.padding()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { controller.cancel(); onFinish(nil) }
                }
            }
            .alert("Scan problem", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
            .onChange(of: controller.phase) { _, phase in
                if case .failed(let message) = phase { errorText = message }
                if phase == .finished { Task { await buildResult() } }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan your home").font(.title2.bold())
            Text("Walk slowly through each room. Scan all rooms in one visit so they line up.")
            Label("The scan stays on this phone. No video or photos are saved.", systemImage: "lock")
            Label("A scan shows layout, not safety. You'll confirm doors and exits afterwards.", systemImage: "checkmark.seal")
            Spacer()
            Button("Start scanning") { started = true; controller.start() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private var controls: some View {
        HStack {
            if controller.hasFailed {
                // The capture session ended with an error, so "Next room" and "Done" would wait for a result that
                // never comes. Offer a retry, and the rooms already saved if there are any.
                Button("Scan this room again") { controller.start() }
                    .buttonStyle(.bordered)
                Spacer()
                Text("\(controller.rooms.count) room\(controller.rooms.count == 1 ? "" : "s") saved").font(.footnote)
                Spacer()
                Button("Use saved rooms") { Task { await buildResult() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.rooms.isEmpty)
            } else {
                Button("Next room") { controller.finishRoomAndContinue() }
                    .buttonStyle(.bordered)
                Spacer()
                Text("\(controller.rooms.count) room\(controller.rooms.count == 1 ? "" : "s") saved").font(.footnote)
                Spacer()
                Button("Done") { controller.finishScan() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .disabled(controller.phase == .processing)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func reviewView(_ r: ScanImportResult) -> some View {
        List {
            Section("What was captured") {
                LabeledContent("Rooms", value: "\(r.home.spaces.count)")
                LabeledContent("Doors and openings", value: "\(r.home.portals.filter { $0.kind != .window }.count)")
                LabeledContent("Windows (not exits)", value: "\(r.home.portals.filter { $0.kind == .window }.count)")
            }
            Section("Before routes can use this scan") {
                ForEach(r.notes, id: \.self) { Text($0) }
            }
            Section {
                Button("Continue to confirmation") { onFinish(r.home) }
            }
        }
    }

    private func buildResult() async {
        do { result = try await controller.makeProposedHome() }
        catch { errorText = "The scan could not be turned into a floor plan. \(error.localizedDescription)" }
    }
}
