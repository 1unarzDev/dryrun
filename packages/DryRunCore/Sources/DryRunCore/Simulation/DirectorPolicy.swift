import Foundation

public struct DirectorStageTransition:Codable,Sendable,Hashable {
    public var from:String
    public var to:String
    public init(from:String,to:String){self.from=from;self.to=to}
}
/// Host-authored bounds, never a model proposal. Current scene engine supports one spatial incident.
public struct DirectorPolicy:Codable,Sendable,Equatable {
    public var version:String
    public var permittedHazardFamilies:[HazardKind]
    public var maximumActiveIncidents:Int
    public var schedulingHorizonMinutes:Int
    public var eventBudget:Int
    public var maximumPendingEvents:Int
    public var allowedStageTransitions:[DirectorStageTransition]
    public init(permittedHazardFamilies:[HazardKind],maximumActiveIncidents:Int=1,schedulingHorizonMinutes:Int,eventBudget:Int=32,maximumPendingEvents:Int=8,allowedStageTransitions:[DirectorStageTransition]) {
        version="dryrun.director-policy/1";self.permittedHazardFamilies=permittedHazardFamilies;self.maximumActiveIncidents=maximumActiveIncidents
        self.schedulingHorizonMinutes=schedulingHorizonMinutes;self.eventBudget=eventBudget;self.maximumPendingEvents=maximumPendingEvents;self.allowedStageTransitions=allowedStageTransitions
    }
    /// All forward compositions of reviewed spatial stages are permitted; no prescribed timeline.
    public static func reviewed(_ scenario:ScenarioDefinition)->DirectorPolicy {
        let stages=spatialProfiles(scenario)
        var edges=stages.filter{canStart($0,in:scenario)}.map{DirectorStageTransition(from:"notStarted",to:$0.id)}
        for (index,stage) in stages.enumerated() {edges += stages.dropFirst(index+1).map{.init(from:stage.id,to:$0.id)}}
        return DirectorPolicy(permittedHazardFamilies:[scenario.hazard],schedulingHorizonMinutes:min(4320,scenario.durationMinutes),allowedStageTransitions:edges)
    }
    public func validate(in scenario:ScenarioDefinition)throws {
        let stages=Self.spatialProfiles(scenario).map(\.id)
        guard scenario.durationMinutes>=0,version=="dryrun.director-policy/1",!permittedHazardFamilies.isEmpty,
              Set(permittedHazardFamilies).count==permittedHazardFamilies.count,
              (0...1).contains(maximumActiveIncidents), // no unsupported multilayer incident composition
              (0...min(4320,scenario.durationMinutes)).contains(schedulingHorizonMinutes),
              (0...32).contains(eventBudget),(1...8).contains(maximumPendingEvents),
              allowedStageTransitions.count<=820,Set(allowedStageTransitions).count==allowedStageTransitions.count else {throw SessionError.invalidCommand}
        for edge in allowedStageTransitions {
            guard let to=stages.firstIndex(of:edge.to),(edge.from=="notStarted" && Self.canStart(Self.spatialProfiles(scenario)[to],in:scenario)) || stages.firstIndex(of:edge.from).map({$0<to})==true else {throw SessionError.invalidCommand}
        }
    }
    static func canStart(_ event:AuthoredEvent,in scenario:ScenarioDefinition)->Bool {
        [RuleID.fireIgnition,RuleID.tornadoWarning,RuleID.floodWarning,RuleID.householdLeak].contains(event.rule)
        || (event.rule==RuleID.fireBlockPrimary && event.params["originKind"] != nil)
    }
    static func spatialProfiles(_ scenario:ScenarioDefinition)->[AuthoredEvent] {
        scenario.events.filter{isSpatial($0,in:scenario)}.sorted{($0.minute,$0.priority,$0.id)<($1.minute,$1.priority,$1.id)}
    }
    static func isSpatial(_ event:AuthoredEvent,in scenario:ScenarioDefinition)->Bool {
        [RuleID.fireIgnition,RuleID.fireBlockPrimary,RuleID.tornadoWarning,RuleID.floodWarning,RuleID.householdLeak].contains(event.rule)
        || (scenario.hazard == .flashFlood && event.rule == RuleID.setExternal && event.params["service"]==Svc.roads && event.params["state"]=="unavailable")
    }
    /// Validate the *time-ordered* pending composition, not the order in which it was submitted.
    func validateQueue(_ commands:[SessionCommand],after currentStage:String?,scenario:ScenarioDefinition)throws {
        var stage=currentStage
        for command in Self.ordered(commands,scenario:scenario) {
            guard let profile=scenario.events.first(where:{$0.id==command.target}) else {throw SessionError.invalidCommand}
            let spatial=Self.isSpatial(profile,in:scenario)
            if command.kind=="startIncident" || command.kind=="advanceIncident" {
                guard spatial,command.hazard==scenario.hazard else {throw SessionError.invalidCommand}
                if command.kind=="startIncident" {guard stage==nil else {throw SessionError.budget}}
                else {guard stage != nil,command.value==nil else {throw SessionError.invalidCommand}}
            }
            if spatial {
                guard maximumActiveIncidents>=1,allowedStageTransitions.contains(.init(from:stage ?? "notStarted",to:profile.id)) else {throw SessionError.invalidCommand}
                stage=profile.id
            }
        }
    }
    static func ordered(_ commands:[SessionCommand],scenario:ScenarioDefinition)->[SessionCommand] {
        let priorities=Dictionary(uniqueKeysWithValues:scenario.events.map{($0.id,$0.priority)})
        return commands.sorted{($0.minute ?? 0,priorities[$0.target ?? ""] ?? 0,$0.target ?? "")<($1.minute ?? 0,priorities[$1.target ?? ""] ?? 0,$1.target ?? "")}
    }
}
public struct DirectorRuntimeState:Codable,Sendable,Equatable {
    public var activeIncidentCount:Int
    public var scheduledEventCount:Int=0
    public var awaitingUserAction:Bool=false
    public var stageID:String?
    public var originSpaceID:String?
    public var lastWait:SessionWaitOutcome?
}

public struct DirectorProfileDescriptor:Codable,Sendable {
    public var id:String
    public var rule:String
    public var minute:Int
    public var hazard:HazardKind
    public var spatial:Bool
    public var canStart:Bool
    public var roomRequired:Bool
    public init(_ event:AuthoredEvent,in scenario:ScenarioDefinition) {
        id=event.id;rule=event.rule;minute=event.minute;hazard=scenario.hazard
        spatial=DirectorPolicy.isSpatial(event,in:scenario);canStart=DirectorPolicy.canStart(event,in:scenario)
        roomRequired=spatial && (scenario.hazard == .homeFire || scenario.hazard == .flashFlood)
    }
}
