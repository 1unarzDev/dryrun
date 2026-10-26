import Foundation
import Testing
@testable import DryRunCore

@Suite("Hazard-aware map planning boundaries")
struct MapPlanningPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let sourceURL = "https://emergency.example.test/local-plan"

    @Test func earlyShelterTransportRemainsAvailableButImmediateShelterDoesNotBecomeStreetRouting() {
        for phase in [MapPlanningContext.Phase.advance, .simulation] {
            #expect(MapPlanningContext(intent: .tornadoShelter, phase: phase).allowsOrdinaryDirections)
        }
        #expect(!MapPlanningContext(intent: .tornadoShelter, phase: .incident).allowsOrdinaryDirections)
        #expect(!MapPlanningContext(intent: .structureFire, phase: .incident).allowsOrdinaryDirections)
        for intent in [MapPlanningContext.Intent.ordinary, .flashFlood, .hurricaneAdvance, .freezeContinuity, .heatContinuity, .waterContinuity] {
            #expect(MapPlanningContext(intent: intent).allowsOrdinaryDirections)
        }
    }

    @Test func plannedExitLinksTextOnlyGatheringWithoutInventingDoorRegistration() throws {
        let home = SampleHomes.ranch
        var household = SampleHouseholds.oak; household.homeID = home.id
        let point = SavedPlace(id: "gather", homeID: home.id, purpose: .outsideMeetingPoint, label: "Fictional gathering point", findingInstructions: "Across the yard")
        let backup = SavedPlace(id: "backup", homeID: home.id, purpose: .backupMeetingPlace, label: "Fictional backup")
        let route = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-living"), in: home)
        let handoff = try #require(PlannedExteriorHandoff(route: route, home: home, household: household, places: [backup, point]))
        #expect(handoff.meetingPlaceID == point.id)
        #expect(handoff.exitPortalID == route.primary?.exitPortalID)
        #expect(handoff.isCurrent(home: home, household: household, places: [point]))
        #expect(!handoff.isCurrent(home: home, household: household, places: [backup]))
        var changed = home; changed.revision += 1
        #expect(!handoff.isCurrent(home: changed, household: household, places: [point]))
        #expect(PlannedExteriorHandoff(route: route, home: changed, household: household, places: [point]) == nil)
        var other = household; other.isFictional = false
        #expect(!handoff.isCurrent(home: home, household: other, places: [point]))
        var uncertain = route; uncertain.primary?.verificationNeeded = ["unreviewed-threshold"]
        #expect(PlannedExteriorHandoff(route: uncertain, home: home, household: household, places: [point]) == nil)
        let shelter = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-living", purpose: .interiorShelter, destinationSpaceID: "sp-closet"), in: home)
        #expect(PlannedExteriorHandoff(route: shelter, home: home, household: household, places: [point]) == nil)
        let blocked = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-living", exclusions: ScenarioExclusions(blockedPortalIDs: home.portals.map(\.id))), in: home)
        #expect(PlannedExteriorHandoff(route: blocked, home: home, household: household, places: [point]) == nil)
    }

    @Test func officialPlanningNeedsExactApprovedSourceLocationAndCurrentEvidence() throws {
        let household = withHurricanePlan()
        let places = [SavedPlace(id: "destination", homeID: household.stableHomeID, purpose: .fallbackDestination, label: "Fictional destination")]
        let result = MapPlanningPolicy.hurricanePlanning(household: household, places: places, approvedSourceURLs: [sourceURL], at: now)
        guard case .available(let planning) = result else { Issue.record("Expected current approved planning evidence"); return }
        #expect(planning.zone == "Synthetic zone")
        #expect(planning.destinationPlaceID == "destination")
        #expect(planning.source.id == "source-local")
        #expect(MapPlanningPolicy.hurricanePlanning(household: household, places: places, approvedSourceURLs: [], at: now) == .needsReview)
        #expect(MapPlanningPolicy.hurricanePlanning(household: household, places: places, approvedSourceURLs: [sourceURL + "?different"], at: now) == .needsReview)
        #expect(MapPlanningPolicy.hurricanePlanning(household: household, places: places, approvedSourceURLs: [sourceURL], at: now.addingTimeInterval(3601)) == .needsReview)
        var moved = household; moved.privateLocation = PrivateLocation(addressLine: "Different fictional home")
        #expect(MapPlanningPolicy.hurricanePlanning(household: moved, places: places, approvedSourceURLs: [sourceURL], at: now) == .needsReview)
        var wrongRegion = household; wrongRegion.regionID = "another-jurisdiction"
        #expect(MapPlanningPolicy.hurricanePlanning(household: wrongRegion, places: places, approvedSourceURLs: [sourceURL], at: now) == .needsReview)
        var unbound = household; unbound.siteHazards?.locationBinding = nil
        #expect(MapPlanningPolicy.hurricanePlanning(household: unbound, places: places, approvedSourceURLs: [sourceURL], at: now) == .needsReview)
        var duplicate = household; duplicate.siteHazards?.sources.append(household.siteHazards!.sources[0])
        #expect(MapPlanningPolicy.hurricanePlanning(household: duplicate, places: places, approvedSourceURLs: [sourceURL], at: now) == .needsReview)
        for authority in [SiteHazardSource.Authority.household, .synthetic] {
            var unsupported = household; unsupported.siteHazards?.sources[0].authority = authority
            #expect(MapPlanningPolicy.hurricanePlanning(household: unsupported, places: places, approvedSourceURLs: [sourceURL], at: now) == .needsReview)
        }
        var unreviewed = household; unreviewed.siteHazards?.sources[0].reviewed = false
        #expect(MapPlanningPolicy.hurricanePlanning(household: unreviewed, places: places, approvedSourceURLs: [sourceURL], at: now) == .needsReview)
    }

    @Test func destinationMustBeSavedForThisHomeAndNeverSuppliesOfficialRouteGeometry() {
        let household = withHurricanePlan()
        let otherHome = SavedPlace(id: "destination", homeID: "different-home", purpose: .fallbackDestination, label: "Unrelated destination")
        let result = MapPlanningPolicy.hurricanePlanning(household: household, places: [otherHome], approvedSourceURLs: [sourceURL], at: now)
        guard case .available(let planning) = result else { Issue.record("Expected planning evidence without a matched destination"); return }
        #expect(planning.destinationPlaceID == nil)
        #expect(MapPlanningPolicy.hurricanePlanning(household: SampleHouseholds.oak, places: [], approvedSourceURLs: [sourceURL], at: now) == .notRecorded)
    }

    @Test func unrelatedDemoExpiredAndRevokedCatalogsCannotAuthorizeLocalGuidance() {
        let region = RegionInfo(id: "48143", name: "Synthetic region", kind: "county", nwsZoneIDs: [], nwsCountyIDs: [], coverage: .verifiedPartial, inTX25: "unknown")
        let source = SourceRef(id: "source-local", publisher: "Synthetic authority fixture", title: "Synthetic planning source",
            url: sourceURL, checkedAt: "2026-10-20", reviewState: .reviewed)
        let pack = RegionPack(schemaVersion: 1, contentVersion: "synthetic", packID: "synthetic-pack", generatedAt: "2026-10-20T00:00:00Z",
            classification: .curated, regions: [region], resources: [], sources: [source])
        #expect(MapPlanningPolicy.reviewedPlanningSourceURLs(packs: [pack], jurisdictionID: region.id, at: now) == [sourceURL])
        #expect(MapPlanningPolicy.reviewedPlanningSourceURLs(packs: [pack], jurisdictionID: "48133", at: now).isEmpty)
        for classification in [DataClassification.fixture, .demo] {
            var untrusted = pack; untrusted.classification = classification
            #expect(MapPlanningPolicy.reviewedPlanningSourceURLs(packs: [untrusted], jurisdictionID: region.id, at: now).isEmpty)
        }
        var expired = pack; expired.expiresAt = "2026-10-21T00:00:00Z"
        #expect(MapPlanningPolicy.reviewedPlanningSourceURLs(packs: [expired], jurisdictionID: region.id, at: now).isEmpty)
        var revoked = pack; revoked.generatedAt = "2026-10-22T00:00:00Z"; revoked.sources[0].reviewState = .needsReview
        #expect(MapPlanningPolicy.reviewedPlanningSourceURLs(packs: [revoked, pack], jurisdictionID: region.id, at: now).isEmpty)
        revoked.expiresAt = "2026-10-23T00:00:00Z"
        #expect(MapPlanningPolicy.reviewedPlanningSourceURLs(packs: [revoked, pack], jurisdictionID: region.id, at: now).isEmpty)
    }

    private func withHurricanePlan() -> HouseholdProfile {
        var household = SampleHouseholds.oak
        household.privateLocation = PrivateLocation(addressLine: "Synthetic home", latitude: 32, longitude: -98)
        let source = SiteHazardSource(id: "source-local", authority: .official, publisher: "Synthetic authority fixture",
            url: sourceURL, jurisdictionID: household.regionID, retrievedAt: now.addingTimeInterval(-60), validUntil: now.addingTimeInterval(3600), reviewed: true)
        let profile = SiteHazardProfile(jurisdictionID: household.regionID, sources: [source],
            hurricane: HurricaneEvacuationPlan(zone: "Synthetic zone", routeIDs: ["synthetic-route"], sourceID: source.id,
                destinationPlaceID: "destination", instructions: "Synthetic input instructions"))
        SiteHazardEditing.stage(profile, in: &household)
        return household
    }
}
