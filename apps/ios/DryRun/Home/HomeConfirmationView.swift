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

    /// Pending steps, minus the ones set aside in this session. `HomeConfirmation.steps` is rebuilt from the home in a
    /// fixed order and "Not sure" does not change the home, so without this filter a skipped item stays first forever.
    private var steps: [ConfirmationStep] { HomeConfirmation.steps(for: home).filter { !skipped.contains($0.id) } }

    var body: some View {
        Form {
            if let step = steps.first {
                Section {
                    Text("\(steps.count) left").font(.footnote).foregroundStyle(.secondary)
                    Text(step.prompt).font(.headline)
                    if let about = subject(of: step) { Text(about).font(.callout) }
                    if let notice { Text(notice).font(.footnote).foregroundStyle(Theme.caution) }
                }
                FloorPlanView(home: home, routes: [], highlightedFloorID: floorID(for: step))
                    .frame(height: 220)
                    .accessibilityLabel("Floor plan. The item being confirmed is \(step.elementID).")
                stepControls(step)
            } else if !skipped.isEmpty {
                Section {
                    Label("\(skipped.count) left as not sure.", systemImage: "questionmark.circle")
                    Text("Those items stay unconfirmed and out of every practice route. You can come back to them from the Home tab.")
                        .font(.footnote)
                }
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
                Button("Save name") { answer(.labelSpace(spaceID: step.elementID, label: labelText.isEmpty ? "Room" : labelText, kind: labelKind), for: step) }
                Button("Room needs measuring") { answer(.needsMeasurement(spaceID: step.elementID), for: step) }
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
                            answer(.markPortalExterior(portalID: step.elementID, operable: operable, stepFree: stepFree), for: step)
                        }
                    }
                } else {
                    Button(portal?.leadsToExterior == true ? "Yes, this is correct" : "Yes, it connects these rooms") {
                        answer(.confirmPortal(portalID: step.elementID, operable: operable, stepFree: stepFree,
                                              clearWidthMeters: Double(widthText.replacingOccurrences(of: ",", with: "."))),
                               for: step)
                    }
                }
                Button("Not usable", role: .destructive) { answer(.rejectPortal(portalID: step.elementID), for: step) }
                Button("Not sure — leave it out of routes") { answer(.skip(elementID: step.elementID), for: step) }
            }
        case .confirmConnector:
            Section {
                Button("Yes, these stairs are usable") { answer(.confirmConnector(connectorID: step.elementID, usable: true), for: step) }
                Button("Not usable", role: .destructive) { answer(.confirmConnector(connectorID: step.elementID, usable: false), for: step) }
                Button("Not sure — decide later") { answer(.skip(elementID: step.elementID), for: step) }
            }
        case .meetingPoint:
            Section {
                TextField("For example: the neighbor's mailbox", text: $meetingText)
                Button("Set meeting point") { answer(.meetingPoint(label: meetingText), for: step) }
                    .disabled(meetingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Not sure — decide later") { answer(.skip(elementID: step.elementID), for: step) }
            }
        case .shelterSpot:
            Section {
                Picker("Room", selection: $shelterSpaceID) {
                    Text("Choose").tag(String?.none)
                    ForEach(home.spaces) { Text($0.label).tag(String?.some($0.id)) }
                }
                if let id = shelterSpaceID {
                    Button("Interior, lowest floor, no windows") { answer(.shelterSpot(spaceID: id, interiorNoWindows: true), for: step) }
                }
                Button("No such room, or not sure — decide later") { answer(.skip(elementID: step.elementID), for: step) }
            } footer: {
                Text("A household-chosen spot is not an engineered safe room. Manufactured homes need a sturdy building planned in advance.")
            }
        }
    }

    /// Steps the user chose to skip in this session (they stay unknown; shown again next time).
    @State private var skipped: Set<String> = []
    /// Shown when an answer could not be applied, so the button never appears to do nothing.
    @State private var notice: String?

    private func answer(_ a: ConfirmationAnswer, for step: ConfirmationStep) {
        let updated = HomeConfirmation.apply(a, to: home)
        switch a {
        case .skip, .needsMeasurement:
            // Deliberately left open: move on. The item stays pending and is asked again next time.
            skipped.insert(step.id)
            notice = nil
        default:
            if updated == home {
                // The core refused the answer (for example an exit that is not on the ground floor, or a shelter room
                // that is not on the lowest floor). Stay on this item and say so.
                notice = "That answer doesn't fit this item, so nothing was changed. Choose another answer, or leave it as not sure."
                return
            }
            notice = nil
        }
        home = updated
        labelText = ""; widthText = ""; meetingText = ""; operable = true; stepFree = nil; shelterSpaceID = nil
    }

    /// Which room, door, or stairs the question is about, in words. Scanned elements have opaque IDs, so the prompt
    /// alone cannot tell two doors apart.
    private func subject(of step: ConfirmationStep) -> String? {
        func name(_ side: PortalDestination) -> String {
            switch side {
            case .space(let id): return home.space(id)?.label ?? "a room"
            case .exterior: return "outside"
            case .commonArea: return "a shared building area"
            case .unknown: return "not known yet"
            }
        }
        switch step.kind {
        case .labelSpace:
            return home.space(step.elementID).map { "Currently shown as: \($0.label)" }
        case .confirmPortal:
            guard let p = home.portal(step.elementID) else { return nil }
            return "\(p.kind.rawValue.capitalized) between: \(name(p.sideA)) and \(name(p.sideB))"
        case .confirmConnector:
            guard let c = home.connectors.first(where: { $0.id == step.elementID }) else { return nil }
            return "Between: \(home.space(c.fromSpaceID)?.label ?? "a room") and \(home.space(c.toSpaceID)?.label ?? "a room")"
        case .meetingPoint, .shelterSpot:
            return nil
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
