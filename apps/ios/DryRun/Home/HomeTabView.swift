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
                        Task { await model.updateHome(updated) }
                        editing = false
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
        .sheet(item: $confirming) { draft in
            NavigationStack {
                HomeConfirmationView(home: draft) { confirmed in
                    Task { await model.updateHome(confirmed) }
                    confirming = nil
                }
            }
        }
    }

    private func tri(_ v: EvidenceValue<Bool>) -> String {
        guard let b = v.value else { return "not sure" }
        return b ? "yes" : "no"
    }
}
