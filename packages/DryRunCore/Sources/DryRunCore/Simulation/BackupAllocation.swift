import Foundation

/// Why a backup source can or cannot supply a load. Reasons surface in explanations.
public enum BackupUsability: String, Codable, Sendable, Hashable {
    case usable
    case setupUnconfirmed
    case setupNotDone
    /// Grid-tied solar without confirmed islanding/storage is not outage backup.
    case gridTiedSolarNotBackup
    case islandingUnconfirmed
    /// A portable generator is only modelled with a confirmed outdoor location >= 20 ft from openings [S20].
    case generatorPlacementUnconfirmed
    case depleted
    case notForThisLoad
}

public struct BackupAssignment: Codable, Sendable, Hashable {
    public var loadID: String
    public var sourceID: String?
    public var state: ServiceState
    public var reason: String
}

/// Allocates each backup's continuous output across loads exactly once, in deterministic load order
/// (essential equipment by ID, then home circuits). Energy drain is computed from loads whose draw is known;
/// if any load's draw is unknown the source's runtime is unknown rather than estimated.
public struct BackupAllocator: Sendable {
    public init() {}

    public static func usability(_ b: BackupPowerSource, energyRemaining: Double??) -> BackupUsability {
        switch b.kind {
        case .solarGridTiedOnly: return .gridTiedSolarNotBackup
        case .solarWithBattery:
            if b.islandingConfirmed.confirmedValue != true {
                return b.islandingConfirmed.isConfirmed ? .gridTiedSolarNotBackup : .islandingUnconfirmed
            }
        case .portableGenerator:
            if b.safeOutdoorPlacementConfirmed.confirmedValue != true { return .generatorPlacementUnconfirmed }
        default: break
        }
        switch b.setupConfirmed.confirmedValue {
        case .some(true): break
        case .some(false): return .setupNotDone
        case .none: return .setupUnconfirmed
        }
        if let e = energyRemaining, let v = e, v <= 0 { return .depleted }
        return .usable
    }

    /// - Parameters:
    ///   - gridAvailable: when true no backup is drawn.
    ///   - energyRemaining: per backup ID (nil = unknown).
    /// - Returns: per-load assignments, plus per-source drain in Wh/hour (nil = unknown runtime).
    public func allocate(household h: HouseholdProfile, gridAvailable: Bool, energyRemaining: [String: Double?])
        -> (assignments: [String: BackupAssignment], drainWhPerHour: [String: Double?]) {
        var out: [String: BackupAssignment] = [:]
        var drain: [String: Double?] = [:]
        guard !gridAvailable else { return (out, drain) }

        var outputUsed: [String: Double] = [:]
        var drawUnknown: Set<String> = []
        var loadsOnSource: [String: Int] = [:]
        let sources = Dictionary(uniqueKeysWithValues: h.backupPower.map { ($0.id, $0) })

        func tryAssign(load: String, candidates: [String], watts: Double?) {
            var lastReason = "noCompatibleBackup"
            var lastState: ServiceState = .unavailable
            for sid in candidates.sorted() {
                guard let b = sources[sid] else { lastReason = "unknownBackup"; continue }
                let use = Self.usability(b, energyRemaining: energyRemaining[sid])
                guard use == .usable else {
                    lastReason = use.rawValue
                    // Unconfirmed setup leaves the outcome unknown, never operational.
                    if use == .setupUnconfirmed || use == .islandingUnconfirmed { lastState = .unknown }
                    continue
                }
                if drawUnknown.contains(sid), (loadsOnSource[sid] ?? 0) > 0 {
                    lastReason = "sharedDrawUnknown"; lastState = .unknown; continue
                }
                if let w = watts {
                    if let cap = b.continuousOutputW.confirmedValue {
                        let used = outputUsed[sid, default: 0]
                        guard used + w <= cap + 1e-9 else { lastReason = "outputLimitReached"; lastState = .unavailable; continue }
                        outputUsed[sid] = used + w
                    } else {
                        // Output limit unknown: cannot confirm the load fits.
                        lastReason = "outputLimitUnknown"; lastState = .unknown; continue
                    }
                } else {
                    if (loadsOnSource[sid] ?? 0) > 0 || outputUsed[sid] != nil {
                        // Sharing a source with an unknown draw cannot be confirmed.
                        lastReason = "sharedDrawUnknown"; lastState = .unknown; continue
                    }
                    drawUnknown.insert(sid)
                }
                loadsOnSource[sid, default: 0] += 1
                out[load] = BackupAssignment(loadID: load, sourceID: sid, state: .operational, reason: "assigned")
                return
            }
            out[load] = BackupAssignment(loadID: load, sourceID: nil, state: lastState, reason: lastReason)
        }

        for eq in h.equipment.sorted(by: { $0.id < $1.id }) where eq.requiresElectricalPower {
            tryAssign(load: Load.equipment(eq.id), candidates: eq.compatibleBackupIDs, watts: eq.powerWatts.confirmedValue)
        }
        for b in h.backupPower.sorted(by: { $0.id < $1.id }) where b.kind == .standbyGenerator {
            // Whole-home circuits: draw is not itemised, so runtime is unknown unless fuel is known.
            tryAssign(load: Load.homeCircuits(via: b.id), candidates: [b.id], watts: nil)
        }

        for (sid, b) in sources {
            guard loadsOnSource[sid] != nil else { continue }
            if drawUnknown.contains(sid) { drain[sid] = .some(nil); continue }
            let eff = max(0.05, min(1, b.assumedEfficiency))
            drain[sid] = .some((outputUsed[sid] ?? 0) / eff)
        }
        return (out, drain)
    }
}
