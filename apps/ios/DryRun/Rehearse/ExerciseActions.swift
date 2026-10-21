import Foundation
import DryRunCore

/// Typed actions a family can take in an exercise, built from the household's own records. Shared by the adaptive
/// exercise and the practice check so neither singles out "the right" action; the host previews each one and only
/// accepted actions are shown. Moves are chosen separately (person + room).
enum ExerciseActions {
    struct Option: Sendable, Hashable {
        let title: String
        let symbol: String
        let commands: [SessionCommand]
    }

    static func candidates(session: SimulationSession, receipt: SessionReceipt, localizer l: Localizer) -> [Option] {
        let h = session.initial.household
        var out: [Option] = []
        if receipt.snapshot.resources["res.water.stored"] != nil {
            out.append(.init(title: l("adaptive.water.essential"), symbol: "drop", commands: [.init(kind: "useStoredWater", value: "essential")]))
            out.append(.init(title: l("adaptive.water.all"), symbol: "drop.fill", commands: [.init(kind: "useStoredWater", value: "all")]))
        }
        for equipment in h.equipment where !equipment.compatibleBackupIDs.isEmpty {
            let device = HouseholdLabels.equipment(equipment.id, in: h, localizer: l)
            for backup in equipment.compatibleBackupIDs {
                out.append(.init(title: l("adaptive.power", ["device": device, "backup": HouseholdLabels.backup(backup, in: h, localizer: l)]),
                                 symbol: "bolt", commands: [.init(kind: "allocatePower", target: equipment.id, value: backup)]))
            }
            out.append(.init(title: l("adaptive.powerNone", ["device": device]), symbol: "bolt.slash",
                             commands: [.init(kind: "allocatePower", target: equipment.id, value: "none")]))
        }
        for contact in h.contacts where contact.isComplete {
            out.append(.init(title: l("adaptive.contact", ["contact": contact.alias]), symbol: "phone",
                             commands: [.init(kind: "contact", target: contact.id)]))
        }
        for person in h.people where !person.needs.isEmpty {
            for helper in h.people where helper.id != person.id && helper.needs.isEmpty {
                out.append(.init(title: l("adaptive.helper", ["helper": helper.localizedLabel(l), "person": person.localizedLabel(l)]),
                                 symbol: "figure.2", commands: [.init(kind: "assignHelper", target: person.id, value: helper.id)]))
            }
        }
        if session.initial.scenarioID == "home-fire", let home = session.initial.home {
            for portal in home.portals where portal.kind == .door {
                let rooms = [portal.sideA, portal.sideB].compactMap { side -> String? in
                    if case .space(let id) = side { return HomeScenePresentation.roomLabel(id, in: home) }
                    return nil
                }
                for person in h.people {
                    out.append(.init(title: l("adaptive.closeDoor", ["person": person.localizedLabel(l), "rooms": rooms.joined(separator: " / ")]),
                                     symbol: "door.left.hand.closed", commands: [.init(kind: "closeDoor", target: portal.id, value: person.id)]))
                }
            }
        }
        return out
    }

    /// Host previews off the main actor: which candidates the session would accept at its current revision.
    static func accepted(_ candidates: [Option], session: SimulationSession, library: ScenarioLibrary) async -> [Option] {
        await Task.detached(priority: .userInitiated) {
            candidates.filter { option in
                (try? session.preview(SessionCommit(id: "preview", actor: "user", baseRevision: session.revision,
                                                    commands: option.commands), library: library)) != nil
            }
        }.value
    }
}
