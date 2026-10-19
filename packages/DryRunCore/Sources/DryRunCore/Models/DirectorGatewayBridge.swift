import Foundation

/// Native side of the director gateway contract (services/ai-orchestrator/src/contracts.ts). Builds the strict,
/// minimized operation context from committed host state and executes requested read-only tools through Core,
/// returning only the fields the TypeScript executor returns (scripts/director-tools.ts). Nothing here sends data;
/// the app's transport does, and only for synthetic (fictional) households.
public enum DirectorGatewayBridge {
    public static let contractVersion = "dryrun.ai/1"

    public struct MinimizedSnapshot: Codable, Sendable, Equatable {
        public var firedEventIDs: [String]?
        public var simMinute: Int
        public var resources: [String: ResourceQuantity]
        public var services: [String: ServiceState]
        public var unmetRequirements: [String]
        public var unknowns: [String]
        public init(_ snapshot: SimulationSnapshot) {
            firedEventIDs = snapshot.firedEventIDs; simMinute = snapshot.simMinute; resources = snapshot.resources
            services = snapshot.services; unmetRequirements = snapshot.unmetRequirements; unknowns = snapshot.unknowns
        }
    }

    public struct ProfileContext: Codable, Sendable {
        public var id: String; public var rule: String; public var minute: Int
        public var hazard: HazardKind?; public var spatial: Bool?; public var canStart: Bool?; public var roomRequired: Bool?
    }

    public struct DirectorContext: Codable, Sendable {
        public var binding: AgentContextBinding
        public var snapshot: MinimizedSnapshot
        public var directorPolicy: DirectorPolicy?
        public var directorState: DirectorRuntimeState?
        public var pending: [SessionCommand]?
        public var closedPortalIDs: [String]?
        public var household: HouseholdContextSnapshot?
        public var homeScene: HomeSceneContext?
        public var profiles: [ProfileContext]
        public var learningObjectives: [String]
        public var lastAction: CommittedUserActionContext?
        public var recentActions: [CommittedUserActionContext]?
    }

    public struct OperationRequest: Codable, Sendable {
        public var contractVersion = DirectorGatewayBridge.contractVersion
        public var requestID: String
        public var role = "director"
        public var synthetic = true
        public var context: DirectorContext
    }

    /// Authored per-hazard objectives: what the exercise practices, never model-written.
    public static func learningObjectives(_ hazard: HazardKind) -> [String] {
        switch hazard {
        case .homeFire: ["Practice getting everyone out by recorded routes and reaching the meeting place; never use elevators"]
        case .tornado: ["Practice reaching the reviewed shelter location early, including anyone who needs help"]
        case .flashFlood: ["Practice acting on the warning without driving through water, using recorded plans only"]
        case .freezePowerLoss: ["Practice keeping warm and essential equipment powered with recorded backups only"]
        case .heatGridStrain: ["Practice staying cool and protecting essential equipment during a heat-related outage"]
        case .waterOutage: ["Compare stored-water use and protect continuity without inventing supplies"]
        }
    }

    /// The context for one director turn, built only from the committed session and its frozen source snapshot.
    /// Throws if the session is awaiting the family or finished: a director call is never made then.
    public static func operationRequest(requestID: String, session: SimulationSession, receipt: SessionReceipt,
                                        library: ScenarioLibrary, at date: Date = Date()) throws -> OperationRequest {
        guard !receipt.finished, receipt.directorState?.awaitingUserAction != true,
              let scenario = library.scenario(session.initial.scenarioID) else { throw SessionError.invalidCommand }
        let household = session.initial.household, home = session.initial.home
        let binding = AgentContextBinding(receipt: receipt, householdRevision: household.revision, homeRevision: home?.revision ?? 0)
        let profiles = scenario.events
            .filter { Applicability.holds($0.when, household: household, home: home, variants: session.initial.variants) }
            .map { event -> ProfileContext in
                let d = DirectorProfileDescriptor(event, in: scenario)
                return ProfileContext(id: d.id, rule: d.rule, minute: d.minute, hazard: d.hazard, spatial: d.spatial, canStart: d.canStart, roomRequired: d.roomRequired)
            }
        let actions = try session.userActionContexts(library: library)
        let context = DirectorContext(
            binding: binding, snapshot: MinimizedSnapshot(receipt.snapshot), directorPolicy: session.directorPolicy,
            directorState: receipt.directorState, pending: receipt.pending.isEmpty ? nil : receipt.pending,
            closedPortalIDs: receipt.closedPortalIDs, household: HouseholdContextSnapshot(household, at: date),
            homeScene: home.map { HomeSceneContext($0, household: household) }, profiles: Array(profiles.prefix(40)),
            learningObjectives: learningObjectives(scenario.hazard), lastAction: actions.last,
            recentActions: actions.isEmpty ? nil : actions)
        return OperationRequest(requestID: requestID, context: context)
    }

    // MARK: Client tools

    public struct ToolCall: Codable, Sendable {
        public var id: String
        public var name: String
        public var arguments: ToolArguments
        public init(id: String, name: String, arguments: ToolArguments) { self.id = id; self.name = name; self.arguments = arguments }
    }
    public struct ToolArguments: Codable, Sendable {
        public var command: SessionCommand?
        public var commands: [SessionCommand]?
        public var profileIDs: [String]?
        public var retestPlan: StressRetestPlan?
        public init(command: SessionCommand? = nil, commands: [SessionCommand]? = nil, profileIDs: [String]? = nil, retestPlan: StressRetestPlan? = nil) {
            self.command = command; self.commands = commands; self.profileIDs = profileIDs; self.retestPlan = retestPlan
        }
    }

    public struct PathContext: Codable, Sendable {
        public var spaceSequence: [String]; public var portalSequence: [String]
        public var connectorSequence: [String]; public var verificationNeeded: [String]
        init(_ p: RoutePath) { spaceSequence = p.spaceSequence; portalSequence = p.portalSequence; connectorSequence = p.connectorSequence; verificationNeeded = p.verificationNeeded }
    }
    public struct RouteContext: Codable, Sendable {
        public var personID: String?; public var primary: PathContext?; public var alternative: PathContext?
        public var alternativeStatus: String; public var sharedChokepoints: [String]; public var noRouteReason: String?
        init(_ r: RouteResult) {
            personID = r.request.personID; primary = r.primary.map(PathContext.init); alternative = r.alternative.map(PathContext.init)
            alternativeStatus = r.alternativeStatus.rawValue; sharedChokepoints = r.sharedChokepoints; noRouteReason = r.noRouteReason?.rawValue
        }
    }
    public struct AssistanceContext: Codable, Sendable {
        public var personID: String; public var helperID: String?; public var reachStatus: String
        public var sharedWithPersonIDs: [String]; public var simultaneousCapacity: String
    }
    public struct SpatialContext: Codable, Sendable {
        public var hazard: HazardKind; public var stageID: String; public var originSpaceID: String?
        public var affectedSpaceIDs: [String]; public var affectedPortalIDs: [String]
        public var destinationSpaceID: String?; public var assumptionKey: String?
    }
    public struct PreviewContext: Codable, Sendable {
        public var routes: [RouteContext]; public var assistance: [AssistanceContext]?
        public var directorState: DirectorRuntimeState?; public var spatial: SpatialContext?
    }
    public struct Observation: Codable, Sendable {
        public var kind: String
        public var scene: HomeSceneContext?
        public var routes: [RouteContext]?
        public var dependencies: [DependencyInspection]?
        public var scope: String?; public var failed: Bool?; public var criterionID: String?; public var dependencyIDs: [String]?
        public var sourceConcernDigest: String?; public var baseline: MinimizedSnapshot?; public var controlledRetest: MinimizedSnapshot?
        public var comparison: StressRetestComparison?
        public var status: String?; public var reason: String?
    }
    public struct ToolResult: Codable, Sendable {
        public var binding: AgentContextBinding
        public var snapshot: MinimizedSnapshot
        public var contextDigest: String
        public var observation: Observation?
        public var preview: PreviewContext?
    }

    public static let toolNames: Set<String> = ["evaluateCandidateAction", "inspectScene", "queryRoutes", "evaluateResources", "inspectDependencies", "runCounterfactual"]

    /// Executes one whitelisted, read-only tool against the bound revision. Never commits; never returns raw receipts.
    public static func execute(_ call: ToolCall, session: SimulationSession, binding: AgentContextBinding,
                               library: ScenarioLibrary) throws -> ToolResult {
        guard toolNames.contains(call.name), let kind = SessionToolKind(rawValue: call.name) else { throw SessionError.invalidCommand }
        let current = try session.query(library: library)
        try binding.validate(receipt: current, household: session.initial.household, home: session.initial.home)
        let a = call.arguments
        if kind == .evaluateCandidateAction {
            guard (a.command == nil) != (a.commands == nil), a.profileIDs == nil, a.retestPlan == nil else { throw SessionError.invalidCommand }
        } else if kind == .runCounterfactual {
            guard a.command == nil, a.commands == nil, let ids = a.profileIDs, (1...8).contains(ids.count) else { throw SessionError.invalidCommand }
        } else {
            guard a.command == nil, a.commands == nil, a.profileIDs == nil, a.retestPlan == nil else { throw SessionError.invalidCommand }
        }
        let request = SessionToolRequest(kind: kind, baseRevision: binding.revision, command: a.command, commands: a.commands,
                                         profileIDs: a.profileIDs, retestPlan: a.retestPlan)
        let response: SessionToolResponse
        do { response = try session.executeTool(request, library: library) }
        catch SessionError.invalidCommand where kind == .runCounterfactual {
            // A rejected hypothetical challenge is not a computed pass or failure.
            return ToolResult(binding: binding, snapshot: MinimizedSnapshot(current.snapshot), contextDigest: current.contextDigest,
                              observation: Observation(kind: call.name, status: "unavailable", reason: "host_rejected_counterfactual"))
        }
        let receipt = response.receipt
        let routes = receipt.routes.map(RouteContext.init)
        var result = ToolResult(binding: binding, snapshot: MinimizedSnapshot(receipt.snapshot), contextDigest: receipt.contextDigest)
        switch kind {
        case .evaluateCandidateAction:
            let s = receipt.snapshot.spatialState
            result.preview = PreviewContext(
                routes: routes,
                assistance: receipt.assistance?.map { AssistanceContext(personID: $0.personID, helperID: $0.helperID, reachStatus: $0.reachStatus.rawValue,
                                                                        sharedWithPersonIDs: $0.sharedWithPersonIDs, simultaneousCapacity: $0.simultaneousCapacity) },
                directorState: receipt.directorState,
                spatial: s.map { SpatialContext(hazard: $0.hazard, stageID: $0.stageID, originSpaceID: $0.originSpaceID, affectedSpaceIDs: $0.affectedSpaceIDs,
                                                affectedPortalIDs: $0.affectedPortalIDs, destinationSpaceID: $0.destinationSpaceID, assumptionKey: $0.assumptionKey) })
        case .inspectScene: result.observation = Observation(kind: call.name, scene: response.scene)
        case .evaluateResources: result.observation = Observation(kind: call.name)
        case .queryRoutes: result.observation = Observation(kind: call.name, routes: routes)
        case .inspectDependencies: result.observation = Observation(kind: call.name, dependencies: response.dependencies ?? [])
        case .runCounterfactual:
            guard let c = response.counterfactual else { throw SessionError.invalidCommand }
            result.observation = Observation(kind: call.name, scope: "initial_household_with_selected_profiles", failed: c.failed, criterionID: c.criterionID,
                                             dependencyIDs: c.dependencyIDs, sourceConcernDigest: c.sourceConcernDigest,
                                             baseline: MinimizedSnapshot(c.baseline.snapshot), controlledRetest: c.controlledRetest.map { MinimizedSnapshot($0.snapshot) },
                                             comparison: c.comparison)
        }
        return result
    }
}
