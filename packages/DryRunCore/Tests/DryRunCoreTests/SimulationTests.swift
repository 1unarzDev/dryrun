import Foundation
import Testing
@testable import DryRunCore

// Simulation tests: section 18 "SIMULATION" bullets, using fictional households and the sample ranch home.

private func finalServices(_ r: RehearsalResult) -> [String: ServiceState] { r.snapshots.last?.services ?? [:] }
private func everUnmet(_ r: RehearsalResult) -> Set<String> { Set(r.snapshots.flatMap(\.unmetRequirements)) }
private func state(_ r: RehearsalResult, _ svc: String, at minute: Int) -> ServiceState? {
    r.snapshots.last { $0.simMinute <= minute }?.services[svc]
}
private func resource(_ r: RehearsalResult, _ id: String, at minute: Int) -> Double? {
    r.snapshots.last { $0.simMinute <= minute }?.resources[id]?.amount
}

@Suite("Simulation")
struct SimulationTests {
    @Test("Library loads six distinct, fictional, draft-reviewed packs")
    func libraryLoads() throws {
        let lib = SimFixtures.library
        #expect(lib.scenarios.map(\.id).sorted() == SimFixtures.scenarioIDs.sorted())
        for s in lib.scenarios {
            #expect(s.fictional)
            #expect(!s.choicePoints.isEmpty, "\(s.id) needs at least one decision")
            #expect(!s.sourceIDs.isEmpty)
            #expect(s.choicePoints.allSatisfy { cp in cp.options.contains { $0.unsafe } || cp.options.count >= 2 })
        }
    }

    @Test("Identical inputs give identical results, including equal-time ordering")
    func determinism() throws {
        for h in SampleHouseholds.all {
            for s in SimFixtures.scenarioIDs {
                let a = try SimFixtures.run(h, s), b = try SimFixtures.run(h, s)
                #expect(a == b, "\(h.id) \(s)")
                let enc = DryRunJSON.encoder()
                #expect(try enc.encode(a) == enc.encode(b))
                // Events are emitted in non-decreasing simulated time.
                #expect(zip(a.events, a.events.dropFirst()).allSatisfy { $0.simMinute <= $1.simMinute })
                #expect(Set(a.events.map(\.id)).count == a.events.count, "event IDs unique")
            }
        }
    }

    @Test("Authored events at the same minute order by priority then ID")
    func equalTimeOrdering() throws {
        let r = try SimFixtures.run(SampleHouseholds.lake, "water-outage", variants: ["do-not-drink"])
        let at361 = r.events.filter { $0.simMinute == 361 }.map(\.id)
        #expect(at361.first == "evt.water-outage.do-not-drink")
    }

    @Test("No compatible backup: essential device stops; unknown setup stays unknown, never operational")
    func unknownBackupDoesNotSupply() throws {
        let base = try SimFixtures.run(SampleHouseholds.oak, "freeze-power-loss")
        #expect(state(base, "svc.device.eq-oxygen", at: 200) == .unavailable)

        var h = SampleHouseholds.oak
        h.equipment[0].compatibleBackupIDs = ["bk-station"]       // listed, but setup still unconfirmed
        let r = try SimFixtures.run(h, "freeze-power-loss")
        #expect(state(r, "svc.device.eq-oxygen", at: 200) == .unknown)
        #expect(everUnmet(r).contains("req.power.eq-oxygen"))
    }

    @Test("Confirmed compatible backup supplies its intended load during the outage")
    func compatibleBackupSupplies() throws {
        var h = SampleHouseholds.oak
        h.equipment[0].compatibleBackupIDs = ["bk-station"]
        h.backupPower[0].setupConfirmed = .confirmed(true)
        let r = try SimFixtures.run(h, "freeze-power-loss")
        #expect(state(r, "svc.device.eq-oxygen", at: 200) == .operational)
        #expect(r.events.contains { $0.id == "evt.freeze-power-loss.svc.device.eq-oxygen.on-backup" })
        #expect(!everUnmet(r).contains("req.power.eq-oxygen"))
        // Heat is NOT powered by a portable station: grid loss still stops electric heat.
        #expect(state(r, "svc.heat", at: 200) == .unavailable)
    }

    @Test("Grid-tied solar and an unplaced generator are not outage backup")
    func ineligibleBackups() throws {
        var h = SampleHouseholds.oak
        h.backupPower = [
            BackupPowerSource(id: "bk-solar", kind: .solarGridTiedOnly, label: "Rooftop solar", usableEnergyWh: .confirmed(5000),
                              continuousOutputW: .confirmed(5000), setupConfirmed: .confirmed(true)),
            BackupPowerSource(id: "bk-gen", kind: .portableGenerator, label: "Portable generator", usableEnergyWh: .confirmed(8000),
                              continuousOutputW: .confirmed(3000), setupConfirmed: .confirmed(true)),
        ]
        h.equipment[0].compatibleBackupIDs = ["bk-solar", "bk-gen"]
        let r = try SimFixtures.run(h, "freeze-power-loss")
        #expect(state(r, "svc.device.eq-oxygen", at: 200) == .unavailable)
        #expect(r.recommendations.contains { $0.actionID == "act.generator.outdoor-placement" })
        #expect(BackupAllocator.usability(h.backupPower[0], energyRemaining: nil) == .gridTiedSolarNotBackup)
        #expect(BackupAllocator.usability(h.backupPower[1], energyRemaining: nil) == .generatorPlacementUnconfirmed)
    }

    @Test("Shared backup output and energy are never double-allocated or negative")
    func sharedBackupAllocation() throws {
        var h = SampleHouseholds.oak
        h.backupPower = [BackupPowerSource(id: "bk-shared", kind: .portableBatteryStation, label: "Shared station",
                                           usableEnergyWh: .confirmed(1000), continuousOutputW: .confirmed(1000), setupConfirmed: .confirmed(true),
                                           assumedEfficiency: 1.0)]
        h.equipment = [
            PoweredEquipment(id: "eq-a", purpose: .oxygenConcentrator, label: "Device A", compatibleBackupIDs: ["bk-shared"], powerWatts: .confirmed(600)),
            PoweredEquipment(id: "eq-b", purpose: .cpapOrBipap, label: "Device B", compatibleBackupIDs: ["bk-shared"], powerWatts: .confirmed(600)),
        ]
        let r = try SimFixtures.run(h, "freeze-power-loss")
        // 600 W + 600 W exceeds the 1000 W output: only one device can be supplied.
        #expect(state(r, "svc.device.eq-a", at: 200) == .operational)
        #expect(state(r, "svc.device.eq-b", at: 200) == .unavailable)
        // 1000 Wh at 600 W -> 100 minutes after the outage at minute 180.
        #expect(r.events.contains { $0.id == "evt.freeze-power-loss.res.backup-depleted.bk-shared" && $0.simMinute == 280 })
        #expect(state(r, "svc.device.eq-a", at: 281) == .unavailable)
        for snap in r.snapshots { for (_, q) in snap.resources { if let a = q.amount { #expect(a >= 0) } } }
        // Restoration does not refill the battery.
        #expect(resource(r, "res.backup.bk-shared", at: 4320) == 0)
    }

    @Test("Electric well loses water with power; municipal water does not")
    func wellVersusMunicipal() throws {
        let oak = try SimFixtures.run(SampleHouseholds.oak, "freeze-power-loss")
        #expect(state(oak, "svc.wellPump", at: 200) == .unavailable)
        #expect(state(oak, "svc.water.supply", at: 200) == .unavailable)
        // Stored water is tracked separately and is not erased by the pump stopping.
        #expect(resource(oak, "res.water.stored", at: 180) == 5)

        let lake = try SimFixtures.run(SampleHouseholds.lake, "freeze-power-loss")
        #expect(state(lake, "svc.water.supply", at: 200) == .operational)
        #expect(state(lake, "svc.water.safety", at: 200) == .operational)
        #expect(resource(lake, "res.water.stored", at: 2000) == 2)   // not drawn: taps still work
    }

    @Test("Power restoration does not clear advisories, refill storage, or certify devices")
    func restorationLimits() throws {
        let lake = try SimFixtures.run(SampleHouseholds.lake, "water-outage", variants: ["do-not-drink", "with-power-loss"])
        #expect(lake.events.contains { $0.id == "evt.water-outage.power-restored" })
        #expect(state(lake, "svc.water.safety", at: 1900) == .unavailable)
        #expect(lake.events.contains { $0.id == "evt.water-outage.recovery.advisory-remains" })

        let oak = try SimFixtures.run(SampleHouseholds.oak, "freeze-power-loss")
        #expect(oak.events.contains { $0.id == "evt.freeze-power-loss.recovery.check-device.eq-oxygen" })
        #expect(oak.events.contains { $0.id == "evt.freeze-power-loss.recovery.water-not-refilled" })
        #expect((resource(oak, "res.water.stored", at: 4320) ?? 99) < 5)
    }

    @Test("Unknown essential-device runtime stays unknown and yields a verification action")
    func unknownRuntime() throws {
        var h = SampleHouseholds.oak
        h.equipment[0].compatibleBackupIDs = ["bk-station"]
        h.backupPower[0].setupConfirmed = .confirmed(true)
        let r = try SimFixtures.run(h, "freeze-power-loss")
        #expect(r.unknowns.contains("equipment.eq-oxygen.runtime"))
        #expect(r.snapshots.allSatisfy { $0.resources["res.device.eq-oxygen.runtime"]?.amount == nil })
        #expect(!r.events.contains { $0.id.contains("device-runtime-reached") })
        #expect(r.recommendations.contains { $0.actionID == "act.medical.document-runtime" && $0.tier == .blockingUnknownFact })

        // With documented runtime, the depletion is scheduled from that documentation (not a generic calculator).
        h.equipment[0].documentedBackupRuntimeHours = .confirmed(5, unit: "h")
        let r2 = try SimFixtures.run(h, "freeze-power-loss")
        #expect(r2.events.contains { $0.id == "evt.freeze-power-loss.res.device-runtime-reached.eq-oxygen" && $0.simMinute == 480 })
        #expect(state(r2, "svc.device.eq-oxygen", at: 481) == .unavailable)
    }

    @Test("Chemical do-not-drink / do-not-use never recommend boiling")
    func chemicalNoBoil() throws {
        for v in ["do-not-drink", "do-not-use"] {
            let r = try SimFixtures.run(SampleHouseholds.lake, "water-outage", choices: ["choice.water-outage.drinking-water": "boil-tap"], variants: [v])
            let d = try #require(r.decisions.first { $0.id == "choice.water-outage.drinking-water" })
            #expect(d.options.first { $0.id == "boil-tap" }?.isRecommended == false)
            #expect(r.events.contains { $0.id == "evt.water-outage.advisory.boil-not-remedy" })
            #expect(r.events.contains { $0.id == "evt.water-outage.boil.not-feasible" && $0.templateValues["reason"] == "notRemedyForAdvisory" })
            #expect(!r.recommendations.contains { $0.actionID.contains("boil") })
            #expect(state(r, "svc.water.safety", at: 4000) == .unavailable || state(r, "svc.water.safety", at: 3500) == .unavailable)
        }
        // Boil-water advisory with power: boiling is a feasible, recommended option.
        let boil = try SimFixtures.run(SampleHouseholds.lake, "water-outage")
        #expect(boil.decisions.first?.options.first { $0.id == "boil-tap" }?.isRecommended == true)
        // Boil-water advisory without power: not feasible (no confirmed heat source).
        let noPower = try SimFixtures.run(SampleHouseholds.lake, "water-outage", choices: ["choice.water-outage.drinking-water": "boil-tap"],
                                          variants: ["with-power-loss"])
        #expect(noPower.decisions.first?.options.first { $0.id == "boil-tap" }?.isRecommended == false)
        #expect(noPower.events.contains { $0.templateValues["reason"] == "noHeatSource" })
    }

    @Test("Advisory types are distinct service effects")
    func advisoryTypes() throws {
        let base = try SimFixtures.run(SampleHouseholds.lake, "water-outage")
        #expect(state(base, "svc.water.supply", at: 10) == .unavailable)   // quantity unavailable
        #expect(state(base, "svc.water.safety", at: 362) == .degraded)     // boil water
        let dnd = try SimFixtures.run(SampleHouseholds.lake, "water-outage", variants: ["do-not-drink"])
        #expect(state(dnd, "svc.water.safety", at: 362) == .unavailable)
        let well = try SimFixtures.run(SampleHouseholds.oak, "water-outage")
        #expect(state(well, "svc.water.safety", at: 362) == .unknown)       // unknown quality, not a utility advisory
        #expect(!well.events.contains { $0.id.contains("boil-advisory") })
    }

    @Test("No-car household cannot complete a vehicle-dependent relocation without an explicit alternative")
    func noCar() throws {
        let choice = ["choice.heat-grid-strain.hottest-hours": "relocate"]
        let r = try SimFixtures.run(SampleHouseholds.lake, "heat-grid-strain", choices: choice)
        #expect(r.events.contains { $0.id == "evt.heat-grid-strain.relocation.blocked" && $0.templateValues["reason"] == "noVehicle" })
        #expect(everUnmet(r).contains("req.relocation"))
        let d = try #require(r.decisions.first { $0.id == "choice.heat-grid-strain.hottest-hours" })
        #expect(d.options.first { $0.id == "relocate" }?.isRecommended == false)
        // Recommendation names the gap; trying it enables relocation in the replay.
        let rec = try #require(r.recommendations.first { $0.actionID == "act.relocation.arrange" })
        #expect(rec.tier == .unmetEssentialRequirement)
        #expect(rec.matchedFactIDs.contains("transport.vehicles"))
        let fixed = try SimFixtures.run(SampleHouseholds.lake, "heat-grid-strain", choices: choice, interventions: [rec.tryIntervention!])
        #expect(fixed.events.contains { $0.id == "evt.heat-grid-strain.relocation.done" })
        #expect(!everUnmet(fixed).contains("req.relocation"))
    }

    @Test("Handset depletion, charging, Wi-Fi loss and cellular loss are distinct outcomes")
    func communications() throws {
        let lake = try SimFixtures.run(SampleHouseholds.lake, "freeze-power-loss")
        let dead = try #require(lake.events.first { $0.id == "evt.freeze-power-loss.res.handset-depleted" })
        #expect(dead.simMinute == 180 + 18 * 60)
        #expect(state(lake, "svc.wifi", at: 200) == .unavailable)
        #expect(state(lake, "svc.cellular", at: 200) == .operational)   // Wi-Fi loss is not cellular loss
        #expect(state(lake, "svc.cellular", at: 1600) == .degraded)
        #expect(state(lake, "svc.handset", at: 1300) == .unavailable)
        // A simulated dead phone does not end the exercise: later decisions, events, debrief still exist.
        #expect(lake.decisions.contains { $0.simMinute > dead.simMinute })
        #expect(lake.events.contains { $0.simMinute > dead.simMinute })
        #expect(!lake.recommendations.isEmpty)
        #expect(lake.recommendations.contains { $0.actionID == "act.comms.power-bank" })

        // Oak has power banks: recharges instead of dying, and a powered handset keeps the offline plan.
        let oak = try SimFixtures.run(SampleHouseholds.oak, "freeze-power-loss")
        #expect(oak.events.contains { $0.id == "evt.freeze-power-loss.res.handset-recharged" })
        #expect(!oak.events.contains { $0.id == "evt.freeze-power-loss.res.handset-depleted" })
        #expect(oak.events.contains { $0.id == "evt.freeze-power-loss.checkpoint.offline-plan" })
    }

    @Test("Gas heat with unknown blower dependency stays unknown, not working or failed")
    func gasHeatUnknown() throws {
        let r = try SimFixtures.run(SampleHouseholds.pine, "freeze-power-loss")
        #expect(state(r, "svc.heat", at: 200) == .unknown)
        #expect(r.recommendations.contains { $0.actionID == "act.heat.ask-blower" })
        var h = SampleHouseholds.pine
        h.housing.heatingNeedsElectricity = .confirmed(false)
        #expect(state(try SimFixtures.run(h, "freeze-power-loss"), "svc.heat", at: 200) == .operational)
    }

    @Test("Grid strain is distinct from an authored outage")
    func gridStrain() throws {
        let r = try SimFixtures.run(SampleHouseholds.oak, "heat-grid-strain", variants: ["no-rotating-outage"])
        #expect(state(r, "svc.cooling", at: 100) == .degraded)
        #expect(!r.snapshots.contains { $0.services["svc.grid"] == .unavailable })
        #expect(!everUnmet(r).contains("req.power.eq-oxygen"))
        let withOutage = try SimFixtures.run(SampleHouseholds.oak, "heat-grid-strain")
        #expect(state(withOutage, "svc.cooling", at: 1550) == .unavailable)
    }

    @Test("Unsafe options are never defaults, never recommended, and never improve outcomes")
    func unsafeNeverRewarded() throws {
        for s in SimFixtures.library.scenarios {
            for cp in s.choicePoints {
                #expect(!(cp.options.first { $0.id == cp.defaultOptionID }!.unsafe))
            }
        }
        let safe = try SimFixtures.run(SampleHouseholds.oak, "freeze-power-loss")
        let oven = try SimFixtures.run(SampleHouseholds.oak, "freeze-power-loss", choices: ["choice.freeze-power-loss.keep-warm": "oven"])
        #expect(everUnmet(oven).isSuperset(of: everUnmet(safe)))
        #expect(oven.events.contains { $0.id == "evt.choice.freeze-power-loss.keep-warm" && $0.severity == .critical })
        for d in oven.decisions { for o in d.options where ["oven", "generator-indoors"].contains(o.id) { #expect(!o.isRecommended) } }
    }

    @Test("Fire: blocked usual route finds a modelled alternative; both blocked gives a typed no-route")
    func fireRoutes() throws {
        let r = try SimFixtures.run(SampleHouseholds.oak, "home-fire")
        #expect(r.events.contains { $0.id == "evt.home-fire.route.alternative.p-oak-3" && $0.templateValues["exit"] == "pt-front" })
        #expect(!everUnmet(r).contains { $0.hasPrefix("req.egress") })
        // Every route request after the origin event excludes the kitchen and never starts a re-entry.
        let blockedRuns = r.routes.filter { !$0.request.exclusions.blockedSpaceIDs.isEmpty }
        #expect(!blockedRuns.isEmpty)
        for route in blockedRuns { #expect(route.primary.map { !$0.spaceSequence.contains("sp-kitchen") } ?? true) }

        let both = try SimFixtures.run(SampleHouseholds.oak, "home-fire", variants: ["second-exit-blocked"])
        let none = both.events.filter { $0.id.hasPrefix("evt.home-fire.route.none.") }
        #expect(none.count == SampleHouseholds.oak.people.count)
        #expect(none.allSatisfy { $0.templateValues["reason"] != nil && $0.templateValues["reason"] != "unknown" })
        #expect(both.recommendations.first?.actionID == "act.fire.verify-second-exit" || both.recommendations.contains { $0.actionID == "act.fire.verify-second-exit" && $0.tier == .unmetEssentialRequirement })
        // Unsafe fire options are never recommended.
        let d = try #require(r.decisions.first { $0.id == "choice.home-fire.first-move" })
        #expect(d.options.filter(\.isRecommended).map(\.id) == ["get-out"])
    }

    @Test("Tornado: manufactured home, preselected shelter, night alerting, no distant travel during a warning")
    func tornado() throws {
        let pine = try SimFixtures.run(SampleHouseholds.pine, "tornado")
        #expect(pine.events.contains { $0.id == "evt.tornado.manufactured-home" })
        #expect(pine.recommendations.contains { $0.actionID == "act.tornado.sturdy-building-plan" && $0.tier == .unmetEssentialRequirement })
        let w = try #require(pine.decisions.first { $0.id == "choice.tornado.warning" })
        #expect(w.options.first { $0.id == "drive-to-distant-shelter" }?.isRecommended == false)
        #expect(w.options.first { $0.id == "go-to-shelter" }?.isRecommended == false)   // not adequate in a manufactured home

        let oak = try SimFixtures.run(SampleHouseholds.oak, "tornado")
        #expect(oak.events.contains { $0.id == "evt.tornado.shelter-preselected" })
        #expect(oak.routes.isEmpty)   // never routes to a distant shelter

        var h = SampleHouseholds.oak
        h.communications.handsetRuntimeHours = .assumed(0.5, unit: "h")
        h.communications.powerBankCharges = .confirmed(0)
        let night = try SimFixtures.run(h, "tornado", variants: ["night"])
        // Phone is still charged at the warning (grid is up), so the alert arrives by phone.
        #expect(night.events.contains { $0.id == "evt.tornado.night-alert-received" })

        // Unknown handset assumption and no confirmed radio: a night warning may not wake the household.
        h.communications.handsetRuntimeHours = .unknown
        let uncertain = try SimFixtures.run(h, "tornado", variants: ["night"])
        #expect(uncertain.events.contains { $0.id == "evt.tornado.night-alert-uncertain" })
        let radio = try #require(uncertain.recommendations.first { $0.actionID == "act.comms.weather-radio" })
        #expect(radio.tier == .unmetEssentialRequirement)
        let cmp = try SimFixtures.engine.compare(SimFixtures.input(h, "tornado", variants: ["night"]), applying: radio.tryIntervention!)
        #expect(cmp.diff.resolvedRequirements.contains("req.alerts.night"))
    }

    @Test("Flash flood: never a route through water; no-car early leave is blocked without an arrangement")
    func flood() throws {
        let r = try SimFixtures.run(SampleHouseholds.lake, "flash-flood", choices: ["choice.flash-flood.early": "leave-early"])
        #expect(r.events.contains { $0.id == "evt.flash-flood.no-crossing" })
        #expect(r.events.contains { $0.id == "evt.flash-flood.relocation.blocked" && $0.templateValues["reason"] == "noVehicle" })
        let d = try #require(r.decisions.first { $0.id == "choice.flash-flood.warning" })
        #expect(d.options.first { $0.id == "drive-through" }?.isRecommended == false)
        #expect(d.options.first { $0.id == "around-barricade" }?.isRecommended == false)
        #expect(r.routes.isEmpty)
        let oak = try SimFixtures.run(SampleHouseholds.oak, "flash-flood")
        #expect(oak.recommendations.contains { $0.actionID == "act.water.well-test-after-flood" })
    }

    @Test("Each scenario produces distinct events, decisions and results for the same household")
    func scenariosDistinct() throws {
        for h in SampleHouseholds.all {
            var signatures: [String: Set<String>] = [:]
            for s in SimFixtures.scenarioIDs {
                let r = try SimFixtures.run(h, s)
                #expect(!r.decisions.isEmpty)
                let authored = Set(r.events.map(\.titleKey).filter { $0.hasPrefix("scenario.\(s).") })
                #expect(!authored.isEmpty, "\(s) has scenario-specific events")
                signatures[s] = Set(r.events.map(\.titleKey)).union(r.recommendations.map(\.actionID))
            }
            let all = Array(signatures.values)
            for i in all.indices { for j in all.indices where j > i { #expect(all[i] != all[j]) } }
        }
    }

    @Test("Library validation rejects unknown rules and unsafe defaults; dependency evaluation has a hard bound")
    func validationAndBounds() throws {
        let fire = try #require(SimFixtures.library.scenario("home-fire"))
        var bad = fire
        bad.events[0].rule = "rule.invented"
        #expect(throws: ScenarioLoadError.self) { try ScenarioLibrary(scenarios: [bad]) }
        var unsafeDefault = fire
        unsafeDefault.choicePoints[0].defaultOptionID = "fight-fire"
        #expect(throws: ScenarioLoadError.self) { try ScenarioLibrary(scenarios: [unsafeDefault]) }
        #expect(throws: RehearsalError.self) {
            var i = SimFixtures.input(SampleHouseholds.oak, "home-fire")
            i.scenarioVersion = "0.0.1"
            _ = try SimFixtures.engine.run(i)
        }

        // Reverse-ordered chain needs several passes; capping iterations triggers the documented hard error.
        let m = DependencyModel(nodes: [
            DependencyNode(id: "c", requirement: .service("b"), factIDs: [], ruleID: "t"),
            DependencyNode(id: "b", requirement: .service("a"), factIDs: [], ruleID: "t"),
            DependencyNode(id: "a", requirement: .service("svc.grid"), factIDs: [], ruleID: "t"),
        ])
        #expect(throws: DependencyError.self) { _ = try m.evaluate(inputs: ["svc.grid": .operational], backup: [:], maxIterations: 1) }
        #expect(try m.evaluate(inputs: ["svc.grid": .operational], backup: [:])["c"] == .operational)
    }

    @Test("AND/OR algebra: OR keeps a working backup; AND fails on any unavailable input")
    func algebra() {
        #expect(StateAlgebra.or([.unavailable, .operational]) == .operational)
        #expect(StateAlgebra.or([.unavailable, .unknown]) == .unknown)
        #expect(StateAlgebra.and([.operational, .unknown]) == .unknown)
        #expect(StateAlgebra.and([.degraded, .unavailable]) == .unavailable)
    }
}
