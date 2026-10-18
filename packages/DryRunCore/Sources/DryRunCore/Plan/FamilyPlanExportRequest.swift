import Foundation

/// Immutable selections for one export. The UI captures these before asynchronous generation begins.
/// Failure to generate a requested plan must not fall back to a retained document with different consent.
public struct FamilyPlanExportRequest: Sendable, Hashable {
    public let includePlan: Bool
    public let includeCard: Bool
    public let includePrivateNotes: Bool
    public let selection: FamilyCardSelection

    public init(includePlan: Bool, includeCard: Bool, includePrivateNotes: Bool, selection: FamilyCardSelection) {
        self.includePlan = includePlan; self.includeCard = includeCard
        self.includePrivateNotes = includePrivateNotes; self.selection = selection
    }

    /// `generatedPlan` must be the successful result of this request, never a previously retained plan.
    public func document(generatedPlan: PlanDocument?, card: PlanDocument?) -> PlanDocument? {
        guard includePlan || includeCard else { return nil }
        if includePlan && generatedPlan == nil { return nil }
        if includeCard {
            guard let card, !card.pages.isEmpty else { return nil }
        }
        guard var document = includePlan ? generatedPlan : card else { return nil }
        document.pages.removeAll { $0.id == "family-card" }
        if includeCard, let card {
            document.pages = card.pages + document.pages
            document.draftTranslationBanner = document.draftTranslationBanner ?? card.draftTranslationBanner
            document.fallbackNote = document.fallbackNote ?? card.fallbackNote
            document.sourceIDs = Array(Set(document.sourceIDs + card.sourceIDs)).sorted()
        }
        return document.pages.isEmpty ? nil : document
    }
}
