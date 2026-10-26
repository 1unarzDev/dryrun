import Foundation

/// "Do this now" for an active alert: at most three immediate protective steps for this household, chosen
/// deterministically from recorded facts (people's needs and helpers, essential equipment, water source, the home's
/// confirmed interior rooms). Beacon may explain them; it never adds, removes or reorders them.
public enum AlertResponse {
    public enum Ref: Codable, Sendable, Hashable {
        case person(String), equipment(String), space(String)
    }

    public struct Step: Codable, Sendable, Hashable, Identifiable {
        /// Localization key `alert.step.<key>`; `values` fill its placeholders after the app resolves each reference.
        public var key: String
        public var values: [String: Ref]
        public var sourceIDs: [String]
        public init(key: String, values: [String: Ref], sourceIDs: [String]) { self.key = key; self.values = values; self.sourceIDs = sourceIDs }
        public var id: String { key + values.keys.sorted().map { "|\($0)=\(String(describing: values[$0]!))" }.joined() }
    }

    public static func steps(scenarioID: String, household: HouseholdProfile, home: HomeModel?) -> [Step] {
        let essential = household.equipment.filter { $0.isEssential }
        let powered = essential.first { $0.requiresElectricalPower }
        let cold = essential.first { $0.requiresColdStorage }
        let needsHelp = household.people.first { p in
            p.needs.contains(where: { [.usesWheelchair, .cannotUseStairs, .limitedMobility, .needsHelperToEvacuate].contains($0) })
        }
        var steps: [Step] = []
        func add(_ key: String, _ values: [String: Ref] = [:], _ sources: [String]) {
            guard steps.count < 3 else { return }
            steps.append(Step(key: key, values: values, sourceIDs: sources))
        }
        func helpStep(_ key: String, _ sources: [String]) {
            guard let person = needsHelp else { return }
            if let helper = person.helperPersonID, household.people.contains(where: { $0.id == helper }) {
                add(key + "-helper", ["person": .person(person.id), "helper": .person(helper)], sources)
            } else {
                add(key + "-nohelper", ["person": .person(person.id)], sources)
            }
        }

        switch scenarioID {
        case "tornado":
            if let room = shelterRoom(home) { add("tornado-go-room", ["room": .space(room.id)], ["S22"]) }
            else { add("tornado-go-lowest", [:], ["S22"]) }
            helpStep("tornado-move", ["S22"])
            if let powered { add("tornado-bring-backup", ["equipment": .equipment(powered.id)], ["S25"]) }
            add("tornado-shoes-light", [:], ["S22"])
        case "flash-flood":
            add("flood-no-driving", [:], ["S23"])
            if let powered { add("flood-charge", ["equipment": .equipment(powered.id)], ["S25"]) }
            helpStep("flood-move", ["S23"])
            add("flood-higher", [:], ["S23"])
        case "heat-grid-strain":
            if let sensitive = household.people.first(where: { $0.needs.contains(.heatSensitive) || $0.ageBand == .olderAdult || $0.ageBand == .infant }) {
                add("heat-check-person", ["person": .person(sensitive.id)], ["S21"])
            }
            if let cold { add("heat-cold-storage", ["equipment": .equipment(cold.id)], ["S25"]) }
            if let powered, powered.id != cold?.id { add("heat-charge", ["equipment": .equipment(powered.id)], ["S25"]) }
            add("heat-cool-room", [:], ["S21"])
        case "freeze-power-loss":
            if let powered { add("freeze-charge", ["equipment": .equipment(powered.id)], ["S20", "S25"]) }
            if household.housing.waterSource == .privateWell, household.housing.wellPumpElectric.value != false {
                add("freeze-fill-water-well", [:], ["S26"])
            } else {
                add("freeze-fill-water", [:], ["S26"])
            }
            if let sensitive = household.people.first(where: { $0.needs.contains(.coldSensitive) || $0.ageBand == .olderAdult || $0.ageBand == .infant }) {
                add("freeze-warm-person", ["person": .person(sensitive.id)], ["S20"])
            }
            add("freeze-safe-heat", [:], ["S20"])
        default:
            break
        }
        return steps
    }

    /// A room the household confirmed has no windows, on the lowest floor; small rooms first (source S22).
    static func shelterRoom(_ home: HomeModel?) -> Space? {
        guard let home, !home.isFictionalPlaceholder else { return nil }
        let lowest = home.floors.min { $0.level < $1.level }?.id
        let preferred: [SpaceKind] = [.bathroom, .closet, .hallway, .laundry]
        return home.spaces
            .filter { $0.floorID == lowest && $0.interiorNoWindowsConfirmed.confirmedValue == true }
            .min { (preferred.firstIndex(of: $0.kind) ?? 9, $0.id) < (preferred.firstIndex(of: $1.kind) ?? 9, $1.id) }
    }
}

private extension HomeModel {
    /// A home with no rooms says nothing about where to shelter.
    var isFictionalPlaceholder: Bool { spaces.isEmpty }
}
