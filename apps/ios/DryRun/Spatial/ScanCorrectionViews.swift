import SwiftUI
import DryRunCore

/// The compact card shown in place when an opening is tapped on the plan: what it is, where it leads, whether it can
/// be used, and "Restore what the scan saw". Every answer applies immediately through ScanCorrections.
struct OpeningCorrectionCard: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: HomeModel
    let portalID: String
    /// The room the opening is being read from (the side the family is standing in).
    let fromRoomID: String
    var onRemoved: () -> Void = {}

    private func t(_ key: String) -> String { model.localizer("spatial.card.\(key)") }

    var body: some View {
        if let portal = draft.portal(portalID) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(t("what")).font(.headline)
                ForEach([[ScanCorrections.OpeningType.door, .window], [.openDoorway, .notAnOpening]], id: \.self) { row in
                    HStack(spacing: Theme.Space.s) {
                        ForEach(row, id: \.self) { type in
                            let selected = ScanCorrections.type(of: portal) == type
                            Button { setType(type) } label: {
                                HStack {
                                    Text(t(type == .door ? "door" : type == .window ? "window" : type == .openDoorway ? "doorway" : "none"))
                                        .fixedSize(horizontal: false, vertical: true)
                                    if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                                }
                            }
                            .buttonStyle(ChoiceButtonStyle(selected: selected))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            // Same identifiers as the earlier editor grid (HomePersistenceUITests): door, window, opening.
                            .accessibilityIdentifier("home.opening.type.\(type == .openDoorway ? PortalKind.opening.rawValue : type.rawValue)")
                        }
                    }
                }

                Picker(t("leadsTo"), selection: Binding(get: { leadsTo(portal) }, set: { setLeadsTo($0) })) {
                    // Only rooms the captured opening actually touches; the geometry itself never moves.
                    ForEach(ScanCorrections.leadsToRooms(portalID, from: fromRoomID, in: draft), id: \.self) { roomID in
                        Text(HomeScenePresentation.roomLabel(roomID, in: draft)).tag(roomID)
                    }
                    Text(t("outside")).tag("outside")
                    if leadsTo(portal) == "unknown" { Text(t("notSure")).tag("unknown") }
                }
                .accessibilityIdentifier("opening.leadsTo")

                Toggle(t("notUsable"), isOn: Binding(get: { ScanCorrections.isNotUsable(portal) }, set: { value in
                    draft.edit { try? ScanCorrections.setNotUsable(portalID, value, in: &$0) }
                }))
                .accessibilityIdentifier("opening.notUsable")
                if ScanCorrections.isNotUsable(portal) {
                    Text(t("notUsableNote")).font(.footnote).foregroundStyle(.secondary)
                }

                if draft.scanSnapshot?.portals.contains(where: { $0.id == portalID }) == true,
                   draft.scanSnapshot?.portals.first(where: { $0.id == portalID }) != portal {
                    Button(t("restore"), systemImage: "arrow.counterclockwise") {
                        draft.edit { try? ScanCorrections.restore(portalID, in: &$0) }
                    }
                    .accessibilityIdentifier("opening.restore")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.opening.type")
        }
    }

    private func leadsTo(_ portal: Portal) -> String {
        let other = portal.sideA == .space(fromRoomID) ? portal.sideB : portal.sideA
        switch other { case .space(let id): return id; case .exterior: return "outside"; default: return "unknown" }
    }

    private func setType(_ type: ScanCorrections.OpeningType) {
        draft.edit { try? ScanCorrections.setType(portalID, to: type, in: &$0) }
        if type == .notAnOpening { onRemoved() }
    }

    private func setLeadsTo(_ id: String) {
        let destination: PortalDestination = id == "outside" ? .exterior : .space(id)
        guard id != "unknown" else { return }
        draft.edit { try? ScanCorrections.setLeadsTo(portalID, from: fromRoomID, to: destination, in: &$0) }
    }
}

/// "Check your scan": one question per uncertain opening, the plan focused on it, Skip and Not sure allowed.
struct ScanCheckView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: HomeModel
    @State private var queue: [String] = []
    @State private var position = 0

    private func t(_ key: String) -> String { model.localizer("spatial.card.\(key)") }

    var body: some View {
        // Pushed inside the editor's own navigation stack: a sheet over the editor sheet would dismiss the editor.
        Group {
                if position < queue.count, let portal = draft.portal(queue[position]) {
                    Form {
                        Section {
                            Text(model.localizer("spatial.card.progress", ["n": "\(position + 1)", "total": "\(queue.count)"]))
                                .font(.subheadline).foregroundStyle(.secondary)
                            FloorPlanView(home: draft, routes: [], highlightedFloorID: portal.floorID, highlightedElementID: portal.id)
                                .frame(height: 260)
                                .listRowInsets(EdgeInsets())
                        }
                        Section {
                            OpeningCorrectionCard(draft: $draft, portalID: portal.id, fromRoomID: Self.room(of: portal, in: draft),
                                                  onRemoved: { advance() })
                        }
                        Section {
                            HStack {
                                Button(t("notSure")) { advance() }.accessibilityIdentifier("scanCheck.notSure")
                                Spacer()
                                Button(t("skip")) { advance() }.accessibilityIdentifier("scanCheck.skip")
                                Spacer()
                                Button(t("confirm")) {
                                    draft.edit { home in
                                        if let i = home.portals.firstIndex(where: { $0.id == portal.id }) { home.portals[i].verification = .verified }
                                    }
                                    advance()
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("scanCheck.confirm")
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(t("checked"), systemImage: "checkmark.seal", description: Text(t("checkedDetail")))
                }
            }
        .navigationTitle(t("checkTitle"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("done")) { dismiss() }.accessibilityIdentifier("scanCheck.done") } }
        .onAppear { if queue.isEmpty { queue = ScanCorrections.uncertainOpenings(draft).map(\.id) } }
    }

    private func advance() { position += 1 }

    static func room(of portal: Portal, in home: HomeModel) -> String {
        for side in [portal.sideA, portal.sideB] { if case .space(let id) = side { return id } }
        return home.spaces.first { $0.floorID == portal.floorID }?.id ?? ""
    }
}

/// Editor overview section for scanned homes: guided check, removed openings, revert to the scan.
struct ScanCorrectionSection: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: HomeModel
    @State private var confirmingRevert = false

    private func t(_ key: String) -> String { model.localizer("spatial.card.\(key)") }

    var body: some View {
        if draft.scanSnapshot != nil {
            Section(t("scanSection")) {
                let uncertain = ScanCorrections.uncertainOpenings(draft).count
                NavigationLink { ScanCheckView(draft: $draft) } label: {
                    Label(model.localizer("spatial.card.check", ["count": "\(uncertain)"]), systemImage: "checklist")
                }
                .disabled(uncertain == 0)
                .accessibilityIdentifier("scan.check")
                ForEach(ScanCorrections.removedOpenings(draft)) { portal in
                    HStack {
                        Text(model.localizer("spatial.card.removed", ["room": HomeScenePresentation.roomLabel(ScanCheckView.room(of: portal, in: draft), in: draft)]))
                            .font(.footnote)
                        Spacer()
                        Button(t("restore")) { draft.edit { try? ScanCorrections.restore(portal.id, in: &$0) } }
                    }
                }
                Button(t("revert"), systemImage: "arrow.uturn.backward.circle", role: .destructive) { confirmingRevert = true }
                    .accessibilityIdentifier("scan.revert")
            }
            .confirmationDialog(t("revertConfirm"), isPresented: $confirmingRevert, titleVisibility: .visible) {
                Button(t("revert"), role: .destructive) { draft.edit { try? ScanCorrections.revertToScan(&$0) } }
            }
        }
    }
}
