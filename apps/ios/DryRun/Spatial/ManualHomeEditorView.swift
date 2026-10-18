import SwiftUI
import DryRunCore

// Manual mode: rectangular rooms, doors on real shared walls, verified exits, markers, meeting point.
// Geometry rules live in DryRunCore.ManualLayout (tested). Every change bumps the draft revision.
// Presented inside the caller's NavigationStack. AUTHORED, NOT COMPILED in this environment.

struct ManualHomeEditorView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let onSave: (HomeModel) -> Void
    @State private var draft: HomeModel
    @State private var message: String?
    @State private var selectedID: String?
    @State private var history: [HomeModel] = []
    @State private var undoing = false
    @State private var confirmingDelete = false
    @State private var confirmingReplace = false
    @Environment(\.dismiss) private var dismiss

    // Add-room form
    @State private var roomLabel = ""
    @State private var roomKind: SpaceKind = .other
    @State private var roomWidth = 3.5
    @State private var roomDepth = 3.5
    @State private var addingRoom = false
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

    init(home: HomeModel, selectedElementID: String? = nil, onSave: @escaping (HomeModel) -> Void) {
        self.onSave = onSave
        _selectedID = State(initialValue: selectedElementID)
        _draft = State(initialValue: home)
        _anchorID = State(initialValue: home.spaces.first?.id ?? "")
        _doorFrom = State(initialValue: home.spaces.first?.id ?? "")
        _markerRoom = State(initialValue: home.spaces.first?.id ?? "")
        _meetingLabel = State(initialValue: home.meetingPoint?.label ?? "")
        _addingRoom = State(initialValue: home.spaces.isEmpty)
    }

    var body: some View {
        Group {
            if selectedID != nil { contextualEditor }
            else { overview }
        }
        .onChange(of: draft) { old, _ in
            if undoing { undoing = false } else { history.append(old) }
        }
    }

    private var overview: some View {
        Form {
            Section {
                if draft.spaces.isEmpty {
                    Text(s("Start with one room you know. Add only rooms and connections that describe your home."))
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    FloorPlanView(home: draft, routes: [], highlightedFloorID: nil, highlightedElementID: selectedID,
                                  onSelect: { selectedID = $0 }).frame(height: 280)
                    Text(s("Tap a room, opening or marker to edit it. The lists below provide the same controls.")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if draft.isFictional || draft.source == .sample {
                Section {
                    Text(s("You're editing the fictional sample home. Start your own to describe your real layout."))
                    Button(s("Start my own home")) { confirmingReplace = true }
                }
            }
            if let message {
                Section { Text(message).foregroundStyle(.orange) }
            }

            Section(s("Floor")) {
                ForEach(draft.floors) { floor in
                    Picker(floor.label, selection: Binding<ExteriorGrade>(get: {
                        draft.floors.first { $0.id == floor.id }?.exteriorGrade ?? .unknown
                    }, set: { grade in
                        draft = HomeConfirmation.apply(.floorGrade(floorID: floor.id, grade: grade), to: draft)
                    })) {
                        Text(s("Not sure")).tag(ExteriorGrade.unknown)
                        Text(s("Ground level")).tag(ExteriorGrade.ground)
                        Text(s("Above ground")).tag(ExteriorGrade.aboveGround)
                        Text(s("Below ground")).tag(ExteriorGrade.belowGround)
                        Text(s("Walkout level — exterior ground at an exit")).tag(ExteriorGrade.walkout)
                    }
                }
                Text(s("A walkout level still needs each exterior opening checked. Stairs need both landings confirmed.")).font(.footnote)
            }

            Section(s("Rooms")) {
                ForEach(draft.spaces) { space in
                    Button(space.label) { selectedID = space.id }
                }
                DisclosureGroup(s("Add a room"), isExpanded: $addingRoom) {
                Picker(s("New room type"), selection: $roomKind) {
                    ForEach(SpaceKind.allCases, id: \.self) { Text(DisplayNames.name($0.rawValue, localizer: model.localizer)).tag($0) }
                }
                TextField(s("New room name"), text: $roomLabel)
                Stepper(String(format: "Width %.1f m", roomWidth), value: $roomWidth, in: 1...15, step: 0.5)
                Stepper(String(format: "Depth %.1f m", roomDepth), value: $roomDepth, in: 1...15, step: 0.5)
                if !draft.spaces.isEmpty {
                    Picker(s("Next to"), selection: $anchorID) { roomOptions }
                    Picker(s("On which side"), selection: $side) {
                        ForEach(ManualLayout.Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
                Button(s("Add room"), systemImage: "plus.square") { addRoom() }
                    .accessibilityIdentifier("home.addRoom")
                Text(s("Sizes are estimates and are marked \"needs measurement\" until you measure them."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            }
            Section(s("Doors and openings")) {
                ForEach(draft.portals) { portal in
                    Button("\(portal.kind.rawValue.capitalized): \(portal.id)") { selectedID = portal.id }
                }
                DisclosureGroup(s("Add an opening")) {
                Picker(s("From room"), selection: $doorFrom) { roomOptions }
                Picker(s("To"), selection: $doorTo) {
                    Text(s("Outside")).tag("outside")
                    roomOptions
                }
                if doorTo == "outside" {
                    Picker(s("Outside wall"), selection: $doorSide) {
                        ForEach(ManualLayout.Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
                Picker(s("Type"), selection: $doorKind) {
                    Text(s("Door")).tag(PortalKind.door)
                    Text(s("Sliding door")).tag(PortalKind.slidingDoor)
                    Text(s("Open doorway")).tag(PortalKind.opening)
                    Text(s("Window")).tag(PortalKind.window)
                }
                TextField(s("Measured clear width in metres (optional)"), text: $doorWidthText)
                    .keyboardType(.decimalPad)
                Button(s("Add opening"), systemImage: "door.left.hand.open") { addDoor() }
            }.disabled(draft.spaces.isEmpty)

            }
            Section(s("Safety markers")) {
                ForEach(draft.annotations) { a in
                    Button("\(a.label) — \(a.spaceID.flatMap { draft.space($0)?.label } ?? "outside")") { selectedID = a.id }
                }
                .onDelete { idx in draft.edit { $0.annotations.remove(atOffsets: idx) } }
                Picker(s("Marker"), selection: $markerKind) {
                    ForEach(AnnotationKind.allCases.filter { $0 != .outsideMeetingPoint && $0 != .exteriorHydrant }, id: \.self) {
                        Text(DisplayNames.name($0.rawValue, localizer: model.localizer)).tag($0)
                    }
                }
                Picker(s("Room"), selection: $markerRoom) { roomOptions }
                Button(s("Add marker"), systemImage: "mappin.and.ellipse") { addMarker() }
            }.disabled(draft.spaces.isEmpty)

            Section(s("Outside meeting point")) {
                TextField(s("Somewhere everyone can reach, e.g. the neighbor's mailbox"), text: $meetingLabel)
                Button(s("Save meeting point")) { setMeetingPoint() }
                    .disabled(meetingLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle(s("Edit home"))
        .confirmationDialog("Replace the example layout with your own?", isPresented: $confirmingReplace) {
            Button(s("Start my own home")) { startNew() }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(s("Finish later")) { onSave(draft) } }
            ToolbarItem(placement: .topBarTrailing) { Button(s("Undo"), systemImage: "arrow.uturn.backward") {
                if let previous = history.popLast() { undoing = true; draft = previous }
            }.disabled(history.isEmpty) }
            ToolbarItem(placement: .confirmationAction) { Button(s("Save")) { onSave(draft) } }
        }
    }

    @ViewBuilder private var contextualEditor: some View {
        Form {
            FloorPlanView(home: draft, routes: [], highlightedFloorID: selectedFloorID, highlightedElementID: selectedID).frame(height: 180)
            if let index = draft.spaces.firstIndex(where: { $0.id == selectedID }) {
                TextField(s("Room name"), text: $draft.spaces[index].label)
                Picker(s("Room type"), selection: $draft.spaces[index].kind) {
                    ForEach(SpaceKind.allCases, id: \.self) { Text(DisplayNames.name($0.rawValue, localizer: model.localizer)).tag($0) }
                }
                Text(s("Layout corrections can change connections. Review doors and routes after a correction.")).font(.footnote)
                Toggle(s("Needs measurement"), isOn: $draft.spaces[index].needsMeasurement)
                Button(s("Move 25 cm east")) { moveRoom(index, delta: Vec2(0.25, 0)) }
                Button(s("Move 25 cm west")) { moveRoom(index, delta: Vec2(-0.25, 0)) }
                Button(s("Move 25 cm north")) { moveRoom(index, delta: Vec2(0, 0.25)) }
                Button(s("Move 25 cm south")) { moveRoom(index, delta: Vec2(0, -0.25)) }
                Picker(model.localizer("spatial.refuge-check"), selection: Binding<Int>(get: {
                    draft.spaces[index].higherRefugeConfirmed?.confirmedValue.map { $0 ? 1 : 0 } ?? -1
                }, set: { answer in
                    if answer < 0 { draft.spaces[index].higherRefugeConfirmed = nil }
                    else { draft = HomeConfirmation.apply(.higherRefuge(spaceID: draft.spaces[index].id, hasWayOutAndIsNotClosedAttic: answer == 1), to: draft) }
                })) { Text(s("Not sure")).tag(-1); Text(s("Yes")).tag(1); Text(s("No")).tag(0) }
                Text(model.localizer("spatial.refuge-check-note")).font(.footnote)
                Button(s("Use as interior shelter candidate")) {
                    draft = HomeConfirmation.apply(.shelterSpot(spaceID: draft.spaces[index].id, interiorNoWindows: true), to: draft)
                }
            } else if let index = draft.portals.firstIndex(where: { $0.id == selectedID }) {
                portalEditor($draft.portals[index])
                Picker(s("Leads to"), selection: Binding(get: { destinationID(draft.portals[index].sideB) }, set: { value in
                    if value == "outside" {
                        draft = HomeConfirmation.apply(.markPortalExteriorEvidence(portalID: draft.portals[index].id,
                            operable: draft.portals[index].operable.value, stepFree: draft.portals[index].stepFree.value,
                            clearWidthMeters: draft.portals[index].clearWidthMeters.value), to: draft)
                    } else {
                        draft = HomeConfirmation.apply(.assignPortalInterior(portalID: draft.portals[index].id, spaceID: value), to: draft)
                    }
                })) {
                    Text(s("Not sure")).tag("unknown"); Text(s("Outside")).tag("outside")
                    ForEach(draft.spaces.filter { $0.floorID == draft.portals[index].floorID }) { Text($0.label).tag($0.id) }
                }
                TextField(s("Measured width in metres"), text: Binding(get: { draft.portals[index].clearWidthMeters.value.map(String.init(describing:)) ?? "" }, set: { text in
                    if let width = Double(text.replacingOccurrences(of: ",", with: ".")), width > 0, width.isFinite {
                        draft.portals[index].clearWidthMeters = .confirmed(width, unit: "m")
                    }
                })).keyboardType(.decimalPad)
                if draft.portals[index].kind == .window {
                    Toggle(s("I checked this as an escape option for the person who would use it"), isOn: Binding(get: { draft.portals[index].emergencyEscapeConfirmed == true }, set: { draft.portals[index].emergencyEscapeConfirmed = $0 }))
                }
            } else if let index = draft.connectors.firstIndex(where: { $0.id == selectedID }) {
                Text(model.localizer("spatial.stair-landings-note")).font(.footnote)
                Picker(model.localizer("spatial.stair-from"), selection: $draft.connectors[index].fromSpaceID) {
                    ForEach(draft.spaces) { Text($0.label).tag($0.id) }
                }
                Picker(model.localizer("spatial.stair-to"), selection: $draft.connectors[index].toSpaceID) {
                    ForEach(draft.spaces) { Text($0.label).tag($0.id) }
                }
                Text(model.localizer("spatial.stair-points", ["from": "\(draft.connectors[index].fromPoint.x), \(draft.connectors[index].fromPoint.y)", "to": "\(draft.connectors[index].toPoint.x), \(draft.connectors[index].toPoint.y)"]))
                Button(model.localizer("spatial.stair-confirm")) {
                    let connector = draft.connectors[index]
                    if let from = draft.space(connector.fromSpaceID), let to = draft.space(connector.toSpaceID),
                       from.floorID != to.floorID, Geometry.contains(from.polygon, connector.fromPoint), Geometry.contains(to.polygon, connector.toPoint) {
                        draft = HomeConfirmation.apply(.confirmConnector(connectorID: connector.id, usable: true), to: draft)
                    } else { message = model.localizer("spatial.stair-invalid") }
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
                Button(s("Not usable"), role: .destructive) {
                    draft = HomeConfirmation.apply(.confirmConnector(connectorID: draft.connectors[index].id, usable: false), to: draft)
                }
            } else if let index = draft.annotations.firstIndex(where: { $0.id == selectedID }) {
                TextField(s("Label"), text: $draft.annotations[index].label)
                TextField(s("Finding instructions"), text: Binding(get: { draft.annotations[index].note ?? "" }, set: { draft.annotations[index].note = $0 }), axis: .vertical)
            } else if let obstacle = draft.obstacles.first(where: { $0.id == selectedID }) {
                Text(obstacle.label)
                Text(s("An obstacle stays excluded from route geometry. Remove it only if the actual obstruction is gone.")).font(.footnote)
            }
            Button(s("Remove item"), role: .destructive) { confirmingDelete = true }
        }
        .confirmationDialog("Remove this item and its room associations?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(s("Remove"), role: .destructive) { removeSelected() }
        }
        .navigationTitle(s("Selected home item"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(s("All items")) { selectedID = nil } }
            ToolbarItem(placement: .topBarTrailing) { Button(s("Undo")) {
                if let previous = history.popLast() { undoing = true; draft = previous }
            }.disabled(history.isEmpty) }
            ToolbarItem(placement: .confirmationAction) { Button(s("Save")) { draft.bumpRevision(); onSave(draft) } }
        }
    }

    private var selectedFloorID: String? {
        guard let id = selectedID else { return nil }
        return draft.space(id)?.floorID ?? draft.portal(id)?.floorID
            ?? draft.annotations.first(where: { $0.id == id })?.floorID
            ?? draft.obstacles.first(where: { $0.id == id })?.floorID
            ?? draft.connectors.first(where: { $0.id == id }).flatMap { draft.space($0.fromSpaceID)?.floorID }
    }

    private func destinationID(_ destination: PortalDestination) -> String {
        switch destination { case .space(let id): id; case .exterior: "outside"; default: "unknown" }
    }

    private func moveRoom(_ index: Int, delta: Vec2) {
        let id = draft.spaces[index].id
        let proposed = draft.spaces[index].polygon.map { $0 + delta }
        var candidate = draft; candidate.spaces[index].polygon = proposed
        guard !HomeValidator.validate(candidate).contains(where: { $0.kind == .overlappingSpaces && $0.elementID.split(separator: "|").contains(Substring(id)) }) else {
            message = "This correction would overlap another room."; return
        }
        draft.edit { home in
            home.spaces[index].polygon = proposed; home.spaces[index].needsMeasurement = true
            for portalIndex in home.portals.indices where home.portals[portalIndex].sideA == .space(id) || home.portals[portalIndex].sideB == .space(id) {
                home.portals[portalIndex].verification = .proposed
            }
        }
    }

    private func removeSelected() {
        guard let id = selectedID else { return }
        draft.edit { home in
            home.spaces.removeAll { $0.id == id }
            home.portals.removeAll { $0.id == id || $0.sideA == .space(id) || $0.sideB == .space(id) }
            home.annotations.removeAll { $0.id == id || $0.spaceID == id }
            home.obstacles.removeAll { $0.id == id }
            home.connectors.removeAll { $0.id == id || $0.fromSpaceID == id || $0.toSpaceID == id }
        }
        selectedID = nil
    }

    @ViewBuilder private var roomOptions: some View {
        ForEach(draft.spaces) { Text($0.label).tag($0.id) }
    }

    private func portalEditor(_ portal: Binding<Portal>) -> some View {
        let p = portal.wrappedValue
        let sides = [p.sideA, p.sideB].map { side -> String in
            switch side {
            case .space(let id): return draft.space(id)?.label ?? id
            case .exterior: return s("outside")
            case .commonArea: return s("building corridor")
            case .unknown: return s("unknown")
            }
        }
        return DisclosureGroup("\(DisplayNames.name(p.kind.rawValue, localizer: model.localizer)): \(sides.joined(separator: " ↔ "))") {
            Toggle(s("I checked this connection in person"), isOn: Binding(
                get: { portal.wrappedValue.verification == .verified },
                set: { portal.wrappedValue.verification = $0 ? .verified : .proposed; draft.bumpRevision() }))
            if p.kind != .opening {
                triToggle(s("Opens without keys or tools"), portal.operable)
            }
            triToggle(s("No step at the threshold"), portal.stepFree)
            if p.leadsToExterior && p.kind == .window {
                Text(s("Windows are exits only if everyone who would use it can open it and climb out, on the ground floor."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(s("Mark as not usable"), role: .destructive) {
                portal.wrappedValue.verification = .rejected; draft.bumpRevision()
            }
        }
    }

    /// Yes / No / Not sure — unknown is never silently "no".
    private func triToggle(_ title: String, _ value: Binding<EvidenceValue<Bool>>) -> some View {
        Picker(title, selection: Binding<Int>(
            get: { value.wrappedValue.value.map { $0 ? 1 : 0 } ?? -1 },
            set: { value.wrappedValue = $0 < 0 ? .unknown : .confirmed($0 == 1); draft.bumpRevision() })) {
            Text(s("Yes")).tag(1); Text(s("No")).tag(0); Text(s("Not sure")).tag(-1)
        }
    }

    private func startNew() {
        var fresh = ManualLayout.emptyHome(id: draft.id)
        fresh.revision = draft.revision + 1
        draft = fresh
        anchorID = ""; doorFrom = ""; markerRoom = ""; meetingLabel = ""
        addingRoom = true
    }

    private func addRoom() {
        do {
            let label = roomLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let room: Space
            if draft.spaces.isEmpty {
                room = try ManualLayout.addFirstRoom(to: &draft, label: label.isEmpty ? s("Room") : label,
                    kind: roomKind, width: roomWidth, depth: roomDepth)
                doorFrom = room.id; markerRoom = room.id
            } else {
                room = try ManualLayout.addRoom(to: &draft, label: label.isEmpty ? s("Room") : label,
                    kind: roomKind, width: roomWidth, depth: roomDepth, attachedTo: anchorID, side: side)
            }
            message = nil
            anchorID = room.id
        } catch { message = describe(error) }
    }

    private func addDoor() {
        // Both pickers list every room; a door from a room to itself is not a connection.
        guard doorTo != doorFrom else { message = "Choose two different rooms."; return }
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
