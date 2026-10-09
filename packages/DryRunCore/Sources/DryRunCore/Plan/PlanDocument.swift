import Foundation

public enum PlanLineStyle: String, Codable, Sendable, Hashable {
    case normal
    /// Safety prohibition ("never ..."). Renders with emphasis; must survive translation intact.
    case prohibition
    /// Phone/contact line. Always printed as text, never only as a QR code.
    case contact
    case caveat
}

public struct PlanLine: Codable, Sendable, Hashable {
    public var text: String
    public var style: PlanLineStyle
    public var key: String
    public var resolvedLocale: String
    public var isFallback: Bool
    public var isDraftTranslation: Bool
    public var sourceIDs: [String]
}

public struct PlanSection: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var heading: String
    public var lines: [PlanLine]
    public var isSafetyCritical: Bool
    public var containsFallback: Bool { lines.contains(where: \.isFallback) }
    public var containsDraft: Bool { lines.contains(where: \.isDraftTranslation) }
}

public enum PlanPageKind: Codable, Sendable, Hashable {
    case essentials
    case scenario(String)
}

public struct PlanPage: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: PlanPageKind
    public var title: String
    public var sections: [PlanSection]
}

/// The validated, localized source for both the on-device viewer and the PDF renderer.
public struct PlanDocument: Codable, Sendable, Hashable {
    public static let schemaVersion = 1
    public var schemaVersion: Int
    public var locale: String
    public var householdID: String
    public var householdRevision: Int
    public var homeID: String
    public var homeRevision: Int
    public var contentVersion: String
    public var generatedAt: Date
    public var reviewedAt: Date?
    public var scenarioIDs: [String]
    public var includesPrivateNotes: Bool
    public var pages: [PlanPage]
    /// Shown on every page when true.
    public var draftTranslationBanner: String?
    /// Shown when any line fell back to English.
    public var fallbackNote: String?
    /// Prototype content review notice (all content is unreviewed in the first build).
    public var contentReviewBanner: String?
    public var footer: String
    public var sourceIDs: [String]

    public var revisionKey: RevisionKey {
        RevisionKey(householdID: householdID, householdRevision: householdRevision, homeID: homeID,
                    homeRevision: homeRevision, contentVersion: contentVersion, algorithmVersion: "plan/\(Self.schemaVersion)")
    }

    /// True when the plan was built from older household/home/content than `current`.
    public func isStale(household: HouseholdProfile, home: HomeModel, contentVersion: String) -> Bool {
        household.id != householdID || household.revision != householdRevision || home.id != homeID
            || home.revision != homeRevision || contentVersion != self.contentVersion
    }
}

public enum PlanValidationIssue: Sendable, Hashable, CustomStringConvertible {
    case missingEssentialsPage
    case emptySafetySection(String)
    case unresolvedKey(String)
    case unfilledPlaceholder(String)
    case draftWithoutBanner
    case fallbackWithoutNote
    case privateNotesLeaked(String)
    public var description: String {
        switch self {
        case .missingEssentialsPage: "missing essentials page"
        case .emptySafetySection(let s): "safety section \(s) is empty"
        case .unresolvedKey(let k): "unresolved key \(k)"
        case .unfilledPlaceholder(let t): "unfilled placeholder in: \(t)"
        case .draftWithoutBanner: "draft translation without visible banner"
        case .fallbackWithoutNote: "English fallback without visible note"
        case .privateNotesLeaked(let id): "private care-plan notes for \(id) included without consent"
        }
    }
}

public enum PlanValidator {
    public static func validate(_ doc: PlanDocument, household: HouseholdProfile) -> [PlanValidationIssue] {
        var issues: [PlanValidationIssue] = []
        if !doc.pages.contains(where: { $0.kind == .essentials }) { issues.append(.missingEssentialsPage) }
        let lines = doc.pages.flatMap(\.sections).flatMap(\.lines)
        for section in doc.pages.flatMap(\.sections) where section.isSafetyCritical && section.lines.isEmpty {
            issues.append(.emptySafetySection(section.id))
        }
        for line in lines {
            if line.text == line.key { issues.append(.unresolvedKey(line.key)) }
            if !Localizer.placeholders(in: line.text).isEmpty { issues.append(.unfilledPlaceholder(line.text)) }
        }
        if lines.contains(where: \.isDraftTranslation) && doc.draftTranslationBanner == nil { issues.append(.draftWithoutBanner) }
        if lines.contains(where: \.isFallback) && doc.fallbackNote == nil { issues.append(.fallbackWithoutNote) }
        if !doc.includesPrivateNotes {
            for eq in household.equipment {
                if let notes = eq.carePlanNotes, !notes.isEmpty, lines.contains(where: { $0.text.contains(notes) }) {
                    issues.append(.privateNotesLeaked(eq.id))
                }
            }
        }
        return issues
    }
}
