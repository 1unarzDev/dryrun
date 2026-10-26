import Foundation

/// Current exercise assignment/approach, separate from the frozen real household.
/// Reachability is an approach computation, never completed assistance or capacity.
/// Route geometry and private annotations deliberately stay on the local host.
public struct ExerciseAssistanceContext:Codable,Sendable,Equatable {
    public let personID:String
    public let helperID:String?
    public let reachStatus:AssistanceReachStatus
    public let sharedWithPersonIDs:[String]
    public let simultaneousCapacity:String

    public init(_ actual:ExerciseAssistance) {
        personID=actual.personID;helperID=actual.helperID;reachStatus=actual.reachStatus
        sharedWithPersonIDs=actual.sharedWithPersonIDs;simultaneousCapacity=actual.simultaneousCapacity
    }
}
public extension SessionReceipt {
    /// Nil means not assessed; an assessed empty summary remains an empty array.
    var assistanceContext:[ExerciseAssistanceContext]? {assistance?.map(ExerciseAssistanceContext.init)}
}
