import Foundation

/// Stable domain cues for native task rows and accepted Gemini task selections. These symbols
/// describe the action, never completion, evidence authority or real-world safety.
public enum PreparationPresentation {
    public static func symbol(actionID: String) -> String {
        switch NextSteps.preparationActionID(for: actionID) {
        case "prep.water", "prep.wellFloodPlan": "drop.fill"
        case "prep.food", "prep.coldStorage": "fork.knife"
        case "prep.smokeAlarms", "prep.coAlarms": "sensor"
        case "prep.extinguisher": "fire.extinguisher"
        case "prep.clearExits", "act.fire.verify-second-exit": "door.left.hand.open"
        case "prep.fireDrill": "figure.walk.departure"
        case "prep.shelterPlan", "act.tornado.choose-shelter": "tornado"
        case "prep.layout": "square.3.layers.3d"
        case "prep.floodPlan": "water.waves"
        case "prep.medicalBackup", "act.generator.outdoor-placement": "bolt.heart"
        case "prep.medication", "prep.equipmentSupplies", "prep.firstAid": "cross.case"
        case "prep.helper": "person.2.fill"
        case "prep.pets": "pawprint.fill"
        case "prep.contact", "prep.outOfAreaContact", "prep.waterUtility", "prep.reconnect": "phone"
        case "prep.nearMeetup", "prep.backupMeetup": "mappin.and.ellipse"
        case "prep.transport", "act.relocation.arrange", "act.tornado.sturdy-building-plan": "figure.walk"
        case "prep.alerts", "prep.radio": "antenna.radiowaves.left.and.right"
        case "prep.batteries", "act.comms.power-bank": "battery.100percent"
        case "prep.flashlight": "flashlight.on.fill"
        case "prep.heatCold", "act.heat.ask-blower": "thermometer.medium"
        case "prep.sanitation": "hands.sparkles"
        case "prep.reviewCard": "person.text.rectangle"
        default: "checklist"
        }
    }
}
