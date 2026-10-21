import Foundation

/// Canonical JSON values retain units, evidence states and relationships without lossy summaries.
public indirect enum AIContextValue: Codable, Sendable {
    case string(String), number(Double), bool(Bool), array([AIContextValue]), object([String: AIContextValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([AIContextValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: AIContextValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v); case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
}
public enum AIContextSection: String, Codable, Sendable, CaseIterable {
    case family, medical, home, location, constraints, inventory, tasks, learning, scores
}
public struct AIContextFact: Codable, Sendable {
    public var id: String
    public var section: AIContextSection
    public var subjectID: String
    public var sourcePath: String
    /// Recorded is not verified: nested canonical EvidenceValue retains its actual status.
    public var status: String
    public var value: AIContextValue?
}
public struct AuthorizedAIContext: Codable, Sendable {
    public struct Scope: Codable, Sendable, Equatable {
        public var householdID: String; public var origin: String; public var sessionID: String
    }
    public struct Revisions: Codable, Sendable, Equatable {
        public var household: Int; public var home: Int?; public var inventory: Int; public var stateFingerprint: String
    }
    public struct Binding: Codable, Sendable, Equatable {
        public var scope: Scope; public var revisions: Revisions; public var snapshotID: String; public var homeID: String?
    }
    public let version: String
    public let consent: Bool
    public let scope: Scope
    public let revisions: Revisions
    public let snapshotID: String
    public let records: [AIContextFact]
    public let homeID: String?
    public var binding: Binding { Binding(scope:scope,revisions:revisions,snapshotID:snapshotID,homeID:homeID) }

    /// Explicit consent is required by the caller's existing cloud-processing setting.
    /// Never use for a public search brief. Existing minimal snapshot stays unchanged.
    /// Any accepted AI wording in canonical records remains protected execution context.
    public init(household h: HouseholdProfile, home: HomeModel?, state: IntegratedAIState,
                places: [SavedPlace] = [], tasks: [PreparationTaskProposal] = [], sessionID: String,
                cloudPlanningConsent: Bool, currentScorecard: PreparednessScorecard? = nil) throws {
        guard cloudPlanningConsent, !sessionID.isEmpty, sessionID.count <= 120, !h.id.isEmpty,
              home == nil || home?.id == h.stableHomeID,
              places.allSatisfy({ $0.homeID == h.stableHomeID }) else { throw SessionError.invalidCommand }
        version = "dryrun.private-context/1"; consent = true
        homeID = home?.id
        scope = Scope(householdID: h.id, origin: h.isFictional ? "example" : "real", sessionID: sessionID)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        func json<T: Encodable>(_ value: T) throws -> AIContextValue { try JSONDecoder().decode(AIContextValue.self, from: encoder.encode(value)) }
        var facts: [AIContextFact] = []
        func append(_ section: AIContextSection, _ key: String, _ subject: String, _ value: AIContextValue?) {
            facts.append(AIContextFact(id:"context.\(section.rawValue).\(key)",section:section,subjectID:subject,
                sourcePath:key,status:value == nil ? "not_recorded":"recorded",value:value))
        }
        func collection(_ section: AIContextSection, _ key: String, _ subject: String, _ values: [AIContextValue]) -> AIContextValue {
            for (index,value) in values.enumerated() {
                let entityID: String
                if case .object(let object) = value, case .string(let id) = object["id"] { entityID=id }
                else { entityID=String(index) }
                append(section,"\(key).item.\(index).\(entityID)",entityID,value)
            }
            return .object(["recordCollection":.string(key+".item."),"count":.number(Double(values.count)),"ordering":.string("source array order; numeric index in sourcePath")])
        }
        func add<T: Encodable>(_ section: AIContextSection, _ key: String, _ subject: String, _ value: T?) throws {
            guard var encoded = try value.map(json) else { append(section,key,subject,nil);return }
            if case .array(let values) = encoded {
                encoded=collection(section,key,subject,values)
            } else if (key == "geometry" || key == "ledger"), case .object(var object) = encoded {
                for field in object.keys.sorted() {
                    if case .array(let values) = object[field] { object[field]=collection(section,key+"."+field,subject,values) }
                }
                encoded = .object(object)
            }
            append(section,key,subject,encoded)
        }
        try add(.family, "householdPreferences", h.id, ["displayName":h.displayName,"preferredLocale":h.preferredLocale])
        for person in h.people {
            try add(.family, "person.\(person.id)", person.id, person)
            try add(.medical, "emergencyInformation.\(person.id)", person.id, person.emergencyInformation)
        }
        try add(.family, "pets", h.id, h.pets)
        try add(.family, "communications", h.id, h.communications)
        try add(.family, "contacts", h.id, h.contacts)
        for equipment in h.equipment { try add(.medical, "equipment.\(equipment.id)", equipment.personID ?? equipment.id, equipment) }
        try add(.medical, "backupPower", h.id, h.backupPower)
        try add(.home, "housing", h.id, h.housing)
        try add(.home, "geometry", h.stableHomeID, home)
        try add(.location, "privateLocation", h.id, h.privateLocation)
        try add(.location, "savedPlaces", h.stableHomeID, places)
        try add(.location, "siteHazards", h.id, h.siteHazards)
        try add(.constraints, "transport", h.id, h.transport)
        try add(.constraints, "limitedBudget", h.id, h.supplies.limitedBudget)
        try add(.constraints, "limitedStorageSpace", h.id, h.supplies.limitedStorageSpace)
        // There is no canonical numeric budget; unknown never becomes an invented amount.
        facts.append(AIContextFact(id:"context.constraints.budgetAmount", section:.constraints, subjectID:h.id,
                                   sourcePath:"budgetAmount", status:"unsupported", value:nil))
        try add(.inventory, "supplies", h.id, h.supplies)
        try add(.inventory, "ledger", h.id, state.inventory)
        try add(.tasks, "currentTasks", h.id, tasks)
        try add(.tasks, "completedPreparations", h.id, h.completedPreparations)
        try add(.tasks, "preparedness", h.id, h.preparedness)
        try add(.learning, "sessions", h.id, state.sessions)
        try add(.learning, "practiceAttempts", h.id, state.practiceAttempts)
        try add(.scores, "scorecards", h.id, state.scorecards)
        try add(.scores, "currentHostScorecard", h.id, currentScorecard)
        records = facts
        func fingerprint(_ bytes: Data) -> String {
            // Content identity only, never authentication or a privacy boundary.
            var hash: UInt64 = 14695981039346656037
            for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
            return String(hash, radix:16)
        }
        revisions = Revisions(household:h.revision, home:home?.revision, inventory:state.inventory.revision,
                              stateFingerprint:fingerprint(try encoder.encode(state)))
        snapshotID = "ctx-" + fingerprint(try encoder.encode(scope) + encoder.encode(revisions) + encoder.encode(facts))
    }
}
