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
    /// Template placeholders left without values (never braces typed by the household).
    public var unfilledPlaceholders: [String] = []
    /// Optional structure for layout (family card rows). `text` stays the complete, readable line;
    /// renderers may lay these parts out as a table but never show anything that is not also in `text`.
    public var parts: PlanLineParts? = nil
}

/// Layout parts of one recorded line: who or what it is about, labeled values, and a phone number to set apart.
public struct PlanLineParts: Codable, Sendable, Hashable {
    public var subject: String?
    public var detail: String?
    public var fields: [PlanField]
    public var phone: String?
    /// The value is absent ("not provided"), shown as a missing-information state rather than blank.
    public var isMissing: Bool
    public init(subject: String? = nil, detail: String? = nil, fields: [PlanField] = [], phone: String? = nil, isMissing: Bool = false) {
        self.subject = subject; self.detail = detail; self.fields = fields; self.phone = phone; self.isMissing = isMissing
    }
}

public struct PlanField: Codable, Sendable, Hashable {
    public var label: String?
    public var value: String
    public init(label: String? = nil, value: String) { self.label = label; self.value = value }
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
    /// Medical power-outage card for one essential device (equipment ID). A card document stands on its own.
    case outageCard(String)

    public var isOutageCard: Bool { if case .outageCard = self { true } else { false } }
}

public struct PlanPage: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: PlanPageKind
    public var title: String
    public var sections: [PlanSection]
}

/// The validated, localized source for both the on-device viewer and the PDF renderer.
public struct PlanDocument: Codable, Sendable, Hashable {
    public static let schemaVersion = 2
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
    /// Plain-value render inputs, kept separate from geographic map coordinates. Absent in legacy documents.
    public var visualSnapshot: PlanVisualSnapshot? = nil

    public var revisionKey: RevisionKey {
        RevisionKey(householdID: householdID, householdRevision: householdRevision, homeID: homeID,
                    homeRevision: homeRevision, contentVersion: contentVersion, algorithmVersion: "plan/\(Self.schemaVersion)")
    }

    /// True when the plan was built from older household/home/content than `current`.
    public func isStale(household: HouseholdProfile, home: HomeModel?, contentVersion: String, savedPlaces: [SavedPlace]? = nil) -> Bool {
        if schemaVersion != Self.schemaVersion { return true }
        if household.id != householdID || household.revision != householdRevision || (home?.id ?? household.stableHomeID) != homeID
            || (home?.revision ?? 0) != homeRevision || contentVersion != self.contentVersion { return true }
        if let savedPlaces {
            return visualSnapshot?.savedPlaces.sorted { $0.id < $1.id } != HomeMeetingPlaces.placesIncludingLocalMeetup(home: home, places: savedPlaces, recordedAt: household.updatedAt).filter { $0.homeID == homeID }.sorted { $0.id < $1.id }
        }
        return false
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

    /// User-facing validation text follows the selected app language. The diagnostic description
    /// above retains exact keys/IDs for local development; private note contents never enter this text.
    public func localizedDescription(_ localizer: Localizer) -> String {
        let key: String
        switch self {
        case .missingEssentialsPage: key = "plan.validation.missingEssentialsPage"
        case .emptySafetySection: key = "plan.validation.emptySafetySection"
        case .unresolvedKey: key = "plan.validation.unresolvedKey"
        case .unfilledPlaceholder: key = "plan.validation.unfilledPlaceholder"
        case .draftWithoutBanner: key = "plan.validation.draftWithoutBanner"
        case .fallbackWithoutNote: key = "plan.validation.fallbackWithoutNote"
        case .privateNotesLeaked: key = "plan.validation.privateNotesLeaked"
        }
        return localizer(key)
    }
}

public enum PlanValidator {
    public static func validate(_ doc: PlanDocument, household: HouseholdProfile) -> [PlanValidationIssue] {
        var issues: [PlanValidationIssue] = []
        // A household plan needs its essentials page; an outage-card document is its own essentials.
        if !doc.pages.contains(where: { $0.kind == .essentials || $0.kind.isOutageCard }) { issues.append(.missingEssentialsPage) }
        let lines = doc.pages.flatMap(\.sections).flatMap(\.lines)
        for section in doc.pages.flatMap(\.sections) where section.isSafetyCritical && section.lines.isEmpty {
            issues.append(.emptySafetySection(section.id))
        }
        for line in lines {
            if line.text == line.key { issues.append(.unresolvedKey(line.key)) }
            if !line.unfilledPlaceholders.isEmpty { issues.append(.unfilledPlaceholder(line.text)) }
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

/// Canonical geometry and exact route legs for app-layer rendering. No MapKit/UIKit dependencies.
public struct PlanVisualSnapshot: Codable, Sendable, Hashable {
    public var home: HomeModel?
    public var routes: [RouteResult]
    public var savedPlaces: [SavedPlace]
    public var routeScenarioIDs: [String]? = nil
    public var personLabels: [String: String]? = nil
    public var scenarioLabels: [String: String]? = nil
    public var exerciseStates: [PlanExerciseSnapshot]? = nil
    /// Localized once with the document, so both print and phone show exactly the same qualifications.
    public var panelDetails: [String: [String]]? = nil
    public var homeCoordinate: GeographicCoordinate?
    public var fictional: Bool
    public init(home: HomeModel?, routes: [RouteResult], savedPlaces: [SavedPlace], homeCoordinate: GeographicCoordinate?, fictional: Bool, routeScenarioIDs: [String]? = nil, personLabels: [String: String]? = nil, scenarioLabels: [String: String]? = nil, exerciseStates: [PlanExerciseSnapshot]? = nil) {
        self.home = home; self.routes = routes; self.savedPlaces = savedPlaces
        self.homeCoordinate = homeCoordinate; self.fictional = fictional; self.routeScenarioIDs = routeScenarioIDs
        self.personLabels = personLabels; self.scenarioLabels = scenarioLabels; self.exerciseStates = exerciseStates
    }
}
