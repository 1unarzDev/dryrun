import SwiftUI
import DryRunCore

struct HomeTabView: View {
    @Environment(AppModel.self) private var model
    @State private var mode = Mode.plan2D
    @State private var floorID: String?
    @State private var editing = false
    @State private var scanning = false
    @State private var editingHousehold = false

    enum Mode: String, CaseIterable, Identifiable {
        case plan2D = "2D plan", dollhouse = "3D", rooms = "Room list"
        var id: String { rawValue }
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
                let issues = HomeValidator.validate(home)
                Section("Still to confirm (\(issues.count))") {
                    if issues.isEmpty { Text("Nothing outstanding in the home model.") }
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Text(String(describing: issue)).font(.callout)
                    }
                }
                Section("Change the home") {
                    Button("Edit rooms, doors, and markers", systemImage: "square.and.pencil") { editing = true }
                    if model.capabilities.roomCaptureSupported {
                        Button("Scan with RoomPlan", systemImage: "camera.viewfinder") { scanning = true }
                    } else {
                        Label("Room scanning needs an iPhone with LiDAR. Manual layout works on every device.", systemImage: "info.circle")
                            .font(.footnote)
                    }
                }
            }
            if let h = model.household {
                Section("Household systems") {
                    LabeledContent("People", value: "\(h.people.count)")
                    LabeledContent("Heat", value: "\(h.housing.heatingFuel.rawValue) · needs power: \(tri(h.housing.heatingNeedsElectricity))")
                    LabeledContent("Water", value: h.housing.waterSource.rawValue)
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
        .fullScreenCover(isPresented: $scanning) {
            RoomScanFlowView { proposed in
                if let proposed { Task { await model.updateHome(proposed) } }
                scanning = false
            }
        }
        .navigationDestination(isPresented: $editingHousehold) { HouseholdSetupView(mode: .edit) }
    }

    private func tri(_ v: EvidenceValue<Bool>) -> String {
        guard let b = v.value else { return "not sure" }
        return b ? "yes" : "no"
    }
}
