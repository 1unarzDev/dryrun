import SwiftUI
import RoomPlan
import ARKit
import AVFoundation
import DryRunCore

// RoomPlan capture for SwiftUI. AUTHORED, NOT COMPILED/DEVICE-TESTED in this environment.
// - Gated by RoomCaptureSession.isSupported (LiDAR), independent of every other capability.
// - Multiroom: one shared ARSession, one capture view/session with immutable delegate identity per room. Between rooms we call
//   stop(pauseARSession: false) so the next room continues in the same world frame, then merge with
//   StructureBuilder. Independently scanned rooms are never positioned by guessing (ScanImport refuses).
// - Nothing is persisted from the camera: no RGB frames, no ARWorldMap, no USDZ unless a later feature needs it.

@MainActor
final class RoomCaptureController: NSObject, ObservableObject {
    enum Phase: Equatable { case idle, scanning, processing, finished, failed(String) }

    @Published var phase: Phase = .idle
    @Published private(set) var rooms: [CapturedRoom] = []
    @Published private(set) var previousGroup: [CapturedRoom] = []
    @Published private(set) var captureView: RoomCaptureView?
    @Published private(set) var captureGeneration = 0
    private var sharedARSession: ARSession?
    private var captureFrameID = UUID().uuidString
    private var previousFrameID: String?
    /// Completion belongs to the selected group, never to the phase of a newer live capture.
    private var groupCompleted = false
    private var previousGroupCompleted = false
    private var delegates: [CaptureGenerationDelegate] = []
    private var wantsAnotherRoom = false
    /// Session state is deliberately checked before every callback. RoomPlan can deliver a processed result after
    /// stop/cancel; accepting that late result would publish a draft after the user left the flow.
    private var callbackGeneration = 0
    private var callbackGate = CaptureCallbackGate()
    private var sharedFrameValid = true

    override init() { super.init() }

    private func beginRoom() {
        callbackGeneration = callbackGate.begin()
        captureGeneration = callbackGeneration
        // A different capture view/session and immutable delegate identity for every room. A late callback
        // is therefore tied to its originating room, even while a newer room is processing.
        let arSession: ARSession
        if let existing = sharedARSession { arSession = existing }
        else {
            arSession = ARSession()
            arSession.run(ARWorldTrackingConfiguration())
            sharedARSession = arSession
        }
        let view = RoomCaptureView(frame: .zero, arSession: arSession)
        guard let session = view.captureSession else {
            callbackGate.invalidate()
            callbackGeneration = callbackGate.generation
            phase = .failed("spatial.scan-interrupted")
            return
        }
        let delegate = CaptureGenerationDelegate(generation: callbackGeneration, owner: self)
        delegates.append(delegate)
        view.delegate = delegate
        session.delegate = delegate
        captureView = view
        phase = .scanning
        session.run(configuration: RoomCaptureSession.Configuration())
    }

    func start() {
        guard phase == .idle || hasFailed else { return }
        // Retrying after an interruption starts a new AR frame. Previously captured rooms cannot be positioned
        // relative to that frame by guessing, so multiroom import will remain explicitly unaligned.
        if hasFailed, !rooms.isEmpty {
            previousGroup = rooms; previousFrameID = captureFrameID
            previousGroupCompleted = groupCompleted; rooms = []
        }
        sharedFrameValid = true
        if hasFailed { sharedARSession = nil; captureFrameID = UUID().uuidString; groupCompleted = false }
        beginRoom()
    }

    /// Finish the current room but keep the ARSession running so the next room shares its frame.
    func finishRoomAndContinue() {
        guard phase == .scanning else { return }
        wantsAnotherRoom = true
        phase = .processing
        guard callbackGate.expectFinish(from: callbackGeneration) else { return }
        captureView?.captureSession.stop(pauseARSession: false)
    }

    func finishScan() {
        guard phase == .scanning else { return }
        wantsAnotherRoom = false
        phase = .processing
        guard callbackGate.expectFinish(from: callbackGeneration) else { return }
        captureView?.captureSession.stop()
    }

    func cancel() {
        callbackGate.invalidate()
        callbackGeneration = callbackGate.generation
        captureView?.captureSession.stop()
        sharedARSession = nil
        captureView = nil
        rooms = []
        previousGroup = []
        previousFrameID = nil
        groupCompleted = false; previousGroupCompleted = false
        captureFrameID = UUID().uuidString
        sharedFrameValid = true
        phase = .idle
    }

    /// Background/interruption path. Retain already processed rooms for an honest retry, but invalidate their shared
    /// frame so a later retry cannot silently merge coordinates from two AR sessions.
    func interrupted() {
        guard phase == .scanning || phase == .processing else { return }
        callbackGate.invalidate()
        callbackGeneration = callbackGate.generation
        wantsAnotherRoom = false
        // Already processed rooms retain their valid shared frame; retry starts a separate group.
        captureView?.captureSession.stop()
        phase = .failed("spatial.scan-interrupted")
    }

    var hasFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    func retainDraftAfterProcessingFailure(_ message: String) {
        // makeProposedHome already froze capture. Keep its selected rooms and present Retry / Use saved rooms.
        phase = .failed(message)
    }

    fileprivate func received(_ room: CapturedRoom, error: Error?, generation: Int) {
        guard phase == .processing, callbackGate.accept(from: generation) else { return }
        if let error {
            wantsAnotherRoom = false
            phase = .failed(error.localizedDescription)
            return
        }
        rooms.append(room)
        if wantsAnotherRoom {
            wantsAnotherRoom = false
            beginRoom()
        } else { groupCompleted = true; phase = .finished }
    }

    fileprivate func failedCapture(_ message: String, generation: Int) {
        guard generation == callbackGeneration, phase == .scanning || phase == .processing else { return }
        callbackGate.invalidate(); callbackGeneration = callbackGate.generation
        wantsAnotherRoom = false
        captureView?.captureSession.stop()
        phase = .failed(message)
    }

    /// Merge into one structure (shared frame) and convert to a PROPOSED HomeModel.
    func makeProposedHome(usePrevious: Bool = false) async throws -> ScanImportResult {
        let capturedRooms = usePrevious ? previousGroup : rooms
        guard !capturedRooms.isEmpty else { throw ScanImportError.empty }
        let completed = usePrevious ? previousGroupCompleted : groupCompleted
        let frameValid = usePrevious || sharedFrameValid
        let selectedFrameID = usePrevious ? previousFrameID : captureFrameID
        // Freeze the selected completed group before awaiting StructureBuilder. In particular, choosing
        // earlier rooms abandons the newer live capture; its delegate must never append into this draft.
        callbackGate.invalidate()
        callbackGeneration = callbackGate.generation
        let generation = callbackGeneration
        wantsAnotherRoom = false
        phase = .processing
        captureView?.captureSession.stop()
        sharedARSession?.pause()
        if usePrevious {
            rooms = capturedRooms; previousGroup = []
            if let selectedFrameID { captureFrameID = selectedFrameID }
            groupCompleted = completed; previousGroupCompleted = false
            previousFrameID = nil
        }
        let homeID = "home-scan-\(UUID().uuidString.prefix(8).lowercased())"
        if capturedRooms.count > 1 {
            let builder = StructureBuilder(options: [.beautifyObjects])
            let structure = try await builder.capturedStructure(from: capturedRooms)
            guard generation == callbackGeneration else { throw CancellationError() }
            var capture = RoomPlanMapping.capture(rooms: structure.rooms, sharedFrame: frameValid,
                                                  completed: completed)
            capture.coordinateFrameID = selectedFrameID
            return try ScanImport.importCapture(capture, homeID: homeID)
        }
        var capture = RoomPlanMapping.capture(rooms: capturedRooms, sharedFrame: true, completed: completed)
        capture.coordinateFrameID = selectedFrameID
        return try ScanImport.importCapture(capture, homeID: homeID)
    }
}

/// NSCoding comes from RoomCaptureViewDelegate. The controller never archives these delegates.
@objc(DryRunCaptureGenerationDelegate)
@MainActor
private final class CaptureGenerationDelegate: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    nonisolated let generation: Int
    weak var owner: RoomCaptureController?
    init(generation: Int, owner: RoomCaptureController) { self.generation = generation; self.owner = owner }
    nonisolated required init?(coder: NSCoder) { nil }
    nonisolated func encode(with coder: NSCoder) {}
    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error {
            let origin = generation
            Task { @MainActor in self.owner?.failedCapture(error.localizedDescription, generation: origin) }
            return false
        }
        return true
    }
    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        guard let error else { return }
        let origin = generation
        Task { @MainActor in self.owner?.failedCapture(error.localizedDescription, generation: origin) }
    }
    nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        let origin = generation
        Task { @MainActor in self.owner?.received(processedResult, error: error, generation: origin) }
    }
}

struct RoomCaptureContainer: UIViewRepresentable {
    let controller: RoomCaptureController
    func makeUIView(context: Context) -> UIView { controller.captureView ?? UIView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Full-screen scan flow. Calls `onFinish(nil)` on cancel or when unsupported.
struct RoomScanFlowView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let onFinish: (HomeModel?) -> Void
    @StateObject private var controller = RoomCaptureController()
    @State private var started = false
    @State private var result: ScanImportResult?
    @State private var errorText: String?
    @State private var buildGeneration = 0
    @State private var startGeneration = 0
    @State private var building = false
    @Environment(\.scenePhase) private var scenePhase

    init(onFinish: @escaping (HomeModel?) -> Void) { self.onFinish = onFinish }

    var body: some View {
        NavigationStack {
            Group {
                if !RoomCaptureSession.isSupported {
                    ContentUnavailableView {
                        Label(s("Scanning isn't available on this device"), systemImage: "camera.metering.unknown")
                    } description: {
                        Text(s("Room scanning needs a LiDAR sensor. You can build your home manually instead; every other feature works the same."))
                    } actions: {
                        Button(s("Close")) { onFinish(nil) }
                    }
                } else if let result {
                    reviewView(result)
                } else if !started {
                    intro
                } else {
                    ZStack(alignment: .bottom) {
                        RoomCaptureContainer(controller: controller).id(controller.captureGeneration).ignoresSafeArea()
                        controls.padding()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(s("Cancel")) { startGeneration += 1; buildGeneration += 1; controller.cancel(); onFinish(nil) }
                }
            }
            .alert(model.localizer("spatial.scan-problem"), isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button(s("OK"), role: .cancel) {}
            } message: { Text(errorText ?? "") }
            .onChange(of: controller.phase) { _, phase in
                if case .failed(let message) = phase { errorText = message.hasPrefix("spatial.") ? model.localizer(message) : message }
                if phase == .finished { Task { await buildResult() } }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { startGeneration += 1; buildGeneration += 1; controller.interrupted() }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(s("Scan your home")).font(.title2.bold())
            Text(s("Walk slowly through each room. Scan all rooms in one visit so they line up."))
            Label(s("The scan stays on this phone. No video or photos are saved."), systemImage: "lock")
            Label(s("A scan shows layout, not safety. You'll confirm doors and exits afterwards."), systemImage: "checkmark.seal")
            Spacer()
            Button(s("Start scanning")) {
                startGeneration += 1
                let generation = startGeneration
                Task {
                    let granted: Bool
                    if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                        granted = await AVCaptureDevice.requestAccess(for: .video)
                    } else { granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
                    guard generation == startGeneration, scenePhase != .background else { return }
                    if granted { controller.start(); started = true }
                    else { errorText = model.localizer("spatial.scan-camera-denied") }
                }
            }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private var controls: some View {
        HStack {
            if controller.phase == .finished {
                Button(s("Use saved rooms")) { Task { await buildResult() } }.buttonStyle(.borderedProminent)
            } else if controller.hasFailed {
                // The capture session ended with an error, so "Next room" and "Done" would wait for a result that
                // never comes. Offer a retry, and the rooms already saved if there are any.
                Button(s("Scan this room again")) { controller.start() }
                    .buttonStyle(.bordered)
                Spacer()
                Text(model.localizer("spatial.rooms-saved", ["count": "\(controller.rooms.count)"])).font(.footnote)
                Spacer()
                Button(s("Use saved rooms")) { Task { await buildResult() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.rooms.isEmpty)
            } else {
                if !controller.previousGroup.isEmpty {
                    Button(s("Use earlier rooms")) { Task { await buildResult(usePrevious: true) } }
                }
                Button(s("Next room")) { controller.finishRoomAndContinue() }
                    .buttonStyle(.bordered)
                Spacer()
                Text(model.localizer("spatial.rooms-saved", ["count": "\(controller.rooms.count)"])).font(.footnote)
                Spacer()
                Button(s("Done")) { controller.finishScan() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .disabled(controller.phase == .processing || building)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func reviewView(_ r: ScanImportResult) -> some View {
        List {
            FloorPlanView(home: r.home, routes: [], highlightedFloorID: nil).frame(height: 250)
            Section(s("What was captured")) {
                LabeledContent(s("Rooms"), value: "\(r.home.spaces.count)")
                LabeledContent(s("Doors and openings"), value: "\(r.home.portals.filter { $0.kind != .window }.count)")
                LabeledContent(s("Windows (not exits)"), value: "\(r.home.portals.filter { $0.kind == .window }.count)")
            }
            Section(s("Before routes can use this scan")) {
                ForEach(r.notes, id: \.self) { Text(SpatialStrings.scanImportNote($0, localizer: model.localizer)) }
            }
            Section {
                Button(s("Continue to confirmation")) { onFinish(r.home) }
            }
        }
    }

    private func buildResult(usePrevious: Bool = false) async {
        guard !building else { return }
        building = true
        buildGeneration += 1
        let generation = buildGeneration
        defer { building = false }
        do {
            let proposed = try await controller.makeProposedHome(usePrevious: usePrevious)
            guard generation == buildGeneration else { return }
            result = proposed
        } catch is CancellationError { }
        catch {
            if generation == buildGeneration {
                let message = model.localizer("spatial.scan-processing-failed", ["error": error.localizedDescription])
                controller.retainDraftAfterProcessingFailure(message)
                errorText = message
            }
        }
    }
}
