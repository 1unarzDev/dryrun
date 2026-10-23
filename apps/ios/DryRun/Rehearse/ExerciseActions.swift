import Foundation
import DryRunCore

/// Typed actions a family can take in an exercise, built from the household's own records. Shared by the adaptive
/// exercise and the practice check so neither singles out "the right" action; the host previews each one and only
/// accepted actions are shown.
///
/// Hazard choices come first: the host's `receipt.experience.feasibleCommands`, described by person, purpose and
/// destination (who gets out through which exit, who goes to which room, which device gets which backup). Generic
/// "move someone" or "helper" choices are not offered when the exercise has hazard choices.
enum ExerciseActions {
    struct Option: Sendable, Hashable {
        let title: String
        let symbol: String
        let commands: [SessionCommand]
        /// Accessibility identifier: `rehearsal.cmd.<kind>.<target>.<value>` for hazard choices.
        var identifier: String = "adaptive.action"
        /// A recognition-only note (identifyGap): shown apart from the actions that change the exercise.
        var isNote = false
        /// Built from the receipt's hazard commands (not a generic power/contact/water-policy/door extra).
        var isHazardChoice = false
    }

    /// Whether the exercise describes its own hazard choices (adaptive mechanics with an experience).
    static func hasHazardChoices(_ receipt: SessionReceipt) -> Bool { receipt.experience?.feasibleCommands != nil }

    /// The host's validated hazard commands as person/purpose/destination choices, primary objective first.
    static func hazardOptions(session: SimulationSession, receipt: SessionReceipt, localizer l: Localizer) -> [Option] {
        let h = session.initial.household
        return HazardChoices.options(receipt, household: h, home: session.initial.home).compactMap { choice in
            guard let title = title(choice, session: session, receipt: receipt, localizer: l) else { return nil }
            return Option(title: title, symbol: symbol(choice.purpose), commands: [choice.command],
                          identifier: "rehearsal.cmd.\(choice.id)", isNote: !choice.isAction, isHazardChoice: choice.isAction)
        }
    }

    static func candidates(session: SimulationSession, receipt: SessionReceipt, localizer l: Localizer) -> [Option] {
        let h = session.initial.household
        let hazard = hazardOptions(session: session, receipt: receipt, localizer: l)
        let covered = Set(hazard.flatMap(\.commands).map(\.kind))
        var out = hazard
        if receipt.snapshot.resources["res.water.stored"] != nil {
            out.append(.init(title: l("adaptive.water.essential"), symbol: "drop", commands: [.init(kind: "useStoredWater", value: "essential")],
                             identifier: "rehearsal.cmd.useStoredWater.essential"))
            out.append(.init(title: l("adaptive.water.all"), symbol: "drop.fill", commands: [.init(kind: "useStoredWater", value: "all")],
                             identifier: "rehearsal.cmd.useStoredWater.all"))
        }
        if !covered.contains("allocatePower") {
            for equipment in h.equipment where !equipment.compatibleBackupIDs.isEmpty {
                let device = HouseholdLabels.equipment(equipment.id, in: h, localizer: l)
                for backup in equipment.compatibleBackupIDs {
                    out.append(.init(title: l("adaptive.power", ["device": device, "backup": HouseholdLabels.backup(backup, in: h, localizer: l)]),
                                     symbol: "bolt", commands: [.init(kind: "allocatePower", target: equipment.id, value: backup)],
                                     identifier: "rehearsal.cmd.allocatePower.\(equipment.id).\(backup)"))
                }
                out.append(.init(title: l("adaptive.powerNone", ["device": device]), symbol: "bolt.slash",
                                 commands: [.init(kind: "allocatePower", target: equipment.id, value: "none")],
                                 identifier: "rehearsal.cmd.allocatePower.\(equipment.id).none"))
            }
        }
        if !covered.contains("contact") {
            for contact in h.contacts where contact.isComplete {
                out.append(.init(title: l("adaptive.contact", ["contact": contact.alias]), symbol: "phone",
                                 commands: [.init(kind: "contact", target: contact.id)], identifier: "rehearsal.cmd.contact.\(contact.id)"))
            }
        }
        // A generic "X helps Y" flag is replaced by the hazard's own accompaniment choices when it has them.
        if !hasHazardChoices(receipt) {
            for person in h.people where !person.needs.isEmpty {
                for helper in h.people where helper.id != person.id && helper.needs.isEmpty {
                    out.append(.init(title: l("adaptive.helper", ["helper": helper.localizedLabel(l), "person": person.localizedLabel(l)]),
                                     symbol: "figure.2", commands: [.init(kind: "assignHelper", target: person.id, value: helper.id)]))
                }
            }
        }
        if session.initial.scenarioID == "home-fire", let home = session.initial.home {
            // Only doors next to where each person is now; the host still previews every one.
            let rooms = receipt.experience?.occupantRoomIDs
            for portal in home.portals where portal.kind == .door {
                let sides = [portal.sideA, portal.sideB].compactMap { side -> String? in
                    if case .space(let id) = side { return id }
                    return nil
                }
                let label = sides.map { HomeScenePresentation.roomLabel($0, in: home) }.joined(separator: " / ")
                for person in h.people {
                    if let room = rooms?[person.id], !sides.contains(room) { continue }
                    out.append(.init(title: l("adaptive.closeDoor", ["person": person.localizedLabel(l), "rooms": label]),
                                     symbol: "door.left.hand.closed", commands: [.init(kind: "closeDoor", target: portal.id, value: person.id)],
                                     identifier: "rehearsal.cmd.closeDoor.\(portal.id).\(person.id)"))
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

    // MARK: Describing a command

    /// A title for any committed or offered command, from the command itself rather than whether it is still feasible.
    static func describe(_ command: SessionCommand, session: SimulationSession, receipt: SessionReceipt, localizer l: Localizer) -> String? {
        let h = session.initial.household
        if command.kind == "wait" { return l("rehearsal.cmd.wait") }
        if let choice = HazardChoices.describe(command, receipt: receipt, household: h, home: session.initial.home),
           let title = title(choice, session: session, receipt: receipt, localizer: l) { return title }
        return candidates(session: session, receipt: receipt, localizer: l).first { $0.commands == [command] }?.title
    }

    /// What the app did with a committed command, in the family's words; nil when no specific note exists.
    static func doneNote(_ command: SessionCommand, localizer l: Localizer) -> String {
        let key = "rehearsal.cmd.done.\(command.kind)"
        return l.has(key, in: "en") ? l(key) : l("simulation.user.\(command.kind)")
    }

    static func symbol(_ purpose: HazardChoice.Purpose) -> String {
        switch purpose {
        case .escape: return "figure.walk.departure"
        case .accompanyEscape: return "figure.2"
        case .accountOutside: return "checklist"
        case .shelter: return "shield.lefthalf.filled"
        case .accompanyShelter: return "figure.2.arms.open"
        case .refuge: return "stairs"
        case .depart: return "car"
        case .warmth: return "thermometer.snowflake"
        case .shade: return "blinds.horizontal.closed"
        case .moveToShade: return "figure.walk"
        case .gather: return "person.3"
        case .power: return "bolt"
        case .contact: return "phone"
        case .water: return "drop"
        case .carrySupply: return "shippingbox"
        case .placeSupply: return "tray.and.arrow.down"
        case .recognizeGap: return "questionmark.circle"
        }
    }

    static func title(_ c: HazardChoice, session: SimulationSession, receipt: SessionReceipt, localizer l: Localizer) -> String? {
        let h = session.initial.household
        let home = session.initial.home
        func person(_ id: String?) -> String { h.people.first { $0.id == id }?.localizedLabel(l) ?? l("ui.person") }
        func room(_ id: String?) -> String {
            guard let id, let home, home.space(id) != nil else { return l("rehearsal.cmd.unknownRoom") }
            return HomeScenePresentation.roomLabel(id, in: home)
        }
        switch c.purpose {
        case .escape:
            return l("rehearsal.cmd.escape", ["person": person(c.personID), "room": room(c.roomID)])
        case .accompanyEscape:
            return l("rehearsal.cmd.accompanyEscape", ["helper": person(c.helperID), "person": person(c.personID), "room": room(c.roomID)])
        case .accountOutside:
            return l("rehearsal.cmd.accountOutside", ["person": person(c.personID)])
        case .shelter:
            return l("rehearsal.cmd.reachShelter", ["person": person(c.personID), "room": room(c.roomID)])
        case .accompanyShelter:
            return l("rehearsal.cmd.accompanyShelter", ["helper": person(c.helperID), "person": person(c.personID), "room": room(c.roomID)])
        case .refuge:
            return l("rehearsal.cmd.reachHigherRefuge", ["person": person(c.personID), "room": room(c.roomID)])
        case .depart:
            let destination = h.transport.destinations.first { $0.id == c.destinationID }?.label ?? l("rehearsal.cmd.unknownDestination")
            return l("rehearsal.cmd.\(c.command.kind)", ["destination": destination])
        case .warmth:
            return l("rehearsal.cmd.warmLayers")
        case .shade:
            return l("rehearsal.cmd.reduceSolarGain", ["room": room(c.roomID)])
        case .moveToShade:
            return l("rehearsal.cmd.moveToShade", ["person": person(c.personID), "room": room(c.roomID)])
        case .gather:
            // "{person} goes to {room}": existing neutral copy, present in every bundled language (no new keys).
            return l("rehearsal.cmd.reachShelter", ["person": person(c.personID), "room": room(c.roomID)])
        case .power:
            guard let equipment = c.equipmentID else { return nil }
            let device = HouseholdLabels.equipment(equipment, in: h, localizer: l)
            if c.backupID == "none" { return l("adaptive.powerNone", ["device": device]) }
            return l("adaptive.power", ["device": device, "backup": HouseholdLabels.backup(c.backupID ?? "", in: h, localizer: l)])
        case .contact:
            guard let contact = h.contacts.first(where: { $0.id == c.contactID }) else { return nil }
            return l("adaptive.contact", ["contact": contact.alias])
        case .water:
            guard let activity = c.activity else { return nil }
            let source = c.waterSource == "tap" ? "tap" : "stored"
            let amount = c.quantityLiters.map { l("rehearsal.cmd.liters", ["amount": $0.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: l.locale)))]) } ?? ""
            return l("rehearsal.cmd.water.\(source).\(activity)", ["amount": amount])
        case .carrySupply:
            return l("rehearsal.cmd.takeSupply", ["person": person(c.personID), "item": item(c.itemID, receipt: receipt, localizer: l)])
        case .placeSupply:
            return l("rehearsal.cmd.transferSupply", ["item": item(c.itemID, receipt: receipt, localizer: l), "room": room(c.roomID)])
        case .recognizeGap:
            guard let gap = c.gapID else { return nil }
            return l("rehearsal.cmd.identifyGap", ["gap": gapName(gap, session: session, localizer: l)])
        }
    }

    static func item(_ id: String?, receipt: SessionReceipt, localizer l: Localizer) -> String {
        let category = receipt.inventory?.items.first { $0.id == id }?.category ?? "other"
        let key = "rehearsal.cmd.item.\(category)"
        return l.has(key, in: "en") ? l(key) : l("rehearsal.cmd.item.other")
    }

    /// A planning gap in words: hazard gaps have their own names; recorded unknowns use the shared fact names.
    static func gapName(_ id: String, session: SimulationSession, localizer l: Localizer) -> String {
        let h = session.initial.household
        if l.has("rehearsal.cmd.gap.\(id)", in: "en") { return l("rehearsal.cmd.gap.\(id)") }
        for base in ["escapeAssistance", "higherRefuge"] where id.hasPrefix(base + ".") {
            let personID = String(id.dropFirst(base.count + 1))
            let name = h.people.first { $0.id == personID }?.localizedLabel(l) ?? l("ui.person")
            return l("rehearsal.cmd.gap.\(base).person", ["person": name])
        }
        return UnknownNames.describe(id, household: h, localizer: l)
    }

    // MARK: Recorded consequences

    /// Debrief facts the family can read, in their words. Facts without a family-facing sentence (traces,
    /// requirement IDs, internal scene summaries) are left to the debrief and director, not shown raw.
    static func facts(_ receipt: SessionReceipt, session: SimulationSession, localizer l: Localizer) -> [(id: String, text: String)] {
        guard let experience = receipt.experience else { return [] }
        let h = session.initial.household
        let home = session.initial.home
        var out: [(String, String)] = []
        var seen = Set<String>()
        for fact in experience.debrief {
            let key = "rehearsal.cmd.fact.\(fact.kind)"
            guard l.has(key, in: "en") else { continue }
            let people = fact.subjectIDs.compactMap { id in h.people.first { $0.id == id }?.localizedLabel(l) }
            let rooms = fact.subjectIDs.compactMap { id in home?.space(id) != nil ? HomeScenePresentation.roomLabel(id, in: home!) : nil }
            let devices = fact.subjectIDs.compactMap { id in h.equipment.contains { $0.id == id } ? HouseholdLabels.equipment(id, in: h, localizer: l) : nil }
            // A roster fact about nobody says nothing.
            if ["notYetSheltered", "outsideAccounting"].contains(fact.kind), people.isEmpty { continue }
            let text = l(key, ["people": ListFormatter.localizedString(byJoining: people), "rooms": ListFormatter.localizedString(byJoining: rooms),
                               "devices": ListFormatter.localizedString(byJoining: devices)])
            let id = fact.kind + "|" + fact.subjectIDs.joined(separator: ",")
            if seen.insert(text).inserted { out.append((id, text)) }
        }
        return out
    }
}
