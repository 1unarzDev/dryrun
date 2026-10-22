import SwiftUI
import UIKit
import DryRunCore

struct HomeTabView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    // Not a `switch` expression inline: Xcode 27's @State macro does not accept one as the initial value.
    @State private var mode: Mode = Mode.initial(DemoLaunch.current.homeMode)
    @State private var floorID: String? = DemoLaunch.current.homeFloor.flatMap { index in
        DemoLaunch.current.isActive ? DemoLaunch.current.homeID.flatMap { id in SampleHomes.all.first { $0.id == id } }
            .flatMap { $0.floors.indices.contains(index) ? $0.floors[index].id : nil } : nil
    }
    /// The editor opens on the element that was tapped. An item-driven sheet hands that ID to the editor directly;
    /// an isPresented sheet could read a stale selection and open the general list instead (seen on device).
    struct EditorRequest: Identifiable { let id = UUID(); let elementID: String? }
    @State private var editorRequest: EditorRequest?
    @State private var manualDraft: HomeModel?
    @State private var scanning = false
    @State private var editingHousehold = false
    @State private var showingMeetingPlaceMap = false
    @State private var showingExitRoutes = true

    enum Mode: String, CaseIterable, Identifiable {
        case plan2D = "2D plan", dollhouse = "3D", rooms = "Room list"
        var id: String { rawValue }

        static func initial(_ demoMode: String?) -> Mode {
            switch demoMode {
            case "3d": .dollhouse
            case "rooms": .rooms
            default: .plan2D
            }
        }
    }

    var body: some View {
        List {
            if let home = model.home {
                Section {
                    if home.isFictional {
                        Label(s("Sample home (fictional). Build or scan your own home to rehearse it."), systemImage: "house.lodge")
                            .font(.footnote)
                    }
                    if home.source == .roomPlanScan {
                        Label(s("Scanned layout. Doors and exits count only after you confirm them."), systemImage: "camera.viewfinder")
                            .font(.footnote)
                    }
                    Picker(s("View"), selection: $mode) {
                        ForEach(Mode.allCases) { Text(s($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("home.viewMode")
                    if home.floors.count > 1 {
                        Picker(s("Floor"), selection: Binding(get: { floorID ?? home.floors.first?.id ?? "" }, set: { floorID = $0 })) {
                            ForEach(home.floors.sorted { ($0.level, $0.id) < ($1.level, $1.id) }) { Text($0.label).tag($0.id) }
                        }
                        .accessibilityIdentifier("home.floor")
                    }
                    switch mode {
                    case .plan2D:
                        // The saved home only: the line recomputes after each Save, Undo or Revert, never from a draft.
                        let people = model.household?.people ?? []
                        let exitRoutes = showingExitRoutes ? HomeCommittedRoutes.outdoorEgress(people: people, home: home) : []
                        FloorPlanView(home: home, routes: HomeCommittedRoutes.paths(exitRoutes), highlightedFloorID: floorID ?? home.floors.first?.id, onSelect: { editorRequest = EditorRequest(elementID: $0) })
                            .frame(height: 320)
                            .listRowInsets(EdgeInsets())
                            .accessibilityIdentifier("home.scene")
                        if !people.isEmpty {
                            Toggle(s("Show the way out from each starting room"), isOn: $showingExitRoutes)
                                .font(.callout)
                                .accessibilityIdentifier("home.exitRoutes")
                            ForEach(exitRoutes.filter { $0.path == nil }) { entry in
                                if let person = people.first(where: { $0.id == entry.personID }), let reason = entry.noRouteReason {
                                    Label(person.localizedLabel(model.localizer) + ": " + model.localizer("plan.route.reason.\(reason.rawValue)"),
                                          systemImage: "exclamationmark.triangle")
                                        .font(.footnote)
                                        .accessibilityIdentifier("home.exitRoutes.missing.\(entry.personID)")
                                }
                            }
                        }
                    case .dollhouse:
                        DollhouseView(home: home, routes: [], floorID: floorID ?? home.floors.first?.id)
                            .frame(height: 320)
                            .listRowInsets(EdgeInsets())
                            .accessibilityIdentifier("home.scene")
                        DollhouseKey(home: home, floorID: floorID ?? home.floors.first?.id)
                    case .rooms:
                        HomeRoomListView(home: home)
                    }
                }
                if mode != .rooms {
                    Section {
                        DisclosureGroup(s("Safety markers")) {
                            let markers = home.annotations.filter { $0.floorID == (floorID ?? home.floors.first?.id) }
                            if markers.isEmpty { Text(model.localizer("spatial.no-markers-floor")).font(.footnote).foregroundStyle(.secondary) }
                            ForEach(markers) { marker in
                                Button {
                                    editorRequest = EditorRequest(elementID: marker.id)
                                } label: {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(marker.localizedLabel(model.localizer)).foregroundStyle(.primary)
                                            if let roomID = marker.spaceID {
                                                Text(HomeScenePresentation.roomLabel(roomID, in: home)).font(.footnote).foregroundStyle(.secondary)
                                            }
                                            Text(model.localizer(marker.verification == .verified ? "spatial.marker-recorded" : "spatial.marker-review"))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: FloorPlanView.symbol(marker.kind)).foregroundStyle(Theme.accent)
                                    }
                                }
                                .accessibilityIdentifier("home.marker.\(marker.id)")
                            }
                        }
                        // A container keeps each marker row's own identifier.
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("home.markerKey")
                    }
                }
                Section {
                    NavigationLink { SiteEvidenceView() } label: {
                        Label(model.localizer("site.title"), systemImage: "map")
                    }.accessibilityIdentifier("home.siteEvidence")
                    NavigationLink { PhotoReviewView() } label: {
                        Label(model.localizer("photo.title"), systemImage: "camera.viewfinder")
                    }.accessibilityIdentifier("home.photoReview")
                }
                Section(s("Change the home")) {
                    Button(s("Edit rooms, doors, and markers"), systemImage: "square.and.pencil") { editorRequest = EditorRequest(elementID: nil) }
                        .accessibilityIdentifier("home.edit")
                    // Saved versions (last 20 per home): each step is a new revision-checked save, never a silent rewrite.
                    if model.canUndoHomeSave || model.canRedoHomeSave {
                        HStack {
                            Button(model.localizer("spatial.card.undoSave"), systemImage: "arrow.uturn.backward") { Task { await model.undoHomeSave() } }
                                .disabled(!model.canUndoHomeSave)
                                .accessibilityIdentifier("home.undoSave")
                            Spacer()
                            Button(model.localizer("spatial.card.redoSave"), systemImage: "arrow.uturn.forward") { Task { await model.redoHomeSave() } }
                                .disabled(!model.canRedoHomeSave)
                                .accessibilityIdentifier("home.redoSave")
                        }
                        .buttonStyle(.borderless)
                    }
                    scanControls
                }
                if let household = model.household, !household.people.isEmpty {
                    Section(s("Resident starting rooms")) {
                        Text(s("Assign each person to the room where a rehearsal should start. Leave a person unassigned when the answer is unknown; Dry Run will report that explicitly instead of guessing."))
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(household.people) { person in
                            Picker(person.localizedLabel(model.localizer),
                                   selection: Binding<String?>(
                                    get: { model.household?.people.first(where: { $0.id == person.id })?.sleepingSpaceID },
                                    set: { value in
                                        Task {
                                            await model.updateHousehold { edited in
                                                guard let index = edited.people.firstIndex(where: { $0.id == person.id }) else { return }
                                                edited.people[index].sleepingSpaceID = value
                                            }
                                        }
                                    })) {
                                Text(s("Not assigned")).tag(String?.none)
                                ForEach(home.spaces) { space in
                                    Text(HomeScenePresentation.roomLabel(space.id, in: home)).tag(String?.some(space.id))
                                }
                            }
                        }
                    }
                }
                Section(s("Outside meeting place")) {
                    if let annotation = home.meetingPoint {
                        Label(annotation.localizedLabel(model.localizer), systemImage: "mappin.and.ellipse")
                        Text(s("This text note is kept separate from indoor floor-plan coordinates."))
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(s("Add a text meeting point in the home review, or choose a geographic planning point."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(model.savedPlaces.filter { $0.homeID == home.id && $0.purpose == .outsideMeetingPoint }) { place in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(place.label, systemImage: "mappin.and.ellipse")
                            if let address = place.addressText { Text(address).font(.caption).foregroundStyle(.secondary) }
                            Text(s("Saved privately. A map point does not certify a safe outdoor path."))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(s("Delete"), role: .destructive) { Task { await model.deletePlace(id: place.id) } }
                        }
                    }
                    Button(s("Choose on map"), systemImage: "map") { showingMeetingPlaceMap = true }
                }
                let issues = HomeValidator.validate(home).filter { $0.kind != .spaceNeedsMeasurement && $0.kind != .spaceLabelUnconfirmed }
                Section(model.localizer("spatial.issues-count", ["count": String(issues.count)])) {
                    if issues.isEmpty { Text(s("Nothing outstanding in the home model.")) }
                    ForEach(issues) { issue in
                        Label(issueText(issue), systemImage: issue.severity == .blocking ? "exclamationmark.octagon" : "questionmark.circle")
                            .font(.callout)
                    }
                }
            }
            if model.home == nil {
                Section(s("Your home layout")) {
                    Text(s("Your card and preparations work without a layout. Add your own rooms when you are ready to rehearse routes."))
                        .font(.callout).foregroundStyle(.secondary)
                    Button(s("Add layout manually"), systemImage: "square.and.pencil") {
                        if manualDraft == nil {
                            manualDraft = ManualLayout.emptyHome(id: model.household?.stableHomeID ?? "home-\(UUID().uuidString.lowercased())")
                        }
                        editorRequest = EditorRequest(elementID: nil)
                    }
                    .accessibilityIdentifier("home.addManual")
                    scanControls
                }
                Section(s("Outside meeting place")) {
                    Button(s("Choose on map"), systemImage: "map") { showingMeetingPlaceMap = true }
                }
            }
            if let h = model.household {
                Section(s("Household systems")) {
                    LabeledContent(s("People"), value: "\(h.people.count)")
                    LabeledContent(s("Heat"), value: model.localizer("spatial.heating-summary", ["type": DisplayNames.name(h.housing.heatingFuel.rawValue, localizer: model.localizer), "power": tri(h.housing.heatingNeedsElectricity)]))
                    LabeledContent(s("Water"), value: DisplayNames.name(h.housing.waterSource.rawValue, localizer: model.localizer))
                    LabeledContent(s("Vehicle"), value: s(h.transport.hasVehicle ? "Yes" : "No"))
                    ForEach(h.equipment) { eq in
                        LabeledContent(DisplayNames.equipment(eq, localizer: model.localizer), value: model.localizer(eq.compatibleBackupIDs.isEmpty ? "spatial.no-confirmed-backup" : "spatial.backup-listed"))
                    }
                    Button(s("Edit household"), systemImage: "person.2") { editingHousehold = true }
                }
            }
        }
        .navigationTitle(model.localizer("common.tab.home"))
        .sheet(item: $editorRequest, onDismiss: { manualDraft = nil }) { request in
            if let home = manualDraft ?? model.home {
                NavigationStack {
                    ManualHomeEditorView(home: home, selectedElementID: request.elementID, savedBaseRevision: model.home?.revision, scopeSessionID: model.scopeSessionID) { updated, baseRevision, scope in
                        manualDraft = updated
                        let saved = await model.updateHome(updated, baseRevision: baseRevision, scopeSessionID: scope)
                        if saved { editorRequest = nil; manualDraft = nil }
                        return saved
                    }
                }
                .interactiveDismissDisabled()
            }
        }
        .roomScanToHome(isPresented: $scanning)
        .onChange(of: model.scopeSessionID) { _, _ in
            scanning = false; editorRequest = nil; manualDraft = nil
        }
        .navigationDestination(isPresented: $editingHousehold) { FocusedHouseholdEditor(focus: .family) }
        .sheet(isPresented: $showingMeetingPlaceMap) {
            MeetingPlaceChooser(purpose: .outsideMeetingPoint)
        }
    }

    @ViewBuilder private var scanControls: some View {
        NavigationLink { ScannerHomeView() } label: {
            Label(model.localizer("spatial.scanner.title"), systemImage: "sensor.tag.radiowaves.forward")
        }.accessibilityIdentifier("home.scanner")
        switch model.capabilities.plan.scan {
        case .available:
            Button(s("Scan with RoomPlan"), systemImage: "camera.viewfinder") { scanning = true }
                .accessibilityIdentifier("home.scan")
        case .cameraDenied:
            Label(s("Camera access is off for Dry Run. Turn it on in Settings to scan, or edit the layout by hand."),
                  systemImage: "camera.badge.ellipsis")
                .font(.footnote)
            if let url = URL(string: UIApplication.openSettingsURLString) { Link(s("Open Settings"), destination: url) }
        case .unsupportedDevice:
            Label(s("Room scanning needs an iPhone with LiDAR. Manual layout works on every device."), systemImage: "info.circle")
                .font(.footnote)
        }
    }

    private func tri(_ v: EvidenceValue<Bool>) -> String {
        guard let b = v.value else { return s("Not sure") }
        return s(b ? "Yes" : "No")
    }

    private func issueText(_ issue: HomeIssue) -> String {
        guard let home = model.home else { return issue.message }
        return SpatialStrings.issue(issue, in: home, localizer: model.localizer)
    }
}
