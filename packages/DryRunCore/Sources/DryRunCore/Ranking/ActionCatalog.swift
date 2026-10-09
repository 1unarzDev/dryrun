import Foundation

/// One preparation in the catalog. `content/actions/actions.json` is generated from `ActionCatalog.builtIn`
/// and checked by a test, so the descriptive catalog and the Swift triggers never drift apart.
public struct ActionDefinition: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var effort: EffortBand
    public var sourceIDs: [String]
    /// Scenarios where this preparation matters (used for multi-scenario relevance and tie-breaking).
    public var scenarioIDs: [String]
    /// Whether "Try this change" can model it; what the simulation copy changes.
    public var simulates: String?
    public var renterFriendly: Bool
    public var feasibilityNotes: [String]
}

public struct ActionCatalog: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var actions: [ActionDefinition]

    public func action(_ id: String) -> ActionDefinition? { actions.first { $0.id == id } }

    static let all6 = ["freeze-power-loss", "heat-grid-strain", "tornado", "flash-flood", "home-fire", "water-outage"]
    static let power = ["freeze-power-loss", "heat-grid-strain", "tornado", "flash-flood"]
    static let relocation = ["freeze-power-loss", "heat-grid-strain", "flash-flood", "home-fire", "tornado"]

    public static let builtIn = ActionCatalog(schemaVersion: 1, actions: [
        ActionDefinition(id: "act.backup.confirm-medical-backup", effort: .moderate, sourceIDs: ["S25"], scenarioIDs: power,
                         simulates: "Marks a backup the household owns (or a hypothetical one) as confirmed compatible with the device.",
                         renterFriendly: true, feasibilityNotes: ["feasibility.manufacturer-guidance"]),
        ActionDefinition(id: "act.medical.continuity-plan", effort: .noCost, sourceIDs: ["S25"], scenarioIDs: power,
                         simulates: nil, renterFriendly: true, feasibilityNotes: ["feasibility.care-team"]),
        ActionDefinition(id: "act.medical.document-runtime", effort: .noCost, sourceIDs: ["S25"], scenarioIDs: power,
                         simulates: nil, renterFriendly: true, feasibilityNotes: ["feasibility.manufacturer-guidance"]),
        ActionDefinition(id: "act.refrigeration.cooler-plan", effort: .low, sourceIDs: ["S20", "S25"], scenarioIDs: power,
                         simulates: "Adds a confirmed cooler and ice packs (partial substitute only).", renterFriendly: true,
                         feasibilityNotes: ["feasibility.ask-pharmacist"]),
        ActionDefinition(id: "act.relocation.arrange", effort: .noCost, sourceIDs: ["S20", "S21"], scenarioIDs: relocation,
                         simulates: "Adds an agreed destination with confirmed conditions and agreed transport.", renterFriendly: true,
                         feasibilityNotes: ["feasibility.confirm-host"]),
        ActionDefinition(id: "act.assist.assign-helper", effort: .noCost, sourceIDs: ["S19", "S22"], scenarioIDs: all6,
                         simulates: "Assigns an adult household member as helper.", renterFriendly: true, feasibilityNotes: []),
        ActionDefinition(id: "act.tornado.choose-shelter", effort: .noCost, sourceIDs: ["S22"], scenarioIDs: ["tornado"],
                         simulates: "Marks an interior lowest-floor room as the chosen shelter location (not an engineered safe room).",
                         renterFriendly: true, feasibilityNotes: ["feasibility.not-safe-room"]),
        ActionDefinition(id: "act.tornado.sturdy-building-plan", effort: .noCost, sourceIDs: ["S22"], scenarioIDs: ["tornado"],
                         simulates: "Adds an agreed sturdy destination and transport to use when a watch is issued.", renterFriendly: true,
                         feasibilityNotes: ["feasibility.confirm-host"]),
        ActionDefinition(id: "act.fire.verify-second-exit", effort: .noCost, sourceIDs: ["S19"], scenarioIDs: ["home-fire"],
                         simulates: nil, renterFriendly: true, feasibilityNotes: ["feasibility.landlord-for-repairs"]),
        ActionDefinition(id: "act.fire.helper-reach-plan", effort: .noCost, sourceIDs: ["S19"], scenarioIDs: ["home-fire"],
                         simulates: nil, renterFriendly: true, feasibilityNotes: []),
        ActionDefinition(id: "act.fire.meeting-point", effort: .noCost, sourceIDs: ["S19"], scenarioIDs: ["home-fire"],
                         simulates: nil, renterFriendly: true, feasibilityNotes: []),
        ActionDefinition(id: "act.fire.smoke-alarms", effort: .low, sourceIDs: ["S19"], scenarioIDs: ["home-fire"],
                         simulates: nil, renterFriendly: true, feasibilityNotes: ["feasibility.landlord-for-repairs"]),
        ActionDefinition(id: "act.fire.practice-drill", effort: .noCost, sourceIDs: ["S19"], scenarioIDs: ["home-fire"],
                         simulates: nil, renterFriendly: true, feasibilityNotes: []),
        ActionDefinition(id: "act.heat.ask-blower", effort: .noCost, sourceIDs: ["S20"], scenarioIDs: ["freeze-power-loss"],
                         simulates: nil, renterFriendly: true, feasibilityNotes: ["feasibility.landlord-or-technician"]),
        ActionDefinition(id: "act.water.store-3day", effort: .low, sourceIDs: ["S26"], scenarioIDs: ["freeze-power-loss", "water-outage", "flash-flood", "tornado"],
                         simulates: "Sets stored water to the 3-day storage target (1 gal/person/day).", renterFriendly: true,
                         feasibilityNotes: ["feasibility.limited-storage"]),
        ActionDefinition(id: "act.water.save-utility-contact", effort: .noCost, sourceIDs: ["S24"], scenarioIDs: ["water-outage", "flash-flood"],
                         simulates: nil, renterFriendly: true, feasibilityNotes: []),
        ActionDefinition(id: "act.water.well-test-after-flood", effort: .low, sourceIDs: ["S24"], scenarioIDs: ["flash-flood"],
                         simulates: nil, renterFriendly: false, feasibilityNotes: []),
        ActionDefinition(id: "act.comms.power-bank", effort: .low, sourceIDs: ["S20"], scenarioIDs: power,
                         simulates: "Adds two full phone recharges from charged power banks.", renterFriendly: true, feasibilityNotes: []),
        ActionDefinition(id: "act.comms.weather-radio", effort: .low, sourceIDs: ["S22", "S20"], scenarioIDs: ["tornado", "flash-flood", "freeze-power-loss"],
                         simulates: "Adds a confirmed battery or hand-crank weather radio.", renterFriendly: true, feasibilityNotes: []),
        ActionDefinition(id: "act.alerts.enroll-local", effort: .noCost, sourceIDs: ["S17", "S27"], scenarioIDs: all6,
                         simulates: nil, renterFriendly: true, feasibilityNotes: []),
        ActionDefinition(id: "act.pets.carrier-plan", effort: .low, sourceIDs: ["S19", "S20"], scenarioIDs: relocation,
                         simulates: nil, renterFriendly: true, feasibilityNotes: []),
        ActionDefinition(id: "act.generator.outdoor-placement", effort: .noCost, sourceIDs: ["S20"], scenarioIDs: power,
                         simulates: nil, renterFriendly: false, feasibilityNotes: ["feasibility.generator-20ft"]),
        ActionDefinition(id: "act.flood.higher-ground-plan", effort: .noCost, sourceIDs: ["S23"], scenarioIDs: ["flash-flood"],
                         simulates: nil, renterFriendly: true, feasibilityNotes: []),
    ])
}
