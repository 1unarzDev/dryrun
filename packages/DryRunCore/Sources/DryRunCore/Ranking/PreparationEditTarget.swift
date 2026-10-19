import Foundation

/// Plain task-to-editor contract. Subject IDs are carried intact; UI never guesses from localized titles.
public enum PreparationEditTarget: Sendable, Hashable {
    case contact(ContactRole)
    case family(personID: String?)
    case equipment(String)
    case backups
    case meeting(SavedPlacePurpose)
    case transport
    case home(elementID: String?)
    case homeSetup
    case review
    case water
    case communications
    case housing
    case checklist(id: String, titleKey: String)
    case supplies

    public static func resolve(_ recommendation: Recommendation, home: HomeModel?) -> Self {
        let action = recommendation.actionID
        func subject(_ prefix: String) -> String? {
            guard let value = recommendation.subjectID, value.hasPrefix(prefix + ".") else { return nil }
            return String(value.dropFirst(prefix.count + 1))
        }
        switch action {
        case "prep.contact": return .contact(.other)
        case "prep.outOfAreaContact": return .contact(.outOfAreaContact)
        case "prep.waterUtility", "act.water.save-utility-contact": return .contact(.waterUtility)
        case "prep.nearMeetup", "act.fire.meeting-point": return .meeting(.outsideMeetingPoint)
        case "prep.backupMeetup": return .meeting(.backupMeetingPlace)
        case "prep.reviewCard": return .review
        case "prep.layout": return .homeSetup
        case "prep.shelterPlan":
            if recommendation.subjectID == "manufacturedAdvancePlan" {return .transport}
            return home == nil ? .homeSetup:.home(elementID:home?.annotations.first{$0.kind == .tornadoShelterCandidate}?.spaceID)
        case "prep.helper", "act.assist.assign-helper", "act.fire.helper-reach-plan": return .family(personID: subject("person"))
        case "prep.transport", "act.relocation.arrange", "act.tornado.sturdy-building-plan": return .transport
        case "prep.water", "act.water.store-3day": return .water
        case "act.comms.power-bank": return .communications
        case "act.heat.ask-blower": return .housing
        case "prep.medication":
            if let subject = recommendation.subjectID {
                return .checklist(id: "medication.\(subject)", titleKey: "prep.medication.title")
            }
        case "prep.equipmentSupplies":
            if let id = subject("equipment") { return .checklist(id: "equipmentSupplies.\(id)", titleKey: "prep.equipmentSupplies.title") }
        case "prep.alerts", "act.alerts.enroll-local": return .checklist(id: "alerts", titleKey: "prep.alerts.title")
        case "prep.radio", "act.comms.weather-radio": return .checklist(id: "radio", titleKey: "prep.radio.title")
        case "prep.pets", "act.pets.carrier-plan": return .checklist(id: "pets", titleKey: "prep.pets.title")
        case "act.fire.smoke-alarms": return .checklist(id: "smokeAlarms", titleKey: "prep.smokeAlarms.title")
        case "prep.fireDrill", "act.fire.practice-drill": return .checklist(id: "fireDrill", titleKey: "prep.fireDrill.title")
        case "prep.wellFloodPlan", "act.water.well-test-after-flood": return .checklist(id: "wellFloodPlan", titleKey: "prep.wellFloodPlan.title")
        case "act.flood.higher-ground-plan": return .checklist(id: "floodPlan", titleKey: "prep.floodPlan.title")
        case "act.tornado.choose-shelter", "act.fire.verify-second-exit":
            guard let home else { return .homeSetup }
            let exact = subject("room") ?? subject("space") ?? subject("portal")
            if let exact, home.space(exact) != nil || home.portal(exact) != nil { return .home(elementID: exact) }
            if action == "act.tornado.choose-shelter" {
                return .home(elementID: home.annotations.first { $0.kind == .tornadoShelterCandidate }?.spaceID)
            }
            let opening = home.portals.sorted { $0.id < $1.id }.first {
                $0.kind != .window && $0.verification != .verified && $0.verification != .rejected
            } ?? home.portals.sorted { $0.id < $1.id }.first { $0.kind != .window && $0.leadsToExterior }
            return .home(elementID: opening?.id)
        default: break
        }
        if action.hasPrefix("prep."), BaselinePreparedness.definitions.contains(where: { "prep." + $0.id == action }) {
            return .checklist(id: String(action.dropFirst(5)), titleKey: recommendation.titleKey)
        }
        if let id = subject("equipment") { return .equipment(id) }
        if subject("backup") != nil || action == "act.generator.outdoor-placement" { return .backups }
        return .supplies
    }
}
