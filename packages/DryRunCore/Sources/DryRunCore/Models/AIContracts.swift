import Foundation
public struct AgentContextBinding: Codable, Sendable, Equatable {
    public var sessionID:String; public var revision:Int; public var eventSequence:Int; public var contextDigest:String
    public var householdRevision:Int; public var homeRevision:Int
    public init(receipt:SessionReceipt,householdRevision:Int,homeRevision:Int){self.sessionID=receipt.sessionID;self.revision=receipt.revision;self.eventSequence=receipt.eventSequence;self.contextDigest=receipt.contextDigest;self.householdRevision=householdRevision;self.homeRevision=homeRevision}
    public func validate(receipt:SessionReceipt,household:HouseholdProfile,home:HomeModel?) throws {
        guard sessionID==receipt.sessionID,revision==receipt.revision,eventSequence==receipt.eventSequence,contextDigest==receipt.contextDigest,
              householdRevision==household.revision,homeRevision==(home?.revision ?? 0) else {throw SessionError.stale}
    }
}
public struct DirectorProposal: Codable, Sendable {
    public var id:String;public var actor:String;public var baseRevision:Int;public var commands:[SessionCommand]
    public var purpose:String;public var evidenceIDs:[String]
    public func commit(to session:inout SimulationSession,binding:AgentContextBinding,library:ScenarioLibrary,persist:(SimulationSession)throws->Void) throws -> SessionReceipt {
        let receipt=try session.query(library:library)
        try binding.validate(receipt:receipt,household:session.initial.household,home:session.initial.home)
        guard actor=="director",baseRevision==binding.revision else {throw SessionError.invalidCommand}
        return try session.commit(SessionCommit(id:id,actor:actor,baseRevision:baseRevision,commands:commands),library:library,persist:persist)
    }
}
public struct PreparationTaskProposal: Codable, Sendable {
    public var id:String;public var actionID:String;public var criterionID:String;public var subjectID:String;public var why:String
    public var evidenceIDs:[String];public var completionPredicates:[String];public var editor:String;public var dependencyIDs:[String];public var priority:Int
}
public struct ResourceSearchPlan: Codable, Sendable {
    public var id:String;public var taskID:String;public var dependencyIDs:[String];public var hazardIDs:[String];public var category:String
    public var purpose:String;public var mandatoryCapabilities:[String];public var unknowns:[String];public var travelMode:String
    public var maximumDistanceKm:Double;public var expansionLimit:Int;public var requiredEvidence:[String];public var cloudReturnPolicy:String
}
public struct InventoryObservationProposal: Codable, Sendable {
    public var id:String;public var physicalID:String;public var category:String;public var quantity:Double?;public var unit:InventoryUnit
    public var evidenceIDs:[String];public var unknowns:[String]
}
/// iOS implements native authorization. The gateway deliberately has no production fixture-token path.
public protocol AIInstallationAuthorizing: Sendable {
    func authorize(challenge:Data,installationKeyID:String,scope:String) async throws -> String
}
