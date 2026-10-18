import SwiftUI
import UIKit
import DryRunCore

struct HomeTabView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    // Not a `switch` expression inline: Xcode 27's @State macro does not accept one as the initial value.
    @State private var mode: Mode = Mode.initial(DemoLaunch.current.homeMode)
    @State private var floorID: String?
    @State private var editing = false
    @State private var manualDraft: HomeModel?
    @State private var selectedElementID: String?
    @State private var scanning = false
    @State private var editingHousehold = false
    @State private var confirming: HomeModel?
    @State private var showingMeetingPlaceMap = false
    /// A finished scan waiting for the scan cover to finish dismissing before the confirmation sheet is presented.
    @State private var pendingProposal: HomeModel?

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
                    if home.floors.count > 1 {
                        Picker(s("Floor"), selection: Binding(get: { floorID ?? home.floors.first?.id ?? "" }, set: { floorID = $0 })) {
                            ForEach(home.floors) { Text($0.label).tag($0.id) }
                        }
                    }
                    switch mode {
                    case .plan2D:
                        FloorPlanView(home: home, routes: [], highlightedFloorID: floorID ?? home.floors.first?.id, onSelect: { selectedElementID = $0; editing = true })
                            .frame(height: 320)
                            .listRowInsets(EdgeInsets())
                            .accessibilityIdentifier("home.scene")
                    case .dollhouse:
                        DollhouseView(home: home, routes: [], floorID: floorID ?? home.floors.first?.id)
                            .frame(height: 320)
                            .listRowInsets(EdgeInsets())
                            .accessibilityIdentifier("home.scene")
                    case .rooms:
                        HomeRoomListView(home: home)
                    }
                }
                Section(s("Change the home")) {
                    let pending = HomeConfirmation.steps(for: home).count
                    if pending > 0 {
                        Button(model.localizer("spatial.confirm-count", ["count": String(pending)]), systemImage: "checklist") { confirming = home }
                    }
                    Button(s("Edit rooms, doors, and markers"), systemImage: "square.and.pencil") { selectedElementID = nil; editing = true }
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
                                    Text(space.label).tag(String?.some(space.id))
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
                let issues = HomeValidator.validate(home)
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
                        selectedElementID = nil
                        if manualDraft == nil {
                            manualDraft = ManualLayout.emptyHome(id: model.household?.stableHomeID ?? "home-\(UUID().uuidString.lowercased())")
                        }
                        editing = true
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
        .sheet(isPresented: $editing, onDismiss: { selectedElementID = nil }) {
            if let home = model.home ?? manualDraft {
                NavigationStack {
                    ManualHomeEditorView(home: home, selectedElementID: selectedElementID) { updated in
                        Task {
                            manualDraft = updated
                            if await model.updateHome(updated) { editing = false; manualDraft = nil }
                        }
                    }
                }
                .interactiveDismissDisabled()
            }
        }
        .fullScreenCover(isPresented: $scanning, onDismiss: {
            // A scan is only a proposal: go straight into the confirmation pass before it is saved. Presented from
            // onDismiss because SwiftUI can drop a sheet requested while the cover is still dismissing.
            if let proposed = pendingProposal {
                pendingProposal = nil
                confirming = proposed
            }
        }) {
            RoomScanFlowView { proposed in
                pendingProposal = proposed
                scanning = false
            }
        }
        .navigationDestination(isPresented: $editingHousehold) { HouseholdSetupView(mode: .edit) }
        .sheet(isPresented: $showingMeetingPlaceMap) {
            if let regionalResources = model.regionalResources { MapPlanningView(store: regionalResources, purpose: .outsideMeetingPoint) }
            else if let content = model.content {
                MapPlanningView(content: content, client: model.publicClient, regionID: model.household?.regionID ?? "", purpose: .outsideMeetingPoint)
            }
        }
        .sheet(item: $confirming) { draft in
            NavigationStack {
                HomeConfirmationView(home: draft) { confirmed in
                    Task {
                        if await model.updateHome(confirmed) { confirming = nil }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }

    @ViewBuilder private var scanControls: some View {
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
