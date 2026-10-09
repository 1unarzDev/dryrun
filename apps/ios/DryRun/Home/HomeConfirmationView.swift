import SwiftUI
import DryRunCore

/// Guided confirmation pass, one question at a time. Answers go through `HomeConfirmation.apply`, the only way a
/// scan-proposed element becomes verified. "Not sure" leaves it unknown and out of every route.
struct HomeConfirmationView: View {
    @State var home: HomeModel
    let onFinish: (HomeModel) -> Void
    @State private var labelText = ""
    @State private var labelKind = SpaceKind.other
    @State private var operable = true
    @State private var stepFree: Bool?
    @State private var widthText = ""
    @State private var meetingText = ""
    @State private var shelterSpaceID: String?

    private var steps: [ConfirmationStep] { HomeConfirmation.steps(for: home) }

    var body: some View {
        Form {
            if let step = steps.first {
                Section {
                    Text("\(steps.count) left").font(.footnote).foregroundStyle(.secondary)
                    Text(step.prompt).font(.headline)
                }
                FloorPlanView(home: home, routes: [], highlightedFloorID: floorID(for: step))
                    .frame(height: 220)
                    .accessibilityLabel("Floor plan. The item being confirmed is \(step.elementID).")
                stepControls(step)
            } else {
                Section {
                    Label("Everything that needs your confirmation is done.", systemImage: "checkmark.seal")
                    Text("Practice routes now use only the doors and exits you confirmed. Re-check after changes to the home.")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Confirm your home")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Save") { onFinish(home) } }
        }
    }

    @ViewBuilder
    private func stepControls(_ step: ConfirmationStep) -> some View {
        switch step.kind {
        case .labelSpace:
            Section {
                TextField("Room name", text: $labelText)
                Picker("Room type", selection: $labelKind) { ForEach(SpaceKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Button("Save name") { answer(.labelSpace(spaceID: step.elementID, label: labelText.isEmpty ? "Room" : labelText, kind: labelKind)) }
                Button("Room needs measuring") { answer(.needsMeasurement(spaceID: step.elementID)) }
            }
        case .confirmPortal:
            let portal = home.portal(step.elementID)
            let unknownSide = portal.map { $0.sideA == .unknown || $0.sideB == .unknown } ?? true
            Section {
                Toggle("Opens without a key or tool", isOn: $operable)
                Picker("Threshold", selection: $stepFree) {
                    Text("Step-free").tag(Bool?.some(true)); Text("Has a step").tag(Bool?.some(false)); Text("Not sure").tag(Bool?.none)
                }
                TextField("Clear width in meters (optional)", text: $widthText).keyboardType(.decimalPad)
                if unknownSide {
                    if portal?.kind != .window {
                        Button("It leads outside (ground level)") {
                            answer(.markPortalExterior(portalID: step.elementID, operable: operable, stepFree: stepFree))
                        }
                    }
                } else {
                    Button("Yes, it connects these rooms") {
                        answer(.confirmPortal(portalID: step.elementID, operable: operable, stepFree: stepFree,
                                              clearWidthMeters: Double(widthText)))
                    }
                }
                Button("Not usable", role: .destructive) { answer(.rejectPortal(portalID: step.elementID)) }
                Button("Not sure — leave it out of routes") { answer(.skip(elementID: step.elementID)); skipped.insert(step.id) }
            }
        case .confirmConnector:
            Section {
                Button("Yes, these stairs are usable") { answer(.confirmConnector(connectorID: step.elementID, usable: true)) }
                Button("Not usable", role: .destructive) { answer(.confirmConnector(connectorID: step.elementID, usable: false)) }
            }
        case .meetingPoint:
            Section {
                TextField("For example: the neighbor's mailbox", text: $meetingText)
                Button("Set meeting point") { answer(.meetingPoint(label: meetingText)) }
            }
        case .shelterSpot:
            Section {
                Picker("Room", selection: $shelterSpaceID) {
                    Text("Choose").tag(String?.none)
                    ForEach(home.spaces) { Text($0.label).tag(String?.some($0.id)) }
                }
                if let id = shelterSpaceID {
                    Button("Interior, lowest floor, no windows") { answer(.shelterSpot(spaceID: id, interiorNoWindows: true)) }
                }
            } footer: {
                Text("A household-chosen spot is not an engineered safe room. Manufactured homes need a sturdy building planned in advance.")
            }
        }
    }

    /// Steps the user chose to skip in this session (they stay unknown; shown again next time).
    @State private var skipped: Set<String> = []

    private func answer(_ a: ConfirmationAnswer) {
        home = HomeConfirmation.apply(a, to: home)
        labelText = ""; widthText = ""; meetingText = ""; operable = true; stepFree = nil; shelterSpaceID = nil
        if case .skip(let id) = a {
            // Move past a skipped item without changing it: rotate it to the end for this session.
            if let i = home.portals.firstIndex(where: { $0.id == id }) {
                let p = home.portals.remove(at: i)
                home.portals.append(p)
            }
        }
    }

    private func floorID(for step: ConfirmationStep) -> String? {
        switch step.kind {
        case .confirmPortal: home.portal(step.elementID)?.floorID
        case .labelSpace: home.space(step.elementID)?.floorID
        default: home.floors.first?.id
        }
    }
}
