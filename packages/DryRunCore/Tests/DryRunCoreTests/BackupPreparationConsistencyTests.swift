import Foundation
import Testing
@testable import DryRunCore

@Suite("Recorded backup and transport prerequisites")
struct BackupPreparationConsistencyTests {
    static func household(kind: BackupPowerKind = .portableBatteryStation) -> HouseholdProfile {
        var h = OutageCardTests.preparedOak
        h.equipment = [PoweredEquipment(id: "device.a", purpose: .oxygenConcentrator, label: "USER-DEVICE", compatibleBackupIDs: ["source"], documentedBackupRuntimeHours: .confirmed(4))]
        h.backupPower = [BackupPowerSource(id: "source", kind: kind, label: "USER-SOURCE", setupConfirmed: .confirmed(true))]
        return h
    }
    static func powerTask(_ h: HouseholdProfile, _ id: String = "device.a") -> Bool {
        BaselinePreparedness.evaluate(household: h, home: nil).contains { $0.id == "prep.medicalBackup|equipment.\(id)" }
    }

    @Test("A checked source cannot close generator or solar prerequisites, or generate a switch instruction")
    func sourcePrerequisitesReachEveryDocument() throws {
        for (kind, expected) in [(BackupPowerKind.portableGenerator, "generatorPlacementUnconfirmed"), (.solarWithBattery, "islandingUnconfirmed"), (.solarGridTiedOnly, "gridTiedSolarNotBackup")] {
            let h = Self.household(kind: kind)
            #expect(MedicalBackupReadiness.assignment(for: h.equipment[0], in: h)?.reason == expected)
            #expect(Self.powerTask(h))
            #expect(OutageCardBuilder.gaps(for: h.equipment[0], in: h).contains(.backupPrerequisitesUnconfirmed))
            for locale in ["en", "es", "vi"] {
                let l = try PlanBuilderTests.localizer(locale)
                let device = try OutageCardTests.card(h, locale: locale)
                #expect(!device.pages.flatMap(\.sections).flatMap(\.lines).contains { $0.key == "card.steps.switchToBackup" })
                let doc = PlanBuilder.build(household: h, home: nil, results: [], localizer: l, resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate,
                    options: .init(familyCardSelection: .init(includeCriticalInformation: true)))
                let reason = l("reason.\(expected)")
                for pageID in ["family-card", "essentials"] {
                    let page = try #require(doc.pages.first { $0.id == pageID })
                    #expect(page.sections.flatMap(\.lines).contains { $0.text.contains(reason) })
                }
                #expect(PlanValidator.validate(doc, household: h).isEmpty)
            }
        }
        var generator = Self.household(kind: .portableGenerator)
        generator.backupPower[0].safeOutdoorPlacementConfirmed = .confirmed(true)
        #expect(!Self.powerTask(generator))
        var solar = Self.household(kind: .solarWithBattery)
        solar.backupPower[0].islandingConfirmed = .confirmed(true)
        #expect(!Self.powerTask(solar))
    }

    @Test("Optional wattage is not fabricated; known limits and a depleted source remain binding")
    func technicalFieldsAreOptionalButRecordedLimitsMatter() throws {
        var h = Self.household()
        let original = h
        #expect(!Self.powerTask(h), "One compatible checked source and documented runtime need no invented W/Wh")
        #expect(h == original)
        h.equipment[0].powerWatts = .confirmed(30)
        #expect(Self.powerTask(h))
        #expect(MedicalBackupReadiness.assignment(for: h.equipment[0], in: h)?.reason == "outputLimitUnknown")
        h.backupPower[0].continuousOutputW = .confirmed(20)
        #expect(Self.powerTask(h))
        #expect(MedicalBackupReadiness.assignment(for: h.equipment[0], in: h)?.reason == "outputLimitReached")
        h.backupPower[0].continuousOutputW = .confirmed(50)
        #expect(!Self.powerTask(h))
        h.backupPower[0].usableEnergyWh = .confirmed(0)
        #expect(Self.powerTask(h))
        #expect(MedicalBackupReadiness.assignment(for: h.equipment[0], in: h)?.reason == "depleted")
        h.backupPower[0].usableEnergyWh = .unknown
        for invalid in [0.0, -1] {
            h.equipment[0].documentedBackupRuntimeHours = .confirmed(invalid)
            #expect(Self.powerTask(h))
            #expect(OutageCardBuilder.gaps(for: h.equipment[0], in: h).contains(.runtimeUnknown))
        }
    }

    @Test("A second shared load cannot fit around an unknown draw, in either deterministic ID order")
    func sharedSourcesDoNotDoubleCountUnknownDraw() throws {
        var h = Self.household()
        h.backupPower[0].continuousOutputW = .confirmed(100)
        h.equipment.append(PoweredEquipment(id: "device.b", purpose: .cpapOrBipap, label: "SECOND", compatibleBackupIDs: ["source"], documentedBackupRuntimeHours: .confirmed(4), powerWatts: .confirmed(20)))
        #expect(!Self.powerTask(h, "device.a"))
        #expect(Self.powerTask(h, "device.b"))
        #expect(MedicalBackupReadiness.assignment(for: h.equipment[1], in: h)?.reason == "sharedDrawUnknown")
        h.equipment[0].powerWatts = .confirmed(20)
        h.equipment[1].powerWatts = .unknown
        let allocation = BackupAllocator().allocate(household: h, gridAvailable: false, energyRemaining: [:])
        #expect(allocation.assignments[Load.equipment("device.b")]?.reason == "sharedDrawUnknown")
        let drain = try #require(allocation.drainWhPerHour["source"] ?? nil)
        #expect(abs(drain - 20 / 0.85) < 1e-8, "A rejected unknown load cannot invalidate the recorded assigned draw")
        h.equipment[1].powerWatts = .confirmed(20)
        #expect(!Self.powerTask(h, "device.a") && !Self.powerTask(h, "device.b"))
        h.backupPower[0].continuousOutputW = .confirmed(30)
        #expect(!Self.powerTask(h, "device.a") && Self.powerTask(h, "device.b"))
    }

    @Test("An alternative usable source can close the task while rejected candidates stay visibly qualified")
    func alternativeSourceIsSelectedByAllocator() throws {
        var h = Self.household(kind: .portableGenerator)
        h.backupPower.append(BackupPowerSource(id: "source.other", kind: .deviceInternalBattery, label: "SECOND-SOURCE", setupConfirmed: .confirmed(true)))
        h.equipment[0].compatibleBackupIDs.append("source.other")
        #expect(!Self.powerTask(h))
        #expect(MedicalBackupReadiness.assignment(for: h.equipment[0], in: h)?.sourceID == "source.other")
        let lines = try OutageCardTests.card(h).pages.flatMap(\.sections).flatMap(\.lines)
        let step = try #require(lines.first { $0.key == "card.steps.switchToBackup" })
        #expect(step.text.contains("SECOND-SOURCE") && !step.text.contains("USER-SOURCE"))
        #expect(!lines.contains { $0.text.contains("tested by the household") || $0.text.contains("tested with this device") })
    }

    @Test("Medicine private-note selection survives cold-only power independence and every selected locale")
    func coldOnlyNotesRemainSelected() throws {
        var h = Self.household()
        h.equipment = [PoweredEquipment(id: "medicine", purpose: .refrigeratedMedication, label: "USER-MEDICINE", carePlanNotes: "EXACT 0.5 mg @08:30 {literal}", storageInstructions: "PROVIDER-STORAGE")]
        for locale in ["en", "es", "vi"] {
            for medicine in [true, false] {
                for notes in [true, false] {
                    let doc = PlanBuilder.build(household: h, home: nil, results: [], localizer: try PlanBuilderTests.localizer(locale), resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate,
                        options: .init(includePrivateNotes: notes, familyCardSelection: .init(includeMedication: medicine)))
                    let noteLines = doc.pages.flatMap(\.sections).flatMap(\.lines).filter { $0.key == "private.carePlanNotes" }
                    #expect(noteLines.map(\.text) == (notes ? ["EXACT 0.5 mg @08:30 {literal}"] : []))
                    #expect(!doc.pages.flatMap(\.sections).flatMap(\.lines).contains { $0.key == "plan.equipment.line" })
                }
            }
        }
    }

    @Test("No-layout transport preparation requires recorded wheelchair access, including agreed rides")
    func transportAccessIsNotInferredFromOwnershipOrAgreement() {
        var h = Self.household()
        h.people = [Person(id: "wheelchair", alias: "USER", ageBand: .unknown, needs: [.usesWheelchair])]
        h.transport.vehicles = [Vehicle(id: "car", seats: 4, wheelchairAccessible: .confirmed(false))]
        h.transport.alternatives = []
        func task(_ value: HouseholdProfile) -> Bool { BaselinePreparedness.evaluate(household: value, home: nil).contains { $0.actionID == "prep.transport" } }
        #expect(task(h))
        h.transport.vehicles[0].wheelchairAccessible = .unknown
        #expect(task(h))
        h.transport.alternatives = [TransportAlternative(id: "ride", kind: .friendOrFamily, agreed: .confirmed(true))]
        #expect(task(h))
        h.transport.alternatives[0].wheelchairAccessible = .confirmed(false)
        #expect(task(h))
        h.transport.alternatives[0].wheelchairAccessible = .confirmed(true)
        #expect(!task(h))
        h.transport.alternatives[0].agreed = .confirmed(false)
        #expect(task(h))
        h.transport.vehicles[0].wheelchairAccessible = .confirmed(true)
        #expect(!task(h))
        h.people[0].needs = []
        h.transport.vehicles[0].wheelchairAccessible = .confirmed(false)
        #expect(!task(h), "An irrelevant access field cannot block ordinary transport planning")
    }
}
