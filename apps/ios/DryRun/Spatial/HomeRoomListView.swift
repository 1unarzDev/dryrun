import SwiftUI
import DryRunCore

// Accessible text representation of the home: a first-class view, not a fallback.
// Returns rows for use INSIDE a List section (no nested List / NavigationStack).
// AUTHORED, NOT COMPILED in this environment.

struct HomeRoomListView: View {
    private func s(_ english: String) -> String { SpatialStrings.text(english, localizer: model.localizer) }
    @Environment(AppModel.self) private var model
    let home: HomeModel

    init(home: HomeModel) { self.home = home }

    var body: some View {
        ForEach(home.floors.sorted { $0.level < $1.level }) { floor in
            DisclosureGroup {
                ForEach(home.spaces.filter { $0.floorID == floor.id }) { space in
                    spaceRow(space)
                }
            } label: {
                Text(floor.label).font(.headline)
            }
        }
        DisclosureGroup(s("Exits and outside openings")) {
            let exterior = home.portals.filter { $0.leadsToExterior || isCommonArea($0) }
            if exterior.isEmpty { Text(s("No outside doors recorded yet.")) }
            ForEach(exterior) { portalRow($0) }
        }
        if !home.connectors.isEmpty {
            DisclosureGroup(s("Stairs and floor connections")) {
                ForEach(home.connectors) { c in
                    VStack(alignment: .leading) {
                        Text("\(model.localizer("spatial.connector.\(c.kind.rawValue)")): \(label(c.fromSpaceID)) ↔ \(label(c.toSpaceID))")
                        Text(stateText(c.verification)).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        DisclosureGroup(s("Safety markers")) {
            let markers = home.annotations.sorted { priority($0.kind) < priority($1.kind) }
            if markers.isEmpty { Text(s("No markers yet. Add smoke alarms and a meeting point.")) }
            ForEach(markers) { a in
                Label {
                    VStack(alignment: .leading) {
                        Text(a.label)
                        Text([a.spaceID.map(label) ?? s("Outside"), stateText(a.verification)].joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if let note = a.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                    }
                } icon: {
                    Image(systemName: FloorPlanView.symbol(a.kind))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func spaceRow(_ space: Space) -> some View {
        let doors = home.portals.filter { p in p.sideA == .space(space.id) || p.sideB == .space(space.id) }
        let area = abs(Geometry.signedArea(space.polygon)).formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: model.locale)))
        return VStack(alignment: .leading, spacing: 2) {
            Text(space.label + (space.labelConfirmed ? "" : " " + s("(name not confirmed)")))
            Text(model.localizer("spatial.room-area", ["area": area]) + (space.needsMeasurement ? " · " + s("needs measurement") : ""))
                .font(.caption).foregroundStyle(.secondary)
            if space.geometryNeedsReview == true { Text(model.localizer("spatial.issue.correctedGeometryNeedsReview")).font(.caption) }
            ForEach(doors) { p in
                Text(model.localizer("spatial.opening-summary", ["kind": DisplayNames.name(p.kind.rawValue, localizer: model.localizer), "destination": destination(p, from: space.id), "status": stateText(p.verification)]))
                    .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func portalRow(_ p: Portal) -> some View {
        let inside = [p.sideA, p.sideB].compactMap { if case .space(let id) = $0 { return label(id) }; return nil }.first ?? "?"
        var facts: [String] = [stateText(p.verification)]
        if p.kind == .window { facts.append(s("window — not counted as an exit")) }
        if isCommonArea(p) { facts.append(s("opens to a shared building area that is not modelled")) }
        if let w = p.clearWidthMeters.value {
            let width = w.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: model.locale)))
            facts.append(model.localizer("spatial.opening-width", ["width": width]) + (p.clearWidthMeters.isConfirmed ? "" : " · " + model.localizer("spatial.scanned-unconfirmed")))
        }
        else if p.kind != .window { facts.append(s("width not measured")) }
        if let sf = p.stepFree.value { facts.append(s(sf ? "step-free" : "has a step")) }
        if p.operable.value == nil && p.kind != .opening { facts.append(s("opening not confirmed")) }
        return VStack(alignment: .leading, spacing: 2) {
            Text(model.localizer("spatial.opening-from", ["opening": p.note ?? DisplayNames.name(p.kind.rawValue, localizer: model.localizer), "room": inside]))
            Text(facts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func isCommonArea(_ p: Portal) -> Bool {
        [p.sideA, p.sideB].contains { if case .commonArea = $0 { return true }; return false }
    }

    private func destination(_ p: Portal, from id: String) -> String {
        let other = p.sideA == .space(id) ? p.sideB : p.sideA
        switch other {
        case .space(let sid): return label(sid)
        case .exterior: return s("outside")
        case .commonArea: return s("building corridor")
        case .unknown: return s("unknown")
        }
    }

    private func label(_ id: String) -> String { home.space(id)?.label ?? id }

    private func stateText(_ v: VerificationState) -> String {
        switch v {
        case .verified: return s("Confirmed")
        case .proposed: return s("Needs confirmation")
        case .unknown: return s("Unknown")
        case .rejected: return s("Marked not usable")
        }
    }

    private func priority(_ k: AnnotationKind) -> Int {
        switch k {
        case .outsideMeetingPoint: return 0
        case .smokeAlarm: return 1
        case .coAlarm: return 2
        case .medicalEquipment: return 3
        case .tornadoShelterCandidate: return 4
        case .fireExtinguisher: return 5
        case .utilityShutoffElectric, .utilityShutoffGas, .utilityShutoffWater: return 6
        case .supplies: return 7
        case .exteriorHydrant: return 9
        }
    }
}
