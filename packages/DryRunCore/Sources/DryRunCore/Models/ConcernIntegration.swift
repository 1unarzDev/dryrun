import Foundation

public struct ConcernTaskLink:Codable,Sendable {
    public var id:String
    public var concernID:String
    public var actionID:String
    public var editor:String
    public var roomID:String?
    public var scenarioIDs:[String]
    public var evidenceIDs:[String]
    public var sourceIDs:[String]
    public var earnsScoreByItself:Bool
}
/// Only explicit household selection of canonical openings can affect an exercise route.
/// Image pixels never establish an opening ID or metric obstruction shape.
public struct ConcernExerciseSeed:Codable,Sendable {
    public var contractVersion:String
    public var reviewed:ReviewedConcern
    public var scenarioID:String
    public var selectedPortalIDs:[String]
    public var hypotheticalPermission:Bool
    public var sourceHomeFingerprint:String
    public func validate(home:HomeModel?,scenarioID:String)throws {
        guard contractVersion=="dryrun.concern-exercise/1",self.scenarioID==scenarioID,
              let home,sourceHomeFingerprint==HomeFingerprint.of(home),reviewed.proposal.homeRevision==home.revision,reviewed.sourceHomeFingerprint==sourceHomeFingerprint,
              reviewed.proposal.scenarioIDs.contains(scenarioID),reviewed.decision != .dismissed,
              reviewed.decision == .confirmed || hypotheticalPermission,
              Set(selectedPortalIDs).count==selectedPortalIDs.count,!selectedPortalIDs.isEmpty,selectedPortalIDs.count<=8,
              reviewed.proposal.category=="possibleObstruction",let room=reviewed.proposal.roomID,
              selectedPortalIDs.allSatisfy({id in home.portals.contains{$0.id==id && ($0.sideA == .space(room) || $0.sideB == .space(room))}})
        else {throw SessionError.invalidCommand}
    }
}

public extension IntegratedAIState {
    /// One compact review may confirm/dismiss/retain uncertainty. It never completes a preparation
    /// or edits scan geometry, operability, inventory or score predicates.
    mutating func reviewConcern(_ proposal:HomeConcernProposal,decision:ConcernDecision,manifest:RoomImageManifest,
        home:HomeModel,household:HouseholdProfile,rubric:RubricDefinition,library:ScenarioLibrary,at date:Date,
        persist:(IntegratedAIState)throws->Void={_ in})throws {
        try manifest.validate(home:home)
        let catalog=PreparationTaskCatalog.build(household:household,home:home,rubric:rubric,at:date,includeSatisfied:true)
        guard catalog.contains(where:{$0.actionID==proposal.actionID}),
              proposal.category=="supplyAccess" || proposal.actionID=="prep.clearExits",
              !proposal.id.isEmpty,proposal.id.count<=120,!proposal.visibleEvidence.isEmpty,proposal.visibleEvidence.count<=600,
              !proposal.scenarioIDs.isEmpty,Set(proposal.scenarioIDs).count==proposal.scenarioIDs.count,
              proposal.scenarioIDs.allSatisfy({library.scenario($0) != nil}),
              !manifest.redactedRegions.contains(where:{Self.boxOverlap($0,proposal.box)>0}) else {throw SessionError.invalidCommand}
        guard concerns.shouldOffer(proposal) || concerns.reviewed.contains(where:{$0.proposal.id==proposal.id}) else {throw SessionError.duplicate}
        var candidate=self
        try candidate.concerns.review(proposal,decision:decision,manifest:manifest,currentHomeRevision:home.revision,at:date,sourceHomeFingerprint:HomeFingerprint.of(home))
        try persist(candidate);self=candidate
    }
    func concernTasks(currentHome:HomeModel)->[ConcernTaskLink] {
        concerns.reviewed.filter{$0.decision == .confirmed && $0.proposal.homeRevision==currentHome.revision && $0.sourceHomeFingerprint==HomeFingerprint.of(currentHome)}.map {review in
            ConcernTaskLink(id:review.taskID!,concernID:review.proposal.id,actionID:review.proposal.actionID,editor:"home",
                roomID:review.proposal.roomID,scenarioIDs:review.proposal.scenarioIDs,
                evidenceIDs:[review.proposal.imageID,review.proposal.imageDigest,review.proposal.id],
                sourceIDs:review.proposal.category=="possibleObstruction" ? ["S19"]:["S20"],earnsScoreByItself:false)
        }.sorted{$0.id<$1.id}
    }
    /// Native presents these exact openings for user selection and the hypothetical-use label.
    /// Uncertain review alone cannot start or alter an exercise. A fresh session freezes this seed.
    func concernExerciseSeed(concernID:String,scenarioID:String,selectedPortalIDs:[String],allowHypothetical:Bool,
        home:HomeModel)throws->ConcernExerciseSeed {
        guard let reviewed=concerns.reviewed.first(where:{$0.proposal.id==concernID}) else {throw SessionError.invalidCommand}
        let seed=ConcernExerciseSeed(contractVersion:"dryrun.concern-exercise/1",reviewed:reviewed,scenarioID:scenarioID,
            selectedPortalIDs:selectedPortalIDs,hypotheticalPermission:allowHypothetical,sourceHomeFingerprint:HomeFingerprint.of(home))
        try seed.validate(home:home,scenarioID:scenarioID)
        return seed
    }
    private static func boxOverlap(_ a:[Double],_ b:[Double])->Double {
        guard a.count==4,b.count==4 else {return .infinity}
        return max(0,min(a[2],b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]))
    }
}

public extension RoomImageManifest {
    func validate(home:HomeModel)throws {
        guard !id.isEmpty,id.count<=120,homeRevision==home.revision,
              roomID==nil || home.spaces.contains(where:{$0.id==roomID}),
              digest.count==64,digest.allSatisfy({"0123456789abcdef".contains($0)}),
              (1...4096).contains(width),(1...4096).contains(height),
              ["up","right","down","left"].contains(orientation),["none","submittedFrameAligned"].contains(calibration),
              transforms.count<=12,transforms.allSatisfy({["crop","resize","rotate","redact"].contains($0.kind) && $0.values.count<=9 && $0.values.allSatisfy(\.isFinite)}),
              redactedRegions.count<=20,redactedRegions.allSatisfy({$0.count==4 && $0.allSatisfy({$0.isFinite && (0...1).contains($0)}) && $0[2]>$0[0] && $0[3]>$0[1]}) else {throw SessionError.invalidCommand}
    }
}
