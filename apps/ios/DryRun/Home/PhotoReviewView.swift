import SwiftUI
import PhotosUI
import CryptoKit
import AVFoundation
import UIKit
import DryRunCore

/// Optional room-photo check. The family picks one photo; it is redrawn upright, scaled down and re-encoded as a new
/// JPEG (dropping location and camera metadata), and only those exact bytes plus a manifest are sent, after an explicit
/// per-photo consent naming Google Gemini. Possible concerns come back as proposals the family confirms, dismisses or
/// leaves unsure. Nothing found never means the room is safe. Photo bytes are kept in memory only, never saved.
struct PhotoReviewView: View {
    @Environment(AppModel.self) private var model
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: Prepared?
    @State private var roomID = ""
    @State private var consent = false
    @State private var sending = false
    @State private var operationID = UUID()
    @State private var responseKey: RevisionKey?
    @State private var responseScope: String?
    @State private var failure: String?
    @State private var response: HomeReviewBridge.Response?
    @State private var decisions: [String: ConcernDecision] = [:]

    /// The minimized photo exactly as it would be sent, with its manifest data.
    struct Prepared: Equatable {
        let bytes: Data
        let mimeType: String
        let width: Int
        let height: Int
        let transforms: [RoomImageManifest.ImageTransform]
        let image: UIImage
        let synthetic: Bool
        var digest: String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    }

    var body: some View {
        let l = model.localizer
        List {
            Section { Text(l("photo.intro")).font(.callout) }
            if let home = model.home {
                Section(l("photo.choose")) {
                    PhotosPicker(selection: $pickerItem, matching: .images) { Label(l("photo.pick"), systemImage: "photo") }
                        .accessibilityIdentifier("photo.pick")
                    if let photo {
                        Image(uiImage: photo.image).resizable().scaledToFit().frame(maxHeight: 220)
                            .overlay { boxes(photo) }
                            .accessibilityLabel(l("photo.preview"))
                        if photo.synthetic { Label(l("photo.synthetic"), systemImage: "sparkles").font(.caption) }
                        Text(l("photo.minimized", ["width": "\(photo.width)", "height": "\(photo.height)"])).font(.caption).foregroundStyle(.secondary)
                        Picker(l("photo.room"), selection: $roomID) {
                            Text(l("photo.roomUnknown")).tag("")
                            ForEach(home.spaces) { Text(HomeScenePresentation.roomLabel($0.id, in: home)).tag($0.id) }
                        }
                        Button(l("photo.discard"), role: .destructive) { discard() }.accessibilityIdentifier("photo.discard")
                    }
                }
                if photo != nil, response == nil {
                    Section {
                        Toggle(l("photo.consent"), isOn: $consent).accessibilityIdentifier("photo.consent")
                        Button { Task { await send() } } label: {
                            if sending { ProgressView() } else { Label(l("photo.send"), systemImage: "paperplane") }
                        }
                        .disabled(!consent || sending || DirectorGatewayClient.current == nil)
                        .accessibilityIdentifier("photo.send")
                        if DirectorGatewayClient.current == nil { Text(l("photo.noService")).font(.caption).foregroundStyle(.secondary) }
                        if let failure { Text(failure).font(.caption).foregroundStyle(Theme.caution) }
                    } footer: {
                        Text(l("photo.consentDetail"))
                    }
                }
                if let response { results(response) }
                links
            } else {
                Section { Text(l("photo.needsHome")) }
            }
        }
        .navigationTitle(l("photo.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in Task { await load(item) } }
        .task { loadDemoIfRequested() }
        .onDisappear { discard() }
        .onChange(of: model.scopeSessionID) { _, _ in discard() }
        .onChange(of: model.currentKey) { _, _ in discard() }
    }

    // MARK: Results

    @ViewBuilder private func results(_ response: HomeReviewBridge.Response) -> some View {
        let l = model.localizer
        let proposals = (response.reviewProposals ?? []).filter { model.aiState.concerns.shouldOffer($0) || decisions[$0.id] != nil }
        Section(l("photo.results")) {
            if proposals.isEmpty { Text(l("photo.none")).font(.callout) }
            ForEach(proposals, id: \.id) { proposal in
                let detail = response.proposal?.concerns?.first { $0.id == proposal.id }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Label(l("photo.category.\(proposal.category)"), systemImage: "exclamationmark.magnifyingglass").font(.headline)
                    if let room = proposal.roomID, let home = model.home { Text(HomeScenePresentation.roomLabel(room, in: home)).font(.caption) }
                    Text(l("photo.seen", ["evidence": proposal.visibleEvidence])).font(.callout)
                    let items = proposal.unknowns.prefix(3).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
                    Text(l("photo.couldBe", ["items": items.joined(separator: "; ")])).font(.caption).foregroundStyle(.secondary)
                    if let question = detail?.confirmationPrompt { Text(question).font(.callout.weight(.semibold)) }
                    if let decision = decisions[proposal.id] {
                        Label(l("photo.decided.\(decision.rawValue)"), systemImage: "checkmark.circle").font(.caption).foregroundStyle(Theme.accent)
                    } else {
                        AdaptiveStack {
                            ForEach([ConcernDecision.confirmed, .dismissed, .uncertain], id: \.self) { decision in
                                Button(l("photo.decision.\(decision.rawValue)")) { Task { await decide(proposal, decision) } }
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("photo.decide.\(decision.rawValue)")
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
            Text(l("photo.notSafe")).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var links: some View {
        let l = model.localizer
        let tasks = model.concernTasks
        if !tasks.isEmpty {
            Section(l("photo.linked")) {
                ForEach(tasks, id: \.id) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(l(task.actionID == "prep.clearExits" ? "photo.linkedExits" : "photo.linkedSupplies"), systemImage: "link")
                        if let room = task.roomID, let home = model.home { Text(HomeScenePresentation.roomLabel(room, in: home)).font(.caption) }
                    }
                }
                Text(l("photo.noPoints")).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("photo.linked")
        }
    }

    /// Boxes are drawn on the exact submitted image (image space only; nothing is projected into the floor plan).
    @ViewBuilder private func boxes(_ photo: Prepared) -> some View {
        if let proposals = response?.reviewProposals {
            GeometryReader { geo in
                let fitted = AVMakeRect(aspectRatio: CGSize(width: photo.width, height: photo.height), insideRect: CGRect(origin: .zero, size: geo.size))
                ForEach(proposals, id: \.id) { p in
                    if p.box.count == 4 {
                        Rectangle().stroke(Theme.caution, lineWidth: 3)
                            .frame(width: (p.box[3] - p.box[1]) * fitted.width, height: (p.box[2] - p.box[0]) * fitted.height)
                            .position(x: fitted.minX + (p.box[1] + p.box[3]) / 2 * fitted.width, y: fitted.minY + (p.box[0] + p.box[2]) / 2 * fitted.height)
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: Actions

    private func decide(_ proposal: HomeConcernProposal, _ decision: ConcernDecision) async {
        guard let photo, let home = model.home, responseKey == model.currentKey, responseScope == model.scopeSessionID else { return }
        if await model.reviewConcern(proposal, decision: decision, manifest: manifest(photo, home: home)) { decisions[proposal.id] = decision }
    }

    private func manifest(_ photo: Prepared, home: HomeModel) -> RoomImageManifest {
        RoomImageManifest(id: "photo-\(photo.digest.prefix(12))", homeRevision: home.revision, roomID: roomID.isEmpty ? nil : roomID,
                          digest: photo.digest, capturedAt: capturedAt, width: photo.width, height: photo.height, orientation: "up",
                          calibration: "none", transforms: photo.transforms, redactedRegions: [])
    }

    @State private var capturedAt = Date()

    private func send() async {
        guard let photo, let home = model.home, let household = model.household, let rubric = model.rubric,
              household.isFictional, consent, let client = DirectorGatewayClient.current else { return }
        let operation = UUID(), key = model.currentKey, scope = model.scopeSessionID
        let locale = model.locale, stateBytes = model.integratedAIState
        operationID = operation
        sending = true; failure = nil
        defer { if operationID == operation { sending = false } }
        do {
            await model.refreshScorecard(force: true)
            guard operationID == operation, model.currentKey == key, model.scopeSessionID == scope,
                  model.locale == locale, model.integratedAIState == stateBytes, !Task.isCancelled else { return }
            let request = try HomeReviewBridge.request(requestID: "photo-\(UUID().uuidString)", household: household, home: home, rubric: rubric,
                                                       manifest: manifest(photo, home: home), bytes: photo.bytes, mimeType: photo.mimeType,
                                                       state: model.aiState, places: model.savedPlaces, scopeSessionID: scope,
                                                       locale: locale, currentScorecard: model.currentHostScorecard)
            let result = await client.reviewPhoto(request)
            guard operationID == operation, model.currentKey == key, model.scopeSessionID == scope,
                  model.locale == locale, model.integratedAIState == stateBytes, !Task.isCancelled else { return }
            switch result {
            case .reviewed(let result): response = result; responseKey = key; responseScope = scope
            case .unavailable: failure = model.localizer("photo.failed")
            }
        } catch {
            guard operationID == operation, model.currentKey == key, model.scopeSessionID == scope else { return }
            failure = model.localizer("photo.failed")
        }
    }

    private func discard() {
        operationID = UUID(); sending = false; responseKey = nil; responseScope = nil
        photo = nil; pickerItem = nil; response = nil; decisions = [:]; consent = false; failure = nil
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        discard()
        let operation = operationID, key = model.currentKey, scope = model.scopeSessionID
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
              operationID == operation, model.currentKey == key, model.scopeSessionID == scope, !Task.isCancelled else { return }
        response = nil; decisions = [:]; consent = false; capturedAt = Date()
        photo = Self.minimize(image)
    }

    /// DEBUG only: the repository's synthetic doorway test image, so development never uploads a real room.
    private func loadDemoIfRequested() {
        #if DEBUG
        guard photo == nil, ProcessInfo.processInfo.arguments.contains("-demoReviewPhoto"),
              let root = try? ContentLocator.contentRoot(),
              let data = try? Data(contentsOf: root.appendingPathComponent("ai/demo/synthetic-obstructed-doorway.png")),
              let image = UIImage(data: data) else { return }
        photo = Prepared(bytes: data, mimeType: "image/png", width: Int(image.size.width * image.scale), height: Int(image.size.height * image.scale),
                         transforms: [], image: image, synthetic: true)
        roomID = model.home?.spaces.first { $0.id == "sp-living" }?.id ?? ""
        #endif
    }

    /// Upright, at most 1600 px on the long side, re-encoded as JPEG under 1 MB. Rotation and resize are recorded.
    static func minimize(_ image: UIImage) -> Prepared? {
        var transforms: [RoomImageManifest.ImageTransform] = []
        let degrees: Double? = switch image.imageOrientation {
        case .right, .rightMirrored: 90
        case .down, .downMirrored: 180
        case .left, .leftMirrored: 270
        default: nil
        }
        if let degrees { transforms.append(.init(kind: "rotate", values: [degrees])) }
        let pixel = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let scale = min(1, 1600 / max(pixel.width, pixel.height))
        let target = CGSize(width: (pixel.width * scale).rounded(), height: (pixel.height * scale).rounded())
        if scale < 1 { transforms.append(.init(kind: "resize", values: [target.width, target.height])) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        for quality in [0.75, 0.6, 0.45, 0.3] {
            if let data = drawn.jpegData(compressionQuality: quality), data.count <= HomeReviewBridge.maxImageBytes {
                return Prepared(bytes: data, mimeType: "image/jpeg", width: Int(target.width), height: Int(target.height),
                                transforms: transforms, image: drawn, synthetic: false)
            }
        }
        return nil
    }
}
