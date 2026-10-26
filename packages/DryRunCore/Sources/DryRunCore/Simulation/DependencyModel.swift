import Foundation

// Dependency model (graph #1). Distinct from the geometric egress graph (Spatial/).
//
// Every derived service has a requirement expression with AND/OR semantics. A device may need
// compatible power AND usable equipment; grid OR a confirmed compatible backup satisfies power.
// "Remove everything downstream of the grid" is wrong: it disables working backups.
//
// Evaluation is a bounded fixed point (see `DependencyModel.evaluate`). Nodes are built in an
// acyclic order, so evaluation converges in at most `nodes.count + 1` passes; anything else is a
// hard `DependencyError.nonConvergent` (authoring/building bug), never a silent result.

public indirect enum Requirement: Sendable, Hashable {
    /// Another derived node or an external input (grid, cellular, roads, ...).
    case service(String)
    case all([Requirement])
    case any([Requirement])
    /// Known true -> operational, known false -> unavailable, unknown -> unknown.
    case fact(Bool?)
    /// Known true -> degraded (partial substitute such as a cooler), false -> unavailable, unknown -> unknown.
    case partialFact(Bool?)
    /// Supply from the backup allocation table for this load.
    case backupSupply(loadID: String)
    case fixed(ServiceState)
}

public struct DependencyNode: Sendable, Hashable {
    public var id: String
    public var requirement: Requirement
    /// Household/home facts this node reads (explanation chains).
    public var factIDs: [String]
    public var ruleID: String
}

public enum DependencyError: Error, Equatable, Sendable {
    case nonConvergent(iterations: Int)
}

/// AND: any unavailable -> unavailable; else any unknown -> unknown; else any degraded -> degraded.
/// OR: any operational -> operational; else any degraded -> degraded; else any unknown -> unknown.
enum StateAlgebra {
    static func and(_ xs: [ServiceState]) -> ServiceState {
        if xs.isEmpty { return .operational }
        if xs.contains(.unavailable) { return .unavailable }
        if xs.contains(.unknown) { return .unknown }
        if xs.contains(.degraded) { return .degraded }
        return .operational
    }
    static func or(_ xs: [ServiceState]) -> ServiceState {
        if xs.isEmpty { return .unavailable }
        if xs.contains(.operational) { return .operational }
        if xs.contains(.degraded) { return .degraded }
        if xs.contains(.unknown) { return .unknown }
        return .unavailable
    }
}

public struct DependencyModel: Sendable {
    public var nodes: [DependencyNode]

    public init(nodes: [DependencyNode]) { self.nodes = nodes }

    /// Bounded fixed-point evaluation. `inputs` hold external services; `backup` the allocation table.
    public func evaluate(inputs: [String: ServiceState], backup: [String: ServiceState],
                         maxIterations: Int? = nil) throws -> [String: ServiceState] {
        var values: [String: ServiceState] = [:]
        for n in nodes { values[n.id] = .unknown }
        let limit = maxIterations ?? (nodes.count + 1)
        for _ in 0..<max(limit, 1) {
            var changed = false
            for n in nodes {
                let v = eval(n.requirement, values: values, inputs: inputs, backup: backup)
                if values[n.id] != v { values[n.id] = v; changed = true }
            }
            if !changed { return values }
        }
        throw DependencyError.nonConvergent(iterations: limit)
    }

    func eval(_ r: Requirement, values: [String: ServiceState], inputs: [String: ServiceState], backup: [String: ServiceState]) -> ServiceState {
        switch r {
        case .service(let id): return values[id] ?? inputs[id] ?? .unknown
        case .all(let xs): return StateAlgebra.and(xs.map { eval($0, values: values, inputs: inputs, backup: backup) })
        case .any(let xs): return StateAlgebra.or(xs.map { eval($0, values: values, inputs: inputs, backup: backup) })
        case .fact(let b): return b.map { $0 ? .operational : .unavailable } ?? .unknown
        case .partialFact(let b): return b.map { $0 ? .degraded : .unavailable } ?? .unknown
        case .backupSupply(let load): return backup[load] ?? .unavailable
        case .fixed(let s): return s
        }
    }

    public func node(_ id: String) -> DependencyNode? { nodes.first { $0.id == id } }

    /// Builds the household's dependency model. Order matters only for readability: evaluation is a fixed point.
    public static func build(household h: HouseholdProfile) -> DependencyModel {
        var nodes: [DependencyNode] = []
        let standby = h.backupPower.filter { $0.kind == .standbyGenerator }.map(\.id)

        // Home circuits: grid, or a confirmed whole-home standby generator. Portable stations do not power circuits.
        var homeTerms: [Requirement] = [.service(Svc.grid)]
        homeTerms += standby.map { .backupSupply(loadID: Load.homeCircuits(via: $0)) }
        nodes.append(DependencyNode(id: Svc.homePower, requirement: .any(homeTerms),
                                    factIDs: ["backupPower"] , ruleID: "rule.dependency.home-power"))

        // Heating. Gas/propane may still need powered controls or blowers: unknown stays unknown.
        let heat: Requirement
        let needsPower = h.housing.heatingNeedsElectricity
        switch h.housing.heatingFuel {
        case .electric: heat = .service(Svc.homePower)
        case .naturalGas, .propane:
            if needsPower.isConfirmed, needsPower.value == true { heat = .service(Svc.homePower) }
            else if needsPower.isConfirmed, needsPower.value == false { heat = .fixed(.operational) }
            else { heat = .any([.service(Svc.homePower), .fact(nil)]) }
        case .wood: heat = .fixed(.operational)
        case .none: heat = .fixed(.unavailable)
        case .unknown: heat = .fact(nil)
        }
        nodes.append(DependencyNode(id: Svc.heat, requirement: heat,
                                    factIDs: ["housing.heatingFuel", "housing.heatingNeedsElectricity"], ruleID: "rule.dependency.heat"))

        let cooling: Requirement
        switch h.housing.cooling {
        case .centralAC, .windowOrPortableAC, .evaporative: cooling = .service(Svc.homePower)
        // Fans are not treated as cooling access [S21].
        case .fansOnly, .none: cooling = .fixed(.unavailable)
        case .unknown: cooling = .fact(nil)
        }
        nodes.append(DependencyNode(id: Svc.cooling, requirement: cooling, factIDs: ["housing.cooling"], ruleID: "rule.dependency.cooling"))

        nodes.append(DependencyNode(id: Svc.refrigeration, requirement: .service(Svc.homePower), factIDs: [], ruleID: "rule.dependency.refrigeration"))

        // Water supply. A private electric well stops without power; municipal supply does not fail
        // because this home lost power — only an authored utility event changes it.
        switch h.housing.waterSource {
        case .privateWell:
            let pump: Requirement
            let electric = h.housing.wellPumpElectric
            let power: Requirement
            if electric.isConfirmed, electric.value == false { power = .fixed(.operational) }
            else if electric.isConfirmed { power = .service(Svc.homePower) }
            else { power = .any([.service(Svc.homePower), .fact(nil)]) }
            // Pump needs power AND a working pump/pipes (an authored failure can break the latter).
            pump = .all([power, .service(Svc.wellMechanical)])
            nodes.append(DependencyNode(id: Svc.wellPump, requirement: pump,
                                        factIDs: ["housing.waterSource", "housing.wellPumpElectric"], ruleID: "rule.dependency.well-pump"))
            nodes.append(DependencyNode(id: Svc.waterSupply, requirement: .service(Svc.wellPump),
                                        factIDs: ["housing.waterSource"], ruleID: "rule.dependency.water-supply"))
            nodes.append(DependencyNode(id: Svc.waterSafety, requirement: .service(Svc.wellSafety),
                                        factIDs: ["housing.waterSource"], ruleID: "rule.dependency.water-safety"))
        case .municipal:
            nodes.append(DependencyNode(id: Svc.waterSupply, requirement: .service(Svc.municipalSupply),
                                        factIDs: ["housing.waterSource"], ruleID: "rule.dependency.water-supply"))
            nodes.append(DependencyNode(id: Svc.waterSafety, requirement: .service(Svc.utilitySafety),
                                        factIDs: ["housing.waterSource"], ruleID: "rule.dependency.water-safety"))
        case .unknown:
            nodes.append(DependencyNode(id: Svc.waterSupply, requirement: .fact(nil), factIDs: ["housing.waterSource"], ruleID: "rule.dependency.water-supply"))
            nodes.append(DependencyNode(id: Svc.waterSafety, requirement: .fact(nil), factIDs: ["housing.waterSource"], ruleID: "rule.dependency.water-safety"))
        }

        // Home Wi-Fi needs router power AND upstream internet. Cellular is a separate external service.
        let router: Requirement = .any([.service(Svc.homePower), .fact(h.communications.routerOnBackup.confirmedValue == true ? true : false)])
        nodes.append(DependencyNode(id: Svc.wifi, requirement: .all([router, .service(Svc.internet)]),
                                    factIDs: ["communications.routerOnBackup"], ruleID: "rule.dependency.wifi"))

        // Official alert reception: a charged handset with cellular or Wi-Fi, OR a confirmed battery/crank radio.
        nodes.append(DependencyNode(id: Svc.alerts,
                                    requirement: .any([.all([.service(Svc.handset), .any([.service(Svc.cellular), .service(Svc.wifi)])]),
                                                       .fact(h.communications.batteryOrCrankRadio.confirmedValue == true ? true : false)]),
                                    factIDs: ["communications.handsetRuntimeHours", "communications.batteryOrCrankRadio"],
                                    ruleID: "rule.dependency.alerts"))

        // Essential equipment: power from grid/home circuits OR an allocated, confirmed compatible backup.
        for eq in h.equipment.sorted(by: { $0.id < $1.id }) {
            let req: Requirement
            if eq.needsRefrigeration {
                req = .any([.service(Svc.refrigeration), .service(Svc.relocatedPower), .partialFact(h.supplies.coolerAndIcePacks.confirmedValue)])
            } else {
                // After relocation to a destination with confirmed conditions, the device can use power there.
                req = .any([.service(Svc.homePower), .backupSupply(loadID: Load.equipment(eq.id)), .service(Svc.relocatedPower)])
            }
            nodes.append(DependencyNode(id: Svc.device(eq.id), requirement: req,
                                        factIDs: ["equipment.\(eq.id)"] + eq.compatibleBackupIDs.map { "backup.\($0).setupConfirmed" },
                                        ruleID: "rule.dependency.device"))
        }

        // Transport: roads AND (a suitable vehicle OR an agreed alternative). "No car" is a normal path.
        let wheelchair = h.people.contains { $0.needs.contains(.usesWheelchair) }
        var transportOptions: [Requirement] = h.transport.vehicles.sorted { $0.id < $1.id }.map { v in
            wheelchair ? .fact(v.wheelchairAccessible.confirmedValue) : .fixed(.operational)
        }
        transportOptions += h.transport.alternatives.sorted { $0.id < $1.id }.map { a in
            let agreed = a.agreed.confirmedValue
            if wheelchair {
                guard let ag = agreed else { return .fact(nil) }
                return ag ? .fact(a.wheelchairAccessible.confirmedValue) : .fact(false)
            }
            return .fact(agreed)
        }
        nodes.append(DependencyNode(id: Svc.transport, requirement: .all([.service(Svc.roads), .any(transportOptions)]),
                                    factIDs: ["transport.vehicles", "transport.alternatives"] + (wheelchair ? ["people.needs.usesWheelchair"] : []),
                                    ruleID: "rule.dependency.transport"))

        let destinationOptions: [Requirement] = h.transport.destinations.sorted { $0.id < $1.id }.map { .fact($0.conditionsConfirmed.confirmedValue) }
        nodes.append(DependencyNode(id: Svc.destination, requirement: .any(destinationOptions),
                                    factIDs: ["transport.destinations"], ruleID: "rule.dependency.destination"))

        return DependencyModel(nodes: nodes)
    }
}

/// Service identifiers (see docs/CONTRACTS.md).
public enum Svc {
    // External inputs (set only by authored events)
    public static let grid = "svc.grid"
    public static let cellular = "svc.cellular"
    public static let internet = "svc.internet"
    public static let roads = "svc.roads"
    public static let municipalSupply = "svc.water.municipal"
    public static let utilitySafety = "svc.water.utilitySafety"
    public static let wellSafety = "svc.water.wellSafety"
    public static let wellMechanical = "svc.wellPump.mechanical"
    public static let handset = "svc.handset"
    /// Operational once the household has relocated to a destination with confirmed conditions.
    public static let relocatedPower = "svc.relocated"
    // Derived
    public static let homePower = "svc.power.home"
    public static let heat = "svc.heat"
    public static let cooling = "svc.cooling"
    public static let refrigeration = "svc.refrigeration"
    public static let wellPump = "svc.wellPump"
    public static let waterSupply = "svc.water.supply"
    public static let waterSafety = "svc.water.safety"
    public static let wifi = "svc.wifi"
    public static let alerts = "svc.alerts"
    public static let transport = "svc.transport"
    public static let destination = "svc.destination"
    public static func device(_ id: String) -> String { "svc.device.\(id)" }

    public static let externalDefaults: [String: ServiceState] = [
        grid: .operational, cellular: .operational, internet: .operational, roads: .operational,
        municipalSupply: .operational, utilitySafety: .operational, wellSafety: .operational, wellMechanical: .operational,
        handset: .operational, relocatedPower: .unavailable,
    ]
}

enum Load {
    static func equipment(_ id: String) -> String { "load.equipment.\(id)" }
    static func homeCircuits(via id: String) -> String { "load.home.\(id)" }
}
