import SwiftUI
import UIKit
import DryRunCore

struct HomeTabView: View {
    @Environment(AppModel.self) private var model
    // Not a `switch` expression inline: Xcode 27's @State macro does not accept one as the initial value.
    @State private var mode: Mode = Mode.initial(DemoLaunch.current.homeMode)
    @State private var floorID: String?
    @State private var editing = false
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
                        Label("Sample home (fictional). Build or scan your own home to rehearse it.", systemImage: "house.lodge")
                            .font(.footnote)
                    }
                    if home.source == .roomPlanScan {
                        Label("Scanned layout. Doors and exits count only after you confirm them.", systemImage: "camera.viewfinder")
                            .font(.footnote)
                    }
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if home.floors.count > 1 {
                        Picker("Floor", selection: Binding(get: { floorID ?? home.floors.first?.id ?? "" }, set: { floorID = $0 })) {
                            ForEach(home.floors) { Text($0.label).tag($0.id) }
                        }
                    }
                    switch mode {
                    case .plan2D:
                        FloorPlanView(home: home, routes: [], highlightedFloorID: floorID ?? home.floors.first?.id)
                            .frame(height: 320)
                            .listRowInsets(EdgeInsets())
                    case .dollhouse:
                        DollhouseView(home: home, routes: [], floorID: floorID ?? home.floors.first?.id)
                            .frame(height: 320)
                            .listRowInsets(EdgeInsets())
                    case .rooms:
                        HomeRoomListView(home: home)
                    }
                }
                Section("Change the home") {
                    let pending = HomeConfirmation.steps(for: home).count
                    if pending > 0 {
                        Button("Confirm rooms, doors, and exits (\(pending))", systemImage: "checklist") { confirming = home }
                    }
                    Button("Edit rooms, doors, and markers", systemImage: "square.and.pencil") { editing = true }
                    switch model.capabilities.plan.scan {
                    case .available:
                        Button("Scan with RoomPlan", systemImage: "camera.viewfinder") { scanning = true }
                    case .cameraDenied:
                        Label("Camera access is off for Dry Run. Turn it on in Settings to scan, or edit the layout by hand.",
                              systemImage: "camera.badge.ellipsis")
                            .font(.footnote)
                        if let url = URL(string: UIApplication.openSettingsURLString) { Link("Open Settings", destination: url) }
                    case .unsupportedDevice:
                        Label("Room scanning needs an iPhone with LiDAR. Manual layout works on every device.", systemImage: "info.circle")
                            .font(.footnote)
                    }
                }
                if let household = model.household, !household.people.isEmpty {
                    Section("Resident starting rooms") {
                        Text("Assign each person to the room where a rehearsal should start. Leave a person unassigned when the answer is unknown; Dry Run will report that explicitly instead of guessing.")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(household.people) { person in
                            Picker(person.alias.isEmpty ? "Resident" : person.alias,
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
                                Text("Not assigned").tag(String?.none)
                                ForEach(home.spaces) { space in
                                    Text(space.label).tag(String?.some(space.id))
                                }
                            }
                        }
                    }
                }
                Section("Outside meeting place") {
                    if let annotation = home.meetingPoint {
                        Label(annotation.label, systemImage: "mappin.and.ellipse")
                        Text("This text note is kept separate from indoor floor-plan coordinates.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Add a text meeting point in the home review, or choose a geographic planning point.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(model.savedPlaces.filter { $0.homeID == home.id && $0.purpose == .outsideMeetingPoint }) { place in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(place.label, systemImage: "mappin.and.ellipse")
                            if let address = place.addressText { Text(address).font(.caption).foregroundStyle(.secondary) }
                            Text("Saved privately. A map point does not certify a safe outdoor path.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { Task { await model.deletePlace(id: place.id) } }
                        }
                    }
                    Button("Choose on map", systemImage: "map") { showingMeetingPlaceMap = true }
                }
                let issues = HomeValidator.validate(home)
                Section("Still to confirm (\(issues.count))") {
                    if issues.isEmpty { Text("Nothing outstanding in the home model.") }
                    ForEach(issues) { issue in
                        Label(issue.message, systemImage: issue.severity == .blocking ? "exclamationmark.octagon" : "questionmark.circle")
                            .font(.callout)
                    }
                }
            }
            if let h = model.household {
                Section("Household systems") {
                    LabeledContent("People", value: "\(h.people.count)")
                    LabeledContent("Heat", value: "\(h.housing.heatingFuel.displayName) · needs power: \(tri(h.housing.heatingNeedsElectricity))")
                    LabeledContent("Water", value: h.housing.waterSource.displayName)
                    LabeledContent("Vehicle", value: h.transport.hasVehicle ? "Yes" : "No")
                    ForEach(h.equipment) { eq in
                        LabeledContent(eq.label, value: eq.compatibleBackupIDs.isEmpty ? "No confirmed backup" : "Backup listed")
                    }
                    Button("Edit household", systemImage: "person.2") { editingHousehold = true }
                }
            }
        }
        .navigationTitle(model.localizer("common.tab.home"))
        .sheet(isPresented: $editing) {
            if let home = model.home {
                NavigationStack {
                    ManualHomeEditorView(home: home) { updated in
                        Task {
                            if await model.updateHome(updated) { editing = false }
                        }
                    }
                }
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
            if let home = model.home, let regionalResources = model.regionalResources {
                MapPlanningView(store: regionalResources) { coordinate, label, address in
                    let place = SavedPlace(homeID: home.id, purpose: .outsideMeetingPoint, label: label,
                                           coordinate: coordinate, addressText: address, provenance: .userSelected)
                    let saved = await model.savePlace(place)
                    if saved { showingMeetingPlaceMap = false }
                    return saved
                }
            } else if let content = model.content, let home = model.home {
                MapPlanningView(content: content, client: model.publicClient, regionID: model.household?.regionID ?? "tx-statewide") { coordinate, label, address in
                    let place = SavedPlace(homeID: home.id, purpose: .outsideMeetingPoint, label: label,
                                           coordinate: coordinate, addressText: address, provenance: .userSelected)
                    let saved = await model.savePlace(place)
                    if saved { showingMeetingPlaceMap = false }
                    return saved
                }
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
        }
    }

    private func tri(_ v: EvidenceValue<Bool>) -> String {
        guard let b = v.value else { return "not sure" }
        return b ? "yes" : "no"
    }
}
