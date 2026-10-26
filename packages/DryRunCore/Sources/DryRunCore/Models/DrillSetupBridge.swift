import Foundation

/// Native side of the gateway's `drillSetup` role: Beacon picks an instructive setup for a practice drill from
/// candidates Core offers (fire origin rooms, each person's starting room). Only offered candidates survive, at most
/// one origin and one start per person; the family still sees and can change every choice before starting.
public enum DrillSetupBridge {
    public struct Output: Codable, Sendable, Equatable {
        public var choiceTaskIDs: [String]
        public var reason: String
    }

    public struct Accepted: Sendable, Equatable {
        public var originSpaceID: String?
        public var startingSpaceIDs: [String: String]
        public var reason: String
    }

    /// Rooms a person plausibly starts a drill in: bedrooms and living areas (the rest are rarely where people are).
    static let startKinds: Set<SpaceKind> = [.bedroom, .livingRoom, .office, .dining]

    public static func request(requestID: String, scenarioID: String, readableRoom: (String) -> String, household: HouseholdProfile,
                               home: HomeModel, inventory: InventoryLedger, rubric: RubricDefinition,
                               at date: Date = Date(), state: IntegratedAIState? = nil, places: [SavedPlace] = [],
                               scopeSessionID: String? = nil, locale: String? = nil, currentScorecard: PreparednessScorecard? = nil) throws -> PreparationFeatureBridge.Request {
        var request = try PreparationFeatureBridge.request(requestID: requestID, household: household, home: home,
                                                           inventory: inventory, rubric: rubric, at: date, state: state,
                                                           places: places, scopeSessionID: scopeSessionID, locale: locale, currentScorecard: currentScorecard)
        let criterion = rubric.criteria.first?.id ?? "escape"
        func task(_ id: String, action: String, subject: String, why: String) -> PreparationTaskProposal {
            PreparationTaskProposal(id: id, actionID: action, criterionID: criterion, subjectID: subject, why: why,
                                    evidenceIDs: ["household-needs"], completionPredicates: [], editor: "home", dependencyIDs: [], priority: 0)
        }
        var tasks: [PreparationTaskProposal] = []
        if scenarioID == "home-fire" {
            tasks += home.spaces.map { task("origin:\($0.id)", action: "setup.fireOrigin", subject: $0.id, why: "The fire starts in \(readableRoom($0.id)).") }
        }
        let starts = home.spaces.filter { startKinds.contains($0.kind) }
        // People are described by age band and recorded needs only: names never leave the phone.
        for (index, person) in household.people.enumerated() {
            let needs = person.needs.map(\.rawValue).joined(separator: ", ")
            let who = "Person \(index + 1) (\(person.ageBand.rawValue)\(needs.isEmpty ? "" : "; " + needs))"
            tasks += starts.map { task("start:\(person.id):\($0.id)", action: "setup.startingRoom", subject: person.id,
                                       why: "\(who) starts in \(readableRoom($0.id)).") }
        }
        request.role = "drillSetup"
        request.context.debrief = .init(scenarioID: scenarioID)
        request.context.tasks = Array(tasks.prefix(30))
        return request
    }

    public static func accept(_ output: Output, request: PreparationFeatureBridge.Request, home: HomeModel, household: HouseholdProfile) -> Accepted? {
        let reason = output.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty, reason.count <= 600 else { return nil }
        let offered = Set(request.context.tasks.map(\.id))
        var origin: String?, starts: [String: String] = [:]
        for id in output.choiceTaskIDs where offered.contains(id) {
            let parts = id.split(separator: ":").map(String.init)
            if parts.count == 2, parts[0] == "origin", origin == nil, home.space(parts[1]) != nil { origin = parts[1] }
            if parts.count == 3, parts[0] == "start", starts[parts[1]] == nil,
               household.people.contains(where: { $0.id == parts[1] }), home.space(parts[2]) != nil { starts[parts[1]] = parts[2] }
        }
        guard origin != nil || !starts.isEmpty else { return nil }
        return Accepted(originSpaceID: origin, startingSpaceIDs: starts, reason: reason)
    }
}
