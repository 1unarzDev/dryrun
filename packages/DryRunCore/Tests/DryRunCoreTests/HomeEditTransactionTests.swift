import Foundation
import Testing
@testable import DryRunCore

@Suite("Direct home editing save transaction") struct HomeEditTransactionTests {
    @Test func saveIsDurableBeforePublishAndAdvancesOnlyOnce()throws {
        let original=SampleHomes.ranch
        var current:HomeModel?=original,draft=original
        draft.spaces[0].label="Corrected room";draft.revision += 12
        var disk:Data?
        try HomeEditTransaction.commit(draft,baseRevision:original.revision,current:&current,homeID:original.id){candidate in
            disk=try DryRunJSON.encoder().encode(candidate)
        }
        #expect(current?.revision==original.revision+1)
        let reopened=try DryRunJSON.decoder().decode(HomeModel.self,from:#require(disk))
        #expect(reopened==current)
        #expect(reopened.spaces[0].label=="Corrected room")
        #expect(throws:HomeEditError.stale){try HomeEditTransaction.commit(draft,baseRevision:original.revision,current:&current,homeID:original.id,persist:{_ in Issue.record("Stale draft reached persistence")})}
    }
    @Test func rescanReplacesGeometryWithoutMistakingCaptureIDForHomeIdentity()throws {
        let original=SampleHomes.ranch
        var draft=original;draft.id="new-capture";draft.spaces[0].label="Rescanned room"
        let candidate=try #require(HomeEditTransaction.prepare(draft,baseRevision:original.revision,current:original,homeID:original.id))
        #expect(candidate.id==original.id);#expect(candidate.spaces[0].label=="Rescanned room")
        #expect(candidate.revision==original.revision+1)
    }
    @Test func failurePreservesDraftAndCurrentAndRetryCanSucceed()throws {
        let original=SampleHomes.ranch
        var current:HomeModel?=original,draft=original
        draft.spaces[0].label="Kept draft"
        #expect(throws:SessionError.persistence){try HomeEditTransaction.commit(draft,baseRevision:original.revision,current:&current,homeID:original.id,persist:{_ in throw SessionError.persistence})}
        #expect(current==original);#expect(draft.spaces[0].label=="Kept draft")
        try HomeEditTransaction.commit(draft,baseRevision:original.revision,current:&current,homeID:original.id,persist:{_ in})
        #expect(current?.spaces[0].label=="Kept draft")
    }
    @Test func doorWindowCorrectionKeepsGeometryAndDropsOldExitEligibility()throws {
        var home=SampleHomes.ranch
        let original=try #require(home.portal("pt-front"))
        try HomeEditTransaction.reclassify(original.id,as:.window,in:&home)
        let changed=try #require(home.portal(original.id))
        #expect(changed.id==original.id && changed.a==original.a && changed.b==original.b)
        #expect(changed.clearWidthMeters==original.clearWidthMeters)
        #expect(changed.sideA==original.sideA && changed.sideB==original.sideB)
        #expect(changed.operable.confirmedValue==nil && changed.emergencyEscapePersonIDs==nil)
        let route=EgressPlanner().plan(.init(startSpaceID:"sp-living"),in:home)
        #expect(route.primary?.exitPortalID != original.id)
        try HomeEditTransaction.reclassify(original.id,as:.door,in:&home)
        #expect(home.portal(original.id)?.operable.confirmedValue==nil)
    }
}
