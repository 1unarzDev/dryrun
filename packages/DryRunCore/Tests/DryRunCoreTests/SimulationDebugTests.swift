import Foundation
import Testing
@testable import DryRunCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["DRYRUN_EXPLORE"] != nil))
func simulationDebugRoute() {
    let p = EgressPlanner()
    let r0 = p.plan(RouteRequest(startSpaceID: "sp-bed2"), in: SampleHomes.ranch)
    print("usual", r0.primary?.spaceSequence as Any, r0.primary?.exitPortalID as Any, r0.noRouteReason as Any, r0.exclusions)
    let r = p.plan(RouteRequest(startSpaceID: "sp-bed2", exclusions: ScenarioExclusions(blockedSpaceIDs: ["sp-living"], blockedPortalIDs: ["pt-front"])), in: SampleHomes.ranch)
    print("blocked", r.primary?.spaceSequence as Any, r.noRouteReason as Any, r.exclusions)
}
