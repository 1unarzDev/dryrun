import SwiftUI
import DryRunCore

/// Guided confirmation pass, one question at a time. Answers go through `HomeConfirmation.apply`, the only way a
/// scan-proposed element becomes verified. "Not sure" leaves it unknown and out of every route.
struct HomeConfirmationView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    @State var home: HomeModel
    let onFinish: (HomeModel) -> Void
    @State private var labelText = ""
    @State private var labelKind = SpaceKind.other
    @State private var operable: Bool?
    @State private var stepFree: Bool?
    @State private var widthText = ""
    @State private var interiorRoomID: String?
    @State private var meetingText = ""
    @State private var shelterSpaceID: String?
    @State private var undo: [HomeModel] = []

    /// Pending steps, minus the ones set aside in this session. `HomeConfirmation.steps` is rebuilt from the home in a
    /// fixed order and "Not sure" does not change the home, so without this filter a skipped item stays first forever.
    private var steps: [ConfirmationStep] { HomeConfirmation.steps(for: home).filter { !skipped.contains($0.id) } }

    var body: some View {
        Form {
            if let step = steps.first {
                Section {
                    Text(model.localizer("spatial.items-left", ["count": "\(steps.count)"])).font(.footnote).foregroundStyle(.secondary)
                    Text(model.localizer("spatial.question." + step.kind.rawValue)).font(.headline)
                    if let about = subject(of: step) { Text(about).font(.callout) }
                    if let notice { Text(notice).font(.footnote).foregroundStyle(Theme.caution) }
                }
                FloorPlanView(home: home, routes: [], highlightedFloorID: floorID(for: step), highlightedElementID: step.elementID)
                    .frame(height: 220)
                    .accessibilityLabel("Floor plan. The item being confirmed is \(step.elementID).")
                stepControls(step)
            } else if !skipped.isEmpty {
                Section {
                    Label(model.localizer("spatial.items-unknown", ["count": "\(skipped.count)"]), systemImage: "questionmark.circle")
                    Text(s("Those items stay unconfirmed and out of every practice route. You can come back to them from the Home tab."))
                        .font(.footnote)
                }
            } else {
                Section {
                    Label(s("Review answers saved"), systemImage: "checkmark.seal")
                    Text(s("Routes still depend on complete geometry, usable connections and the person’s needs. Remaining validation issues appear in your home review."))
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(s("Confirm your home"))
        .onChange(of: steps.first?.id, initial: true) { _, _ in
            labelText = ""; widthText = ""; interiorRoomID = nil; operable = nil; stepFree = nil
            if let step = steps.first {
                if let room = home.space(step.elementID) { labelText = room.label; labelKind = room.kind }
                if let portal = home.portal(step.elementID) {
                    operable = portal.operable.value; stepFree = portal.stepFree.value
                    widthText = portal.clearWidthMeters.value.map { String($0) } ?? ""
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(s("Undo")) { if let previous = undo.popLast() { home = previous; skipped.removeAll() } }.disabled(undo.isEmpty) }
            ToolbarItem(placement: .confirmationAction) { Button(s("Save")) { onFinish(home) } }
        }
    }

    @ViewBuilder
    private func stepControls(_ step: ConfirmationStep) -> some View {
        switch step.kind {
        case .confirmFloor:
            Section {
                ForEach([ExteriorGrade.ground, .aboveGround, .belowGround, .walkout], id: \.self) { grade in
                    Button(s(grade == .ground ? "Ground level" : grade == .aboveGround ? "Above ground" : grade == .belowGround ? "Below ground" : "Walkout level — exterior ground at an exit")) {
                        answer(.floorGrade(floorID: step.elementID, grade: grade), for: step)
                    }
                }
                Button(s("Not sure — decide later")) { answer(.skip(elementID: step.elementID), for: step) }
                Text(s("A walkout level still needs each exterior opening checked. Stairs need both landings confirmed.")).font(.footnote)
            }
        case .labelSpace:
            Section {
                TextField(s("Room name"), text: $labelText)
                Picker(s("Room type"), selection: $labelKind) { ForEach(SpaceKind.allCases, id: \.self) { Text(DisplayNames.name($0.rawValue, localizer: model.localizer)).tag($0) } }
                Button(s("Save name")) { answer(.labelSpace(spaceID: step.elementID, label: labelText.isEmpty ? "Room" : labelText, kind: labelKind), for: step) }
                Button(s("Room needs measuring")) { answer(.needsMeasurement(spaceID: step.elementID), for: step) }
            }
        case .confirmPortal:
            let portal = home.portal(step.elementID)
            let unknownSide = portal.map { $0.sideA == .unknown || $0.sideB == .unknown } ?? true
            Section {
                Picker(s("Opens without a key or tool"), selection: $operable) {
                    Text(s("Yes")).tag(Bool?.some(true))
                    Text(s("No")).tag(Bool?.some(false))
                    Text(s("Not sure")).tag(Bool?.none)
                }
                Picker(s("Threshold"), selection: $stepFree) {
                    Text(s("Step-free")).tag(Bool?.some(true)); Text(s("Has a step")).tag(Bool?.some(false)); Text(s("Not sure")).tag(Bool?.none)
                }
                TextField(s("Clear width in meters (optional)"), text: $widthText).keyboardType(.decimalPad)
                if unknownSide {
                    if portal?.kind != .window {
                        Picker(s("This opening also leads to"), selection: $interiorRoomID) {
                            Text(s("Choose a room")).tag(String?.none)
                            ForEach(home.spaces.filter { room in
                                guard room.floorID == portal?.floorID else { return false }
                                guard let portal else { return true }
                                return portal.sideA != .space(room.id) && portal.sideB != .space(room.id)
                            }) { room in
                                Text(room.label).tag(String?.some(room.id))
                            }
                        }
                        Button(s("Connect to this room")) {
                            if let roomID = interiorRoomID {
                                let connected = HomeConfirmation.apply(.assignPortalInterior(portalID: step.elementID, spaceID: roomID), to: home)
                                undo.append(home)
                                home = HomeConfirmation.apply(.confirmPortalEvidence(portalID: step.elementID, operable: operable, stepFree: stepFree, clearWidthMeters: parsedWidth), to: connected)
                                notice = nil
                            }
                        }
                        .disabled(interiorRoomID == nil)
                        Button(s("It leads outside (ground level)")) {
                            answer(.markPortalExteriorEvidence(portalID: step.elementID, operable: operable,
                                                              stepFree: stepFree, clearWidthMeters: parsedWidth), for: step)
                        }
                    }
                } else {
                    Button(portal?.leadsToExterior == true ? "Yes, this is correct" : "Yes, it connects these rooms") {
                        answer(.confirmPortalEvidence(portalID: step.elementID, operable: operable, stepFree: stepFree,
                                              clearWidthMeters: parsedWidth),
                               for: step)
                    }
                }
                Button(s("Not usable"), role: .destructive) { answer(.rejectPortal(portalID: step.elementID), for: step) }
                Button(s("Not sure — leave it out of routes")) { answer(.skip(elementID: step.elementID), for: step) }
            }
        case .confirmConnector:
            Section {
                Button(s("Yes, these stairs are usable")) { answer(.confirmConnector(connectorID: step.elementID, usable: true), for: step) }
                Button(s("Not usable"), role: .destructive) { answer(.confirmConnector(connectorID: step.elementID, usable: false), for: step) }
                Button(s("Not sure — decide later")) { answer(.skip(elementID: step.elementID), for: step) }
            }
        case .meetingPoint:
            Section {
                TextField(s("For example: the neighbor's mailbox"), text: $meetingText)
                Button(s("Set meeting point")) { answer(.meetingPoint(label: meetingText), for: step) }
                    .disabled(meetingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(s("Not sure — decide later")) { answer(.skip(elementID: step.elementID), for: step) }
            }
        case .shelterSpot:
            Section {
                Picker(s("Room"), selection: $shelterSpaceID) {
                    Text(s("Choose")).tag(String?.none)
                    ForEach(home.spaces) { Text($0.label).tag(String?.some($0.id)) }
                }
                if let id = shelterSpaceID {
                    Button(s("Interior, lowest floor, no windows")) { answer(.shelterSpot(spaceID: id, interiorNoWindows: true), for: step) }
                }
                Button(s("No such room, or not sure — decide later")) { answer(.skip(elementID: step.elementID), for: step) }
            } footer: {
                Text(s("A household-chosen spot is not an engineered safe room. Manufactured homes need a sturdy building planned in advance."))
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
        if home != updated { undo.append(home) }
        home = updated
        labelText = ""; widthText = ""; interiorRoomID = nil; meetingText = ""; operable = nil; stepFree = nil; shelterSpaceID = nil
    }

    private var parsedWidth: Double? {
        guard let value = Double(widthText.replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0 else { return nil }
        return value
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
            return "\(DisplayNames.name(p.kind.rawValue, localizer: model.localizer)) between: \(name(p.sideA)) and \(name(p.sideB))"
        case .confirmConnector:
            guard let c = home.connectors.first(where: { $0.id == step.elementID }) else { return nil }
            return "Between: \(home.space(c.fromSpaceID)?.label ?? "a room") and \(home.space(c.toSpaceID)?.label ?? "a room")"
        case .confirmFloor:
            return home.floors.first(where: { $0.id == step.elementID })?.label
        case .meetingPoint, .shelterSpot:
            return nil
        }
    }

    private func floorID(for step: ConfirmationStep) -> String? {
        switch step.kind {
        case .confirmFloor: step.elementID
        case .confirmPortal: home.portal(step.elementID)?.floorID
        case .labelSpace: home.space(step.elementID)?.floorID
        default: home.floors.first?.id
        }
    }
}
