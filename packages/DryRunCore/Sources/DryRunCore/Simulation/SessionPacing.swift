import Foundation

/// Finite host predicates; model text is never evaluated as code or treated as a condition.
public enum SessionWaitPredicate:String,Codable,Sendable,Hashable,CaseIterable {
    case nextIncident,storedWaterUnavailable,primaryContactChannelUnavailable
    func holds(in run:RunState)->Bool {
        switch self {
        case .nextIncident:return false // satisfied only by applying a pending incident
        case .storedWaterUnavailable:return !run.tapWaterUsable && run.storedWater.map{$0<=0}==true
        case .primaryContactChannelUnavailable:return run.services[Svc.handset] == .unavailable || run.services[Svc.cellular] == .unavailable
        }
    }
}
public struct SessionWaitOutcome:Codable,Sendable,Equatable {
    public var predicate:SessionWaitPredicate
    public var startedMinute:Int
    public var maximumDurationMinutes:Int
    public var stoppedMinute:Int
    public var satisfied:Bool
    /// predicate, mandatoryBoundary, policyHorizon, or durationLimit; never a model-authored result.
    public var reason:String
}
