import Foundation

/// Reconciles answers from the shared checklist without turning a location-only edit into an ownership edit.
public enum PreparationDraft {
    public static func synchronizeSupplyAnswers(_ draft: inout HouseholdProfile, original: HouseholdProfile) {
        func changed(_ id: String) -> EvidenceValue<Bool>? {
            let before = original.preparedness?.items[id]?.available ?? .unknown
            let after = draft.preparedness?.items[id]?.available ?? .unknown
            return before == after ? nil : after
        }
        if let answer = changed("firstAid") { draft.supplies.firstAidKit = answer }
        if let answer = changed("extinguisher") { draft.supplies.fireExtinguisher = answer }
        if let answer = changed("flashlight") {
            if let available = answer.confirmedValue {
                if !available { draft.supplies.flashlights = .confirmed(0) }
                else if (draft.supplies.flashlights.confirmedValue ?? 0) < 1 { draft.supplies.flashlights = .confirmed(1) }
            } else { draft.supplies.flashlights = .unknown }
        }
    }
}
