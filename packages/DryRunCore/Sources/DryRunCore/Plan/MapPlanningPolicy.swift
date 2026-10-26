import Foundation

/// Purpose and phase are independent: arranging transport before a warning is different from
/// offering street directions as the immediate response. A simulation never establishes road conditions.
public struct MapPlanningContext: Sendable, Hashable {
    public enum Intent: String, Sendable, Hashable {
        case ordinary, structureFire, tornadoShelter, flashFlood, hurricaneAdvance, freezeContinuity, heatContinuity, waterContinuity
    }
    public enum Phase: String, Sendable, Hashable { case advance, incident, simulation }
    public let intent: Intent
    public let phase: Phase
    public init(intent: Intent = .ordinary, phase: Phase = .advance) { self.intent = intent; self.phase = phase }
    public init(hazard: HazardKind, phase: Phase) {
        self.phase = phase
        switch hazard {
        case .homeFire: intent = .structureFire
        case .tornado: intent = .tornadoShelter
        case .flashFlood: intent = .flashFlood
        case .freezePowerLoss: intent = .freezeContinuity
        case .heatGridStrain: intent = .heatContinuity
        case .waterOutage: intent = .waterContinuity
        }
    }

    public var allowsOrdinaryDirections: Bool {
        !(phase == .incident && (intent == .structureFire || intent == .tornadoShelter))
    }
}

/// A planned link between a reviewed indoor route and the household's outdoor gathering point.
/// This is not evidence anyone arrived outside. It intentionally contains no geographic door position.
public struct PlannedExteriorHandoff: Sendable, Hashable {
    public let homeID: String
    public let homeRevision: Int
    public let homeFingerprint: String
    public let exitPortalID: String
    public let meetingPlaceID: String?
    private let route: RouteResult
    private let householdID: String
    private let isExample: Bool

    public init?(route: RouteResult, home: HomeModel, household: HouseholdProfile, places: [SavedPlace]) {
        guard home.id == household.stableHomeID, route.isCurrent(for: home), route.noRouteReason == nil,
              route.request.purpose == nil || route.request.purpose == .outdoorEgress,
              let path = route.primary, path.verificationNeeded.isEmpty,
              let portal = home.portal(path.exitPortalID), portal.leadsToExterior,
              HomeScenePresentation.openingStatus(portal, in: home, request: route.request) == .availableExit else { return nil }
        self.homeID = home.id; self.homeRevision = home.revision; self.homeFingerprint = HomeFingerprint.of(home)
        self.exitPortalID = path.exitPortalID; self.route = route
        self.householdID = household.id; self.isExample = household.isFictional
        self.meetingPlaceID = PlanMapSelection.displayOrder(places).first {
            $0.homeID == home.id && $0.purpose == .outsideMeetingPoint
        }?.id
    }

    public func isCurrent(home: HomeModel, household: HouseholdProfile, places: [SavedPlace]) -> Bool {
        guard household.id == householdID, household.isFictional == isExample,
              home.id == household.stableHomeID, home.id == homeID, home.revision == homeRevision,
              HomeFingerprint.of(home) == homeFingerprint, route.isCurrent(for: home) else { return false }
        if let meetingPlaceID {
            return places.contains { $0.id == meetingPlaceID && $0.homeID == homeID && $0.purpose == .outsideMeetingPoint }
        }
        return true
    }
}

/// Saved planning information, never an active evacuation order or a certified route polyline.
public struct OfficialHurricanePlanning: Sendable, Hashable {
    public let zone: String
    public let routeIDs: [String]
    public let instructions: String
    public let source: SiteHazardSource
    public let destinationPlaceID: String?
}

public enum HurricanePlanningAvailability: Sendable, Hashable {
    case notRecorded
    case needsReview
    case available(OfficialHurricanePlanning)
}

public enum MapPlanningPolicy {
    /// Only independently reviewed catalogs covering the exact jurisdiction can authorize a
    /// planning source. Newer catalog records can revoke an older source's reviewed status.
    public static func reviewedPlanningSourceURLs(packs: [RegionPack], jurisdictionID: String, at date: Date) -> Set<String> {
        let dated = packs.compactMap { pack -> (RegionPack, Date, Bool)? in
            guard pack.classification == .curated || pack.classification == .live,
                  pack.regions.contains(where: { $0.id == jurisdictionID }),
                  let generated = PublicDataPolicy.parseDate(pack.generatedAt), generated <= date else { return nil }
            let isCurrent = pack.expiresAt.map { PublicDataPolicy.parseDate($0).map { date < $0 } ?? false } ?? true
            return (pack, generated, isCurrent)
        }.sorted { ($0.1, $0.0.packID) < ($1.1, $1.0.packID) }
        var byID: [String: (source: SourceRef, isCurrent: Bool)] = [:]
        for (pack, _, isCurrent) in dated { for source in pack.sources { byID[source.id] = (source, isCurrent) } }
        return Set(byID.values.filter { $0.isCurrent && $0.source.reviewState == .reviewed }.map { $0.source.url })
    }

    /// Exact URLs from the app's independently reviewed source catalog, not a model-issued or
    /// household-entered URL allowlist. A source label or a government-looking host is insufficient.
    public static func hurricanePlanning(household: HouseholdProfile, places: [SavedPlace],
                                        approvedSourceURLs: Set<String>, at date: Date) -> HurricanePlanningAvailability {
        guard let profile = household.siteHazards, let plan = profile.hurricane else { return .notRecorded }
        guard profile.schemaVersion == "dryrun.site-hazards/1", profile.jurisdictionID == household.regionID,
              profile.locationBinding == SiteHazardBinding.of(household),
              profile.sources.count <= 20, Set(profile.sources.map(\.id)).count == profile.sources.count,
              let source = profile.sources.first(where: { $0.id == plan.sourceID }),
              source.usable(at: date, jurisdictionID: household.regionID), approvedSourceURLs.contains(source.url),
              !plan.zone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !plan.routeIDs.isEmpty, plan.routeIDs.count <= 8,
              plan.routeIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return .needsReview }
        let destination = plan.destinationPlaceID.flatMap { id in
            places.first { $0.id == id && $0.homeID == household.stableHomeID }?.id
        }
        return .available(OfficialHurricanePlanning(zone: plan.zone, routeIDs: plan.routeIDs, instructions: plan.instructions,
                                                    source: source, destinationPlaceID: destination))
    }
}
