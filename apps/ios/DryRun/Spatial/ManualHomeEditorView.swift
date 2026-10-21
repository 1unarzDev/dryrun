import SwiftUI
import DryRunCore

// Manual mode: rectangular rooms, doors on real shared walls, verified exits, markers, meeting point.
// Geometry rules live in DryRunCore.ManualLayout (tested). Every change bumps the draft revision.
// Presented inside the caller's NavigationStack; persistence remains with AppModel.

struct ManualHomeEditorView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let onSave: @MainActor (HomeModel, Int?, String) async -> Bool
    @State private var baseRevision: Int?
    @State private var savedScopeSessionID: String
    @State private var saving = false
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
    @State private var roomFloorID = ""
    @State private var newFloorLabel = ""
    @State private var newFloorOrder = 1
    @State private var newFloorElevation = ""
    @State private var landingPreviewTo = false
    @State private var landingFromRoom = ""
    @State private var landingToRoom = ""
    @State private var landingFromX = ""
    @State private var landingFromY = ""
    @State private var landingToX = ""
    @State private var landingToY = ""
    @State private var correctionFromRoom = ""
    @State private var correctionToRoom = "outside"
    @State private var correctionSide: ManualLayout.Side?

    // Add-door form
    @State private var doorFrom = ""
    @State private var doorTo = "outside"
    @State private var doorSide: ManualLayout.Side = .south
    @State private var doorKind: PortalKind = .door
    @State private var doorWidthText = ""

    // Add-marker form
    @State private var markerKind: AnnotationKind = .smokeAlarm
    @State private var markerRoom = ""
    @State private var markerEditRoom = ""
    @State private var markerX = ""
    @State private var markerY = ""
    @State private var markerLocationChecked = false
    @State private var meetingLabel = ""

    init(home: HomeModel, selectedElementID: String? = nil, savedBaseRevision: Int?, scopeSessionID: String, onSave: @escaping @MainActor (HomeModel, Int?, String) async -> Bool) {
        self.onSave = onSave
        _baseRevision = State(initialValue: savedBaseRevision)
        _savedScopeSessionID = State(initialValue: scopeSessionID)
        _selectedID = State(initialValue: selectedElementID)
        _draft = State(initialValue: home)
        _anchorID = State(initialValue: home.spaces.first?.id ?? "")
        _roomFloorID = State(initialValue: home.floors.first?.id ?? "")
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
            if undoing { undoing = false; resetContext() } else { history.append(old) }
        }
        .disabled(saving)
        .interactiveDismissDisabled(saving)
        .onAppear { resetContext() }
        .onChange(of: selectedID) { _, _ in resetContext() }
        .onChange(of: roomFloorID) { _, id in anchorID = draft.spaces.first(where: { $0.floorID == id })?.id ?? "" }
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
            ScanCorrectionSection(draft: $draft)
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
                    TextField(model.localizer("spatial.level-name"), text: Binding(get: {
                        draft.floors.first(where: { $0.id == floor.id })?.label ?? ""
                    }, set: { name in
                        guard let index = draft.floors.firstIndex(where: { $0.id == floor.id }) else { return }
                        draft.edit { $0.floors[index].label = name }
                    }))
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
                DisclosureGroup(model.localizer("spatial.add-level")) {
                    TextField(model.localizer("spatial.level-name"), text: $newFloorLabel)
                    Stepper(model.localizer("spatial.level-order", ["order": String(newFloorOrder)]), value: $newFloorOrder, in: -10...100)
                    TextField(model.localizer("spatial.level-elevation"), text: $newFloorElevation).keyboardType(.numbersAndPunctuation)
                    Text(model.localizer("spatial.level-note")).font(.footnote)
                    Button(model.localizer("spatial.save-level")) { addFloor() }
                        .accessibilityIdentifier("home.addFloor")
                }
            }

            Section(s("Rooms")) {
                ForEach(draft.spaces) { space in
                    Button(roomFloorLabel(space)) { selectedID = space.id }
                        .accessibilityIdentifier("home.editRoom.\(space.id)")
                }
                DisclosureGroup(s("Add a room"), isExpanded: $addingRoom) {
                if draft.floors.count > 1 {
                    Picker(s("Floor"), selection: $roomFloorID) {
                        ForEach(draft.floors) { Text($0.label).tag($0.id) }
                    }
                }
                Picker(s("New room type"), selection: $roomKind) {
                    ForEach(SpaceKind.allCases, id: \.self) { Text(DisplayNames.name($0.rawValue, localizer: model.localizer)).tag($0) }
                }
                TextField(s("New room name"), text: $roomLabel)
                if draft.spaces.contains(where: { $0.floorID == roomFloorID }) {
                    Picker(s("Next to"), selection: $anchorID) {
                        ForEach(draft.spaces.filter { $0.floorID == roomFloorID }) { Text($0.label).tag($0.id) }
                    }
                    Picker(s("On which side"), selection: $side) {
                        ForEach(ManualLayout.Side.allCases, id: \.self) { Text(model.localizer("spatial.side.\($0.rawValue)")).tag($0) }
                    }
                }
                Button(s("Add room"), systemImage: "plus.square") { addRoom() }
                    .accessibilityIdentifier("home.addRoom")
            }

            }
            Section(s("Doors and openings")) {
                ForEach(draft.portals) { portal in
                    Button(openingLabel(portal)) { selectedID = portal.id }
                        .accessibilityIdentifier("home.editOpening.\(portal.id)")
                }
                DisclosureGroup(s("Add an opening")) {
                Picker(s("From room"), selection: $doorFrom) { roomOptions }
                Picker(s("To"), selection: $doorTo) {
                    Text(s("Outside")).tag("outside")
                    roomOptions
                }
                if doorTo == "outside" {
                    Picker(s("Outside wall"), selection: $doorSide) {
                        ForEach(ManualLayout.Side.allCases, id: \.self) { Text(model.localizer("spatial.side.\($0.rawValue)")).tag($0) }
                    }
                }
                Picker(s("Type"), selection: $doorKind) {
                    Text(s("Door")).tag(PortalKind.door)
                    Text(s("Sliding door")).tag(PortalKind.slidingDoor)
                    Text(s("Open doorway")).tag(PortalKind.opening)
                    Text(s("Window")).tag(PortalKind.window)
                }
                Button(s("Add opening"), systemImage: "door.left.hand.open") { addDoor() }
            }.disabled(draft.spaces.isEmpty)

            }
            if draft.floors.count > 1 || !draft.connectors.isEmpty {
                Section(s("Stairs and floor connections")) {
                    ForEach(draft.connectors) { connector in
                        Button("\(draft.space(connector.fromSpaceID)?.label ?? connector.fromSpaceID) ↔ \(draft.space(connector.toSpaceID)?.label ?? connector.toSpaceID)") {
                            selectedID = connector.id
                        }
                    }
                    DisclosureGroup(model.localizer("spatial.add-stairs")) {
                        landingInputFields
                        Text(model.localizer("spatial.new-stairs-note")).font(.footnote)
                        Button(model.localizer("spatial.save-stairs")) { addStairs() }
                            .accessibilityIdentifier("home.addStairs")
                    }.disabled(draft.floors.count < 2)
                }
            }
            Section(s("Safety markers")) {
                ForEach(draft.annotations) { a in
                    Button("\(a.localizedLabel(model.localizer)) — \(a.spaceID.flatMap { id in draft.space(id).map { HomeScenePresentation.roomLabel($0.id, in: draft) } } ?? s("outside"))") { selectedID = a.id }
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
        .confirmationDialog(model.localizer("spatial.replace-layout"), isPresented: $confirmingReplace) {
            Button(s("Start my own home")) { startNew() }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(s("Cancel")) { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) { Button(s("Undo"), systemImage: "arrow.uturn.backward") {
                if let previous = history.popLast() { undoing = true; draft = previous }
            }.disabled(history.isEmpty) }
            ToolbarItem(placement: .confirmationAction) { Button(s("Save")) { save() }.accessibilityIdentifier("home.save") }
        }
    }

    @ViewBuilder private var contextualEditor: some View {
        Form {
            FloorPlanView(home: draft, routes: [], highlightedFloorID: selectedFloorID, highlightedElementID: selectedID,
                          onSelect: { id in if applyPendingMarkerPlacement() { selectedID = id } }).frame(height: 180)
            if let index = draft.spaces.firstIndex(where: { $0.id == selectedID }) {
                TextField(s("Room name"), text: $draft.spaces[index].label)
                    .accessibilityIdentifier("home.roomName")
                Picker(s("Room type"), selection: $draft.spaces[index].kind) {
                    ForEach(SpaceKind.allCases, id: \.self) { Text(DisplayNames.name($0.rawValue, localizer: model.localizer)).tag($0) }
                }
                Picker(model.localizer("spatial.refuge-check"), selection: Binding<Int>(get: {
                    draft.spaces[index].higherRefugeConfirmed?.confirmedValue.map { $0 ? 1 : 0 } ?? -1
                }, set: { answer in
                    if answer < 0 { draft.spaces[index].higherRefugeConfirmed = nil }
                    else { draft = HomeConfirmation.apply(.higherRefuge(spaceID: draft.spaces[index].id, hasWayOutAndIsNotClosedAttic: answer == 1), to: draft) }
                })) { Text(s("Not sure")).tag(-1); Text(s("Yes")).tag(1); Text(s("No")).tag(0) }
                Text(model.localizer("spatial.refuge-check-note")).font(.footnote)
                Picker(model.localizer("spatial.shelter-question"), selection: Binding<Int>(get: {
                    draft.spaces[index].interiorNoWindowsConfirmed.confirmedValue.map { $0 ? 1 : 0 } ?? -1
                }, set: { answer in
                    let roomID = draft.spaces[index].id
                    if answer < 0 {
                        draft.edit { h in
                            h.spaces[index].interiorNoWindowsConfirmed = .unknown
                            h.annotations.removeAll { $0.kind == .tornadoShelterCandidate && $0.spaceID == roomID }
                        }
                    } else {
                        draft = HomeConfirmation.apply(.shelterSpot(spaceID: roomID, interiorNoWindows: answer == 1), to: draft)
                    }
                })) { Text(s("Not sure")).tag(-1); Text(s("Yes")).tag(1); Text(s("No")).tag(0) }
                .disabled(model.household?.housing.homeType == .manufacturedHome)
                if model.household?.housing.homeType == .manufacturedHome {
                    Text(model.localizer("plan.shelter.manufactured")).font(.footnote)
                }
            } else if let index = draft.portals.firstIndex(where: { $0.id == selectedID }) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(s("Type")).font(.headline)
                    ForEach([[PortalKind.door, .window], [.slidingDoor, .opening]], id: \.self) { row in
                        HStack(spacing: Theme.Space.s) {
                            ForEach(row, id: \.self) { kind in
                                let selected = draft.portals[index].kind == kind
                                Button {
                                    try? HomeGeometryEditor.reclassifyOpening(in: &draft, portalID: draft.portals[index].id, kind: kind)
                                } label: {
                                    HStack {
                                        Text(s(kind == .door ? "Door" : kind == .window ? "Window" : kind == .slidingDoor ? "Sliding door" : "Open doorway"))
                                            .fixedSize(horizontal: false, vertical: true)
                                        if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                                    }
                                }
                                .buttonStyle(ChoiceButtonStyle(selected: selected))
                                .accessibilityAddTraits(selected ? .isSelected : [])
                                .accessibilityIdentifier("home.opening.type.\(kind.rawValue)")
                            }
                        }
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("home.opening.type")
                portalEditor($draft.portals[index])
                openingPlacementEditor(index)
                if draft.portals[index].kind == .window {
                    Text(model.localizer("spatial.window-person-question")).font(.subheadline)
                    Text(model.localizer("spatial.window-person-note")).font(.footnote)
                    ForEach(model.household?.people ?? []) { person in
                        Toggle(person.localizedLabel(model.localizer), isOn: Binding(get: {
                            draft.portals[index].emergencyEscapePersonIDs?.contains(person.id) == true
                        }, set: { checked in
                            var people = Set(draft.portals[index].emergencyEscapePersonIDs ?? [])
                            if checked { people.insert(person.id) } else { people.remove(person.id) }
                            draft.portals[index].emergencyEscapePersonIDs = people.sorted()
                        }))
                    }
                }
            } else if let index = draft.connectors.firstIndex(where: { $0.id == selectedID }) {
                landingEditor(index)
            } else if let index = draft.annotations.firstIndex(where: { $0.id == selectedID }) {
                TextField(s("Label"), text: $draft.annotations[index].label)
                TextField(s("Finding instructions"), text: Binding(get: { draft.annotations[index].note ?? "" }, set: { draft.annotations[index].note = $0 }), axis: .vertical)
                if draft.annotations[index].kind != .outsideMeetingPoint && draft.annotations[index].kind != .exteriorHydrant {
                    markerPlacementEditor(index)
                }
            } else if let obstacle = draft.obstacles.first(where: { $0.id == selectedID }) {
                Text(obstacle.label)
                Text(s("An obstacle stays excluded from route geometry. Remove it only if the actual obstruction is gone.")).font(.footnote)
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
            Button(s("Remove item"), role: .destructive) { confirmingDelete = true }
        }
        .confirmationDialog(model.localizer("spatial.remove-item-confirm"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(s("Remove"), role: .destructive) { removeSelected() }
        }
        .navigationTitle(s("Edit home"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(s("All items")) { if applyPendingMarkerPlacement() { selectedID = nil } }.accessibilityIdentifier("home.allItems") }
            ToolbarItem(placement: .topBarTrailing) { Button(s("Undo")) {
                if let previous = history.popLast() { undoing = true; draft = previous }
            }.disabled(history.isEmpty) }
            ToolbarItem(placement: .confirmationAction) { Button(s("Save")) { save() }.accessibilityIdentifier("home.save") }
        }
    }

    private func save() {
        guard !saving, applyPendingMarkerPlacement() else { return }
        saving = true
        var candidate = draft
        candidate.bumpRevision()
        Task { @MainActor in
            let saved = await onSave(candidate, baseRevision, savedScopeSessionID)
            saving = false
            if saved { dismiss() }
            else { message = s("Could not save this home. Your edits are still here. Retry, or cancel and reopen the latest home.") }
        }
    }

    private var selectedFloorID: String? {
        guard let id = selectedID else { return nil }
        return draft.space(id)?.floorID ?? draft.portal(id)?.floorID
            ?? draft.annotations.first(where: { $0.id == id })?.floorID
            ?? draft.obstacles.first(where: { $0.id == id })?.floorID
            ?? draft.connectors.first(where: { $0.id == id }).flatMap { draft.space(landingPreviewTo ? $0.toSpaceID : $0.fromSpaceID)?.floorID }
    }

    private func destinationID(_ destination: PortalDestination) -> String {
        switch destination { case .space(let id): id; case .exterior: "outside"; case .commonArea: "common"; default: "unknown" }
    }

    private func resetContext() {
        message = nil
        landingPreviewTo = false
        correctionSide = nil
        correctionFromRoom = ""; correctionToRoom = "unknown"
        if let marker = draft.annotations.first(where: { $0.id == selectedID }) {
            markerEditRoom = marker.spaceID ?? ""
            markerX = marker.position.map { String($0.x) } ?? ""
            markerY = marker.position.map { String($0.y) } ?? ""
            markerLocationChecked = marker.verification == .verified
        } else {
            markerEditRoom = ""; markerX = ""; markerY = ""; markerLocationChecked = false
        }
        if let connector = draft.connectors.first(where: { $0.id == selectedID }) {
            landingFromRoom = connector.fromSpaceID; landingToRoom = connector.toSpaceID
            landingFromX = String(connector.fromPoint.x); landingFromY = String(connector.fromPoint.y)
            landingToX = String(connector.toPoint.x); landingToY = String(connector.toPoint.y)
        } else {
            landingFromRoom = ""; landingToRoom = ""
            landingFromX = ""; landingFromY = ""; landingToX = ""; landingToY = ""
        }
        if let opening = draft.portals.first(where: { $0.id == selectedID }) {
            let first = [opening.sideA, opening.sideB].compactMap { if case .space(let id) = $0 { return id }; return nil }.first
            correctionFromRoom = first ?? draft.spaces.first?.id ?? ""
            let other = opening.sideA == .space(correctionFromRoom) ? opening.sideB : opening.sideA
            correctionToRoom = destinationID(other)
        }
    }

    private func decimal(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")).flatMap { $0.isFinite ? $0 : nil }
    }

    private func roomFloorLabel(_ room: Space) -> String {
        "\(room.label) · \(draft.floors.first(where: { $0.id == room.floorID })?.label ?? room.floorID)"
    }

    private func openingLabel(_ opening: Portal) -> String {
        let rooms = [opening.sideA, opening.sideB].map { side in
            switch side {
            case .space(let id): draft.space(id).map { HomeScenePresentation.roomLabel($0.id, in: draft) } ?? s("unknown")
            case .exterior: s("outside")
            case .commonArea: s("building corridor")
            case .unknown: s("unknown")
            }
        }
        let ordinal = (draft.portals.firstIndex(where: { $0.id == opening.id }) ?? 0) + 1
        return "\(ordinal). \(DisplayNames.name(opening.kind.rawValue, localizer: model.localizer)) · \(rooms.joined(separator: " ↔ "))"
    }

    @ViewBuilder private func openingPlacementEditor(_ index: Int) -> some View {
        DisclosureGroup(model.localizer("spatial.correct-opening")) {
            Picker(s("From room"), selection: $correctionFromRoom) { roomOptions }
            Picker(s("Leads to"), selection: $correctionToRoom) {
                Text(s("Not sure")).tag("unknown")
                Text(s("Outside")).tag("outside")
                Text(s("building corridor")).tag("common")
                ForEach(draft.spaces.filter { $0.id != correctionFromRoom }) { Text(HomeScenePresentation.roomLabel($0.id, in: draft)).tag($0.id) }
            }
            if correctionToRoom == "outside" || correctionToRoom == "common" {
                Picker(s("Outside wall"), selection: $correctionSide) {
                    Text(s("Choose")).tag(ManualLayout.Side?.none)
                    ForEach(ManualLayout.Side.allCases, id: \.self) { Text(model.localizer("spatial.side.\($0.rawValue)")).tag(Optional($0)) }
                }
            }
            Button(model.localizer("spatial.place-opening")) {
                let destination: PortalDestination = correctionToRoom == "outside" ? .exterior
                    : correctionToRoom == "common" ? .commonArea(s("building corridor")) : .space(correctionToRoom)
                do {
                    try HomeGeometryEditor.placeOpening(in: &draft, portalID: draft.portals[index].id,
                        from: correctionFromRoom, to: destination, exteriorSide: correctionSide)
                    message = nil
                } catch { message = describe(error) }
            }.disabled(correctionToRoom == "unknown" || correctionFromRoom.isEmpty || ((correctionToRoom == "outside" || correctionToRoom == "common") && correctionSide == nil))
            Text(model.localizer("spatial.opening-placement-note")).font(.footnote)
        }
    }

    private func landingInputsMatch(_ connector: FloorConnector) -> Bool {
        landingFromRoom == connector.fromSpaceID && landingToRoom == connector.toSpaceID
            && decimal(landingFromX) == connector.fromPoint.x && decimal(landingFromY) == connector.fromPoint.y
            && decimal(landingToX) == connector.toPoint.x && decimal(landingToY) == connector.toPoint.y
    }

    @ViewBuilder private var landingInputFields: some View {
        Picker(model.localizer("spatial.stair-from"), selection: $landingFromRoom) {
            Text(s("Choose a room")).tag("")
            ForEach(draft.spaces) { Text(roomFloorLabel($0)).tag($0.id) }
        }
        TextField(model.localizer("spatial.landing-from-x"), text: $landingFromX).keyboardType(.numbersAndPunctuation)
        TextField(model.localizer("spatial.landing-from-y"), text: $landingFromY).keyboardType(.numbersAndPunctuation)
        Picker(model.localizer("spatial.stair-to"), selection: $landingToRoom) {
            Text(s("Choose a room")).tag("")
            ForEach(draft.spaces) { Text(roomFloorLabel($0)).tag($0.id) }
        }
        TextField(model.localizer("spatial.landing-to-x"), text: $landingToX).keyboardType(.numbersAndPunctuation)
        TextField(model.localizer("spatial.landing-to-y"), text: $landingToY).keyboardType(.numbersAndPunctuation)
    }

    @ViewBuilder private func landingEditor(_ index: Int) -> some View {
        let connector = draft.connectors[index]
        Picker(model.localizer("spatial.landing-preview"), selection: $landingPreviewTo) {
            Text(model.localizer("spatial.stair-from")).tag(false)
            Text(model.localizer("spatial.stair-to")).tag(true)
        }.pickerStyle(.segmented)
        Text(model.localizer("spatial.stair-landings-note")).font(.footnote)
        landingInputFields
        Button(model.localizer("spatial.apply-landings")) {
            guard let fx = decimal(landingFromX), let fy = decimal(landingFromY),
                  let tx = decimal(landingToX), let ty = decimal(landingToY) else {
                message = model.localizer("spatial.stair-invalid"); return
            }
            do {
                try HomeGeometryEditor.correctLandings(in: &draft, connectorID: connector.id,
                    fromRoomID: landingFromRoom, fromPoint: Vec2(fx, fy), toRoomID: landingToRoom, toPoint: Vec2(tx, ty))
                message = nil
            } catch { message = describe(error) }
        }.accessibilityIdentifier("home.correctLandings")
        Button(model.localizer("spatial.stair-confirm")) {
            if HomeGeometryEditor.validLandings(connector, in: draft) {
                draft = HomeConfirmation.apply(.confirmConnector(connectorID: connector.id, usable: true), to: draft)
                message = nil
            } else { message = model.localizer("spatial.stair-invalid") }
        }.disabled(!landingInputsMatch(connector))
        Button(s("Not usable"), role: .destructive) {
            draft = HomeConfirmation.apply(.confirmConnector(connectorID: connector.id, usable: false), to: draft)
        }
    }

    private func removeSelected() {
        guard let id = selectedID else { return }
        if draft.space(id) != nil {
            do { try HomeGeometryEditor.removeRoom(in: &draft, roomID: id); selectedID = nil }
            catch { message = describe(error) }
            return
        }
        draft.edit { home in
            home.portals.removeAll { $0.id == id || $0.sideA == .space(id) || $0.sideB == .space(id) }
            home.annotations.removeAll { $0.id == id || $0.spaceID == id }
            home.obstacles.removeAll { $0.id == id }
            home.connectors.removeAll { $0.id == id || $0.fromSpaceID == id || $0.toSpaceID == id }
        }
        selectedID = nil
    }

    @ViewBuilder private var roomOptions: some View {
        ForEach(draft.spaces) { Text(HomeScenePresentation.roomLabel($0.id, in: draft)).tag($0.id) }
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
        anchorID = ""; doorFrom = ""; markerRoom = ""; meetingLabel = ""; roomFloorID = fresh.floors.first?.id ?? ""
        addingRoom = true
    }

    private func addRoom() {
        do {
            let label = roomLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let room: Space
            if !draft.spaces.contains(where: { $0.floorID == roomFloorID }) {
                room = try ManualLayout.addFirstRoom(to: &draft, label: label.isEmpty ? s("Room") : label,
                    kind: roomKind, width: roomWidth, depth: roomDepth, floorID: roomFloorID)
                doorFrom = room.id; markerRoom = room.id
            } else {
                room = try ManualLayout.addRoom(to: &draft, label: label.isEmpty ? s("Room") : label,
                    kind: roomKind, width: roomWidth, depth: roomDepth, attachedTo: anchorID, side: side)
            }
            message = nil
            anchorID = room.id
        } catch { message = describe(error) }
    }

    private func addFloor() {
        let name = newFloorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let elevation = decimal(newFloorElevation) else {
            message = model.localizer("spatial.level-input-error"); return
        }
        do {
            let floor = try ManualLayout.addFloor(to: &draft, label: name, level: newFloorOrder, elevationMeters: elevation)
            roomFloorID = floor.id; anchorID = ""; addingRoom = true
            newFloorLabel = ""; newFloorElevation = ""; message = nil
        } catch { message = describe(error) }
    }

    private func addStairs() {
        guard let fx = decimal(landingFromX), let fy = decimal(landingFromY),
              let tx = decimal(landingToX), let ty = decimal(landingToY) else {
            message = model.localizer("spatial.stair-invalid"); return
        }
        do {
            let stairs = try HomeGeometryEditor.addStairs(in: &draft, fromRoomID: landingFromRoom, fromPoint: Vec2(fx, fy),
                toRoomID: landingToRoom, toPoint: Vec2(tx, ty))
            selectedID = stairs.id; message = nil
        } catch { message = describe(error) }
    }

    private func addDoor() {
        // Both pickers list every room; a door from a room to itself is not a connection.
        guard doorTo != doorFrom else { message = model.localizer("spatial.different-rooms-error"); return }
        let width = Double(doorWidthText.replacingOccurrences(of: ",", with: "."))
        do {
            try ManualLayout.addPortal(to: &draft, kind: doorKind, from: doorFrom,
                                       to: doorTo == "outside" ? .exterior : .space(doorTo),
                                       exteriorSide: doorTo == "outside" ? doorSide : nil,
                                       width: width ?? (doorKind == .opening ? 1.0 : 0.8), widthMeasured: width != nil)
            message = model.localizer("spatial.opening-added")
        } catch { message = describe(error) }
    }

    private func suggestedMarkerPosition(in room: Space) -> Vec2? {
        HomeSafetyMarkers.suggestedPosition(roomID: room.id, in: draft)
    }

    @ViewBuilder private func markerPlacementEditor(_ index: Int) -> some View {
        Section(model.localizer("spatial.marker-location")) {
            Picker(s("Room"), selection: Binding(get: { markerEditRoom }, set: { roomID in
                markerEditRoom = roomID
                let suggestion = draft.space(roomID).flatMap { suggestedMarkerPosition(in: $0) }
                markerX = suggestion.map { String($0.x) } ?? ""
                markerY = suggestion.map { String($0.y) } ?? ""
                markerLocationChecked = false
            })) {
                Text(s("Not assigned")).tag("")
                ForEach(draft.spaces) { room in Text(roomFloorLabel(room)).tag(room.id) }
            }
            Text(model.localizer("spatial.marker-position-note")).font(.footnote).foregroundStyle(.secondary)
            TextField(model.localizer("spatial.marker-x"), text: Binding(get: { markerX }, set: { markerX = $0; markerLocationChecked = false })).keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("home.marker.x")
            TextField(model.localizer("spatial.marker-y"), text: Binding(get: { markerY }, set: { markerY = $0; markerLocationChecked = false })).keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("home.marker.y")
            Toggle(model.localizer("spatial.marker-location-checked"), isOn: $markerLocationChecked)
                .accessibilityIdentifier("home.marker.locationChecked")
            Button(model.localizer("spatial.marker-apply"), systemImage: "mappin.and.ellipse") { applyMarkerPlacement(index) }
                .accessibilityIdentifier("home.marker.apply")
        }
    }

    /// Save and navigation commit the visible placement too; invalid input stays on this editor.
    private func applyPendingMarkerPlacement() -> Bool {
        guard let index = draft.annotations.firstIndex(where: { $0.id == selectedID }),
              draft.annotations[index].kind != .outsideMeetingPoint,
              draft.annotations[index].kind != .exteriorHydrant else { return true }
        let marker = draft.annotations[index]
        let coordinatesUnchanged = marker.position.map { decimal(markerX) == $0.x && decimal(markerY) == $0.y }
            ?? (markerX.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && markerY.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if markerEditRoom == (marker.spaceID ?? ""), coordinatesUnchanged,
           markerLocationChecked == (marker.verification == .verified) { return true }
        applyMarkerPlacement(index)
        return message == nil
    }

    private func applyMarkerPlacement(_ index: Int) {
        guard draft.annotations.indices.contains(index), let x = decimal(markerX), let y = decimal(markerY) else {
            message = model.localizer("spatial.marker-invalid"); return
        }
        let marker = draft.annotations[index]
        do {
            var updated = try HomeSafetyMarkers.place(id: marker.id, kind: marker.kind, roomID: markerEditRoom,
                position: Vec2(x, y), label: marker.label, note: marker.note, verified: markerLocationChecked, in: draft)
            if let updatedIndex = updated.annotations.firstIndex(where: { $0.id == marker.id }) {
                updated.annotations[updatedIndex].savedPlaceID = marker.savedPlaceID
            }
            draft = updated
            message = nil
        } catch { message = model.localizer("spatial.marker-invalid") }
    }

    private func addMarker() {
        guard let room = draft.space(markerRoom), let position = suggestedMarkerPosition(in: room) else {
            message = model.localizer("spatial.marker-invalid"); return
        }
        let id = "an-\(UUID().uuidString.lowercased())"
        do {
            draft = try HomeSafetyMarkers.place(id: id, kind: markerKind, roomID: room.id,
                position: position, verified: false, in: draft)
            selectedID = id
            message = nil
        } catch { message = model.localizer("spatial.marker-invalid") }
    }

    private func setMeetingPoint() {
        draft.edit { h in
            h.annotations.removeAll { $0.kind == .outsideMeetingPoint }
            h.annotations.append(Annotation(id: "an-meeting", kind: .outsideMeetingPoint, floorID: h.floors.first?.id,
                                            label: meetingLabel, verification: .verified))
        }
    }

    private var invalidDimensionsMessage: String {
        model.localizer("spatial.invalid-dimensions", ["minimum": 0.3.formatted(.number.locale(Locale(identifier: model.locale)))])
    }

    private func describe(_ error: Error) -> String {
        if let correction = error as? HomeGeometryEditor.CorrectionError {
            switch correction {
            case .unknownRoom: return model.localizer("spatial.choose-room-error")
            case .invalidDimensions: return invalidDimensionsMessage
            case .invalidOutline: return model.localizer("spatial.invalid-outline")
            case .overlappingRoom: return model.localizer("spatial.overlap-error")
            case .unknownConnector, .differentFloorsRequired, .invalidLanding: return model.localizer("spatial.stair-invalid")
            case .unknownPortal: return model.localizer("spatial.choose-opening-error")
            }
        }
        switch error as? ManualLayout.LayoutError {
        case .overlapsExistingRoom: return model.localizer("spatial.overlap-error")
        case .noSharedWall: return model.localizer("spatial.shared-wall-error")
        case .sideNotExterior: return model.localizer("spatial.outside-wall-error")
        case .wallTooShort: return model.localizer("spatial.short-wall-error")
        case .invalidSize: return invalidDimensionsMessage
        case .unknownSpace: return model.localizer("spatial.choose-room-error")
        case nil: return error.localizedDescription
        }
    }
}
