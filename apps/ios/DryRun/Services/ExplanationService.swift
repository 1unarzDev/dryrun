import Foundation
import DryRunCore
#if canImport(FoundationModels)
import FoundationModels
#endif

enum ExplanationAvailability: Equatable {
    case available
    case unavailable(reason: String)
}

/// OPTIONAL on-device prose. The deterministic core owns every number, route, priority, instruction, and source.
/// The model only rephrases an already-computed explanation; output is shown only after validation, otherwise
/// the template text is used. Never translates safety-critical directions; never uses a cloud fallback.
enum ExplanationService {
    static func availability() -> ExplanationAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                return .unavailable(reason: String(describing: reason))
            @unknown default:
                return .unavailable(reason: "Unknown availability state")
            }
        }
        return .unavailable(reason: "Requires a newer iOS version")
        #else
        return .unavailable(reason: "Foundation Models framework not present in this SDK")
        #endif
    }

    /// Returns optional explanatory prose for a recommendation, or nil to use the template.
    /// Evidence bundle = IDs and template text that the deterministic engine already produced.
    static func explain(templateText: String, recommendation: Recommendation, locale: String) async -> String? {
        // Only English prose in the first build; other locales use reviewed/draft templates, never live translation.
        // The optional prose seam receives only unparameterized, noncritical authored text. Person/device names,
        // clinical notes, address, contacts, geometry and route decisions are never model inputs, including locally.
        guard locale == "en", recommendation.tier == .general,
              recommendation.subjectID == nil, recommendation.templateValues.isEmpty,
              Localizer.placeholders(in: templateText).isEmpty,
              availability() == .available else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let instructions = """
            You rewrite one short explanation for a household disaster-preparedness exercise in plain, calm English.
            Use ONLY the facts given. Do not add numbers, durations, medical advice, safety instructions, or new actions.
            Do not mention probabilities, survival, or deadlines. Two sentences maximum.
            """
            let session = LanguageModelSession(instructions: instructions)
            let prompt = "Explanation to rephrase: \(templateText)"
            do {
                let response = try await session.respond(to: prompt)
                let text = response.content
                return ExplanationValidator.accept(candidate: text, template: templateText) ? text : nil
            } catch {
                // Refusal, guardrail, unsupported language, context or timeout: fall back to the template.
                return nil
            }
        }
        #endif
        return nil
    }
}

/// Conservative acceptance check. Because free-text accuracy cannot be proven, the prose is rejected
/// when it introduces any digit not in the template, imperative safety verbs, or medical terms.
enum ExplanationValidator {
    static let blockedTerms = ["dose", "medication", "minutes", "hours", "survive", "safe to", "probability", "%",
                               "call 911", "evacuate now", "boil"]

    static func accept(candidate: String, template: String) -> Bool {
        let c = candidate.lowercased()
        guard !c.isEmpty, c.count <= 400 else { return false }
        let templateDigits = Set(template.filter(\.isNumber))
        if candidate.contains(where: { $0.isNumber && !templateDigits.contains($0) }) { return false }
        return !blockedTerms.contains { c.contains($0) && !template.lowercased().contains($0) }
    }
}
