import SwiftUI
import DryRunCore

// Manual mode: rectangular rooms, doors on real shared walls, verified exits, markers, meeting point.
// Geometry rules live in DryRunCore.ManualLayout (tested). Every change bumps the draft revision.
// Presented inside the caller's NavigationStack. AUTHORED, NOT COMPILED in this environment.

struct ManualHomeEditorView: View {
    let onSave: (HomeModel) -> Void
    @State private var draft: HomeModel
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    // Add-room form
    @State private var roomLabel = "Bedroom"
    @State private var roomKind: SpaceKind = .bedroom
    @State private var roomWidth = 3.5
    @State private var roomDepth = 3.5
    @State private var anchorID = ""
    @State private var side: ManualLayout.Side = .north

    // Add-door form
    @State private var doorFrom = ""
    @State private var doorTo = "outside"
    @State private var doorSide: ManualLayout.Side = .south
    @State private var doorKind: PortalKind = .door
    @State private var doorWidthText = ""

    // Add-marker form
    @State private var markerKind: AnnotationKind = .smokeAlarm
    @State private var markerRoom = ""
    @State private var meetingLabel = ""

    init(home: HomeModel, onSave: @escaping (HomeModel) -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: home)
        _anchorID = State(initialValue: home.spaces.first?.id ?? "")
        _doorFrom = State(initialValue: home.spaces.first?.id ?? "")
        _markerRoom = State(initialValue: home.spaces.first?.id ?? "")
        _meetingLabel = State(initialValue: home.meetingPoint?.label ?? "")
    }

    var body: some View {
        Form {
            if draft.isFictional || draft.source == .sample {
                Section {
                    Text("You're editing the fictional sample home. Start your own to describe your real layout.")
                    Button("Start my own home") { startNew() }
                }
            }
            if let message {
                Section { Text(message).foregroundStyle(.orange) }
            }

            Section("Rooms") {
                ForEach($draft.spaces) { $space in
                    TextField("Room name", text: $space.label)
                        .onChange(of: space.label) { _, _ in space.labelConfirmed = true; draft.bumpRevision() }
                }
                Picker("New room type", selection: $roomKind) {
                    ForEach(SpaceKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("New room name", text: $roomLabel)
                Stepper(String(format: "Width %.1f m", roomWidth), value: $roomWidth, in: 1...15, step: 0.5)
                Stepper(String(format: "Depth %.1f m", roomDepth), value: $roomDepth, in: 1...15, step: 0.5)
                Picker("Next to", selection: $anchorID) { roomOptions }
                Picker("On which side", selection: $side) {
                    ForEach(ManualLayout.Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Button("Add room", systemImage: "plus.square") { addRoom() }
                Text("Sizes are estimates and are marked \"needs measurement\" until you measure them.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Doors and openings") {
                ForEach($draft.portals) { $portal in
                    portalEditor($portal)
                }
                Picker("From room", selection: $doorFrom) { roomOptions }
                Picker("To", selection: $doorTo) {
                    Text("Outside").tag("outside")
                    roomOptions
                }
                if doorTo == "outside" {
                    Picker("Outside wall", selection: $doorSide) {
                        ForEach(ManualLayout.Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
                Picker("Type", selection: $doorKind) {
                    Text("Door").tag(PortalKind.door)
                    Text("Sliding door").tag(PortalKind.slidingDoor)
                    Text("Open doorway").tag(PortalKind.opening)
                    Text("Window").tag(PortalKind.window)
                }
                TextField("Measured clear width in metres (optional)", text: $doorWidthText)
                    .keyboardType(.decimalPad)
                Button("Add opening", systemImage: "door.left.hand.open") { addDoor() }
            }

            Section("Safety markers") {
                ForEach(draft.annotations) { a in
                    Text("\(a.label) — \(a.spaceID.flatMap { draft.space($0)?.label } ?? "outside")")
                }
                .onDelete { idx in draft.edit { $0.annotations.remove(atOffsets: idx) } }
                Picker("Marker", selection: $markerKind) {
                    ForEach(AnnotationKind.allCases.filter { $0 != .outsideMeetingPoint && $0 != .exteriorHydrant }, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                Picker("Room", selection: $markerRoom) { roomOptions }
                Button("Add marker", systemImage: "mappin.and.ellipse") { addMarker() }
            }

            Section("Outside meeting point") {
                TextField("Somewhere everyone can reach, e.g. the neighbor's mailbox", text: $meetingLabel)
                Button("Save meeting point") { setMeetingPoint() }
                    .disabled(meetingLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Edit home")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(draft) } }
        }
    }

    @ViewBuilder private var roomOptions: some View {
        ForEach(draft.spaces) { Text($0.label).tag($0.id) }
    }

    private func portalEditor(_ portal: Binding<Portal>) -> some View {
        let p = portal.wrappedValue
        let sides = [p.sideA, p.sideB].map { side -> String in
            switch side {
            case .space(let id): return draft.space(id)?.label ?? id
            case .exterior: return "outside"
            case .commonArea: return "building corridor"
            case .unknown: return "unknown"
            }
        }
        return DisclosureGroup("\(p.kind.rawValue.capitalized): \(sides.joined(separator: " ↔ "))") {
            Toggle("I checked this connection in person", isOn: Binding(
                get: { portal.wrappedValue.verification == .verified },
                set: { portal.wrappedValue.verification = $0 ? .verified : .proposed; draft.bumpRevision() }))
            if p.kind != .opening {
                triToggle("Opens without keys or tools", portal.operable)
            }
            triToggle("No step at the threshold", portal.stepFree)
            if p.leadsToExterior && p.kind == .window {
                Text("Windows are exits only if everyone who would use it can open it and climb out, on the ground floor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Mark as not usable", role: .destructive) {
                portal.wrappedValue.verification = .rejected; draft.bumpRevision()
            }
        }
    }

    /// Yes / No / Not sure — unknown is never silently "no".
    private func triToggle(_ title: String, _ value: Binding<EvidenceValue<Bool>>) -> some View {
        Picker(title, selection: Binding<Int>(
            get: { value.wrappedValue.value.map { $0 ? 1 : 0 } ?? -1 },
            set: { value.wrappedValue = $0 < 0 ? .unknown : .confirmed($0 == 1); draft.bumpRevision() })) {
            Text("Yes").tag(1); Text("No").tag(0); Text("Not sure").tag(-1)
        }
    }

    private func startNew() {
        var fresh = ManualLayout.newHome(id: "home-\(UUID().uuidString.prefix(8).lowercased())")
        fresh.revision = draft.revision + 1
        draft = fresh
        anchorID = "sp-1"; doorFrom = "sp-1"; markerRoom = "sp-1"; meetingLabel = ""
    }

    private func addRoom() {
        do {
            let s = try ManualLayout.addRoom(to: &draft, label: roomLabel, kind: roomKind, width: roomWidth, depth: roomDepth,
                                             attachedTo: anchorID, side: side)
            message = nil
            anchorID = s.id
        } catch { message = describe(error) }
    }

    private func addDoor() {
        let width = Double(doorWidthText.replacingOccurrences(of: ",", with: "."))
        do {
            try ManualLayout.addPortal(to: &draft, kind: doorKind, from: doorFrom,
                                       to: doorTo == "outside" ? .exterior : .space(doorTo),
                                       exteriorSide: doorTo == "outside" ? doorSide : nil,
                                       width: width ?? (doorKind == .opening ? 1.0 : 0.8), widthMeasured: width != nil)
            message = "Added. Open it in the list above to confirm it."
        } catch { message = describe(error) }
    }

    private func addMarker() {
        guard let space = draft.space(markerRoom) else { return }
        draft.edit { h in
            h.annotations.append(Annotation(id: "an-\(UUID().uuidString.prefix(6).lowercased())", kind: markerKind, floorID: space.floorID,
                                            spaceID: space.id, position: Geometry.centroid(space.polygon),
                                            label: markerKind.rawValue, verification: .verified))
        }
    }

    private func setMeetingPoint() {
        draft.edit { h in
            h.annotations.removeAll { $0.kind == .outsideMeetingPoint }
            h.annotations.append(Annotation(id: "an-meeting", kind: .outsideMeetingPoint, floorID: h.floors.first?.id,
                                            label: meetingLabel, verification: .verified))
        }
    }

    private func describe(_ error: Error) -> String {
        switch error as? ManualLayout.LayoutError {
        case .overlapsExistingRoom: return "That room would overlap another room. Choose a different side."
        case .noSharedWall: return "Those rooms don't share a wall, so a door can't connect them."
        case .sideNotExterior: return "That wall is shared with another room. Pick an outside wall."
        case .wallTooShort: return "That wall is too short for this opening."
        case .invalidSize: return "Room size is too small."
        case .unknownSpace: return "Choose a room first."
        case nil: return error.localizedDescription
        }
    }
}
