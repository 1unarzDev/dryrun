import Foundation
import Testing
@testable import DryRunCore

@Suite("Selected family export transaction")
struct FamilyPlanExportRequestTests {
    private func plan(selection: FamilyCardSelection = .init(), notes: Bool = false) throws -> PlanDocument {
        var household = SampleHouseholds.oak
        household.people[0].emergencyInformation = .init(criticalConditions: "CRITICAL-PRIVATE-CANARY")
        household.equipment[0].carePlanNotes = "NOTES-PRIVATE-CANARY"
        return PlanBuilder.build(household: household, home: nil, results: [], localizer: try PlanBuilderTests.localizer("en"),
            resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate,
            options: .init(includePrivateNotes: notes, familyCardSelection: selection))
    }
    private func card(_ document: PlanDocument) -> PlanDocument {
        var card = document; card.pages.removeAll { $0.id != "family-card" }; card.visualSnapshot = nil
        return card
    }

    @Test func failedRequestedGenerationCannotExportEvenWhenACardIsAvailable() throws {
        let request = FamilyPlanExportRequest(includePlan: true, includeCard: true, includePrivateNotes: false, selection: .init())
        #expect(request.document(generatedPlan: nil, card: card(try plan())) == nil)
        #expect(request.document(generatedPlan: try plan(), card: nil) == nil)
    }

    @Test func currentSelectionsApplyToEveryPageAndCardIsIncludedExactlyOnce() throws {
        let request = FamilyPlanExportRequest(includePlan: true, includeCard: true, includePrivateNotes: false, selection: .init())
        let fresh = try plan(selection: request.selection, notes: request.includePrivateNotes)
        let document = try #require(request.document(generatedPlan: fresh, card: card(fresh)))
        #expect(document.pages.first?.id == "family-card")
        #expect(document.pages.filter { $0.id == "family-card" }.count == 1)
        let text = document.pages.flatMap(\.sections).flatMap(\.lines).map(\.text).joined(separator: "\n")
        #expect(!text.contains("CRITICAL-PRIVATE-CANARY") && !text.contains("NOTES-PRIVATE-CANARY"))
        let planOnly = FamilyPlanExportRequest(includePlan: true, includeCard: false, includePrivateNotes: false, selection: .init())
        #expect(planOnly.document(generatedPlan: fresh, card: nil)?.pages.contains { $0.id == "family-card" } == false)
    }

    @Test func cardOnlyExportCannotInheritAnotherPlansPrivatePagesOrGeometry() throws {
        let old = try plan(selection: .init(includeCriticalInformation: true), notes: true)
        let request = FamilyPlanExportRequest(includePlan: false, includeCard: true, includePrivateNotes: false, selection: .init())
        let document = try #require(request.document(generatedPlan: old, card: card(try plan())))
        #expect(document.visualSnapshot == nil)
        #expect(document.pages.map(\.id) == ["family-card"])
        #expect(!document.pages.flatMap(\.sections).flatMap(\.lines).contains { $0.text.contains("PRIVATE-CANARY") })
    }

    @Test func oversizedInstructionsFollowTheMainCardWithoutRewritingOrHidingTheirSelection() throws {
        var h = SampleHouseholds.oak
        let note = String(repeating: "FICTIONAL RECORDED WORDS; ", count: 400) + "END-OF-INSTRUCTIONS"
        h.people[0].emergencyInformation = .init(responderInstructions: note)
        h.contacts = [.init(id: "contact", role: .outOfAreaContact, alias: "CONTACT-CANARY", phone: "+84 28 3822 0000")]
        let places = [SavedPlace(homeID: h.stableHomeID, purpose: .outsideMeetingPoint, label: "NEAR-CANARY"),
                      SavedPlace(homeID: h.stableHomeID, purpose: .backupMeetingPlace, label: "BACKUP-CANARY")]
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            let page = FamilyEmergencyCardBuilder.page(household: h, savedPlaces: places, localizer: l, selection: .init(includeResponderInstructions: true))
            let main = page.sections.filter { $0.id != "instruction-continuation" }.flatMap(\.lines).map(\.text).joined(separator: "\n")
            #expect(main.contains("CONTACT-CANARY") && main.contains("NEAR-CANARY") && main.contains("BACKUP-CANARY"))
            #expect(main.contains(l("family.instructionsContinued")) && !main.contains(note))
            let continuation = try #require(page.sections.last)
            #expect(continuation.id == "instruction-continuation")
            #expect(continuation.lines.first?.text == h.people[0].localizedLabel(l) + ": " + note)
            let omitted = FamilyEmergencyCardBuilder.page(household: h, savedPlaces: places, localizer: l)
            #expect(!omitted.sections.contains { $0.id == "instruction-continuation" })
            #expect(!omitted.sections.flatMap(\.lines).contains { $0.text.contains("END-OF-INSTRUCTIONS") })
        }
    }

    @Test func placeOrderDoesNotInvalidateAPlanButAChangedMeetupDoes() throws {
        let household = SampleHouseholds.oak
        let z = SavedPlace(id: "z-near", homeID: household.stableHomeID, purpose: .outsideMeetingPoint, label: "Fictional gate")
        let a = SavedPlace(id: "a-backup", homeID: household.stableHomeID, purpose: .backupMeetingPlace, label: "Fictional library")
        let document = PlanBuilder.build(household: household, home: nil, savedPlaces: [z, a], results: [],
            localizer: try PlanBuilderTests.localizer("en"), resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate)
        #expect(document.visualSnapshot?.savedPlaces.map(\.id) == [a.id, z.id])
        #expect(!document.isStale(household: household, home: nil, contentVersion: "test", savedPlaces: [z, a]))
        #expect(!document.isStale(household: household, home: nil, contentVersion: "test", savedPlaces: [a, z]))
        var edited = a; edited.findingInstructions = "New entrance"
        #expect(document.isStale(household: household, home: nil, contentVersion: "test", savedPlaces: [z, edited]))
    }

    @Test func droppedPinMeetupsKeepTheirLocationAsTextInACardWithoutMaps() throws {
        let household = SampleHouseholds.oak
        let pin = SavedPlace(homeID: household.stableHomeID, purpose: .outsideMeetingPoint, label: "Fictional driveway",
            coordinate: GeographicCoordinate(latitude: 32.123456, longitude: -98.654321))
        for locale in ["en", "es", "vi"] {
            let page = FamilyEmergencyCardBuilder.page(household: household, savedPlaces: [pin], localizer: try PlanBuilderTests.localizer(locale))
            let section = try #require(page.sections.first { $0.id == "outsideMeetingPoint" })
            let text = section.lines.map(\.text).joined(separator: "\n")
            #expect(text.contains("Fictional driveway"))
            #expect(text.contains("32.123456, -98.654321"))
            #expect(!text.contains("map.pin"))
        }
    }

    @Test func outOfAreaContactKeepsItsRoleAndInternationalPhoneWithoutAProseRelationship() throws {
        var household = SampleHouseholds.oak
        household.contacts = [HouseholdContact(id: "away", role: .outOfAreaContact, alias: "Fictional Linh", phone: "+84 28 3822 0000")]
        for locale in ["en", "es", "vi"] {
            let localizer = try PlanBuilderTests.localizer(locale)
            let page = FamilyEmergencyCardBuilder.page(household: household, localizer: localizer)
            let text = page.sections.first { $0.id == "contacts" }!.lines.map(\.text).joined(separator: "\n")
            #expect(text.contains("Fictional Linh"))
            #expect(text.contains("+84 28 3822 0000"))
            #expect(text.contains(localizer("ui.contact.role.outOfAreaContact")))
            #expect(!text.contains("ui.contact.role"))
            let omitted = FamilyEmergencyCardBuilder.page(household: household, localizer: localizer, selection: .init(includeContacts: false))
            #expect(!omitted.sections.flatMap(\.lines).contains { $0.text.contains("Fictional Linh") || $0.text.contains("+84 28") })
        }
    }

    @Test func subjectSupplyFactsReachTheNoLayoutCardOnlyUnderTheirOwnSelections() throws {
        var household = SampleHouseholds.oak
        var firstPerson = household.people[0]
        firstPerson.id = "resident.one"; firstPerson.alias = "Fictional An"
        var secondPerson = firstPerson
        secondPerson.id = "resident.two"; secondPerson.alias = "Fictional Bo"
        household.people = [firstPerson, secondPerson]
        var firstDevice = household.equipment[0]
        firstDevice.id = "device.one"; firstDevice.personID = firstPerson.id; firstDevice.label = "An device"
        var secondDevice = firstDevice
        secondDevice.id = "device.two"; secondDevice.personID = secondPerson.id; secondDevice.label = "Bo device"
        var medicine = firstDevice
        medicine.id = "medicine.unassigned"; medicine.personID = nil
        medicine.purpose = .refrigeratedMedication; medicine.label = "Recorded medicine"
        household.equipment = [firstDevice, secondDevice, medicine]
        household.preparedness = .init(items: [
            "medication.person.resident.one": .init(available: .confirmed(true), location: "AN-MEDICINE-LOCATION", notes: "PRIVATE-NOTES-CANARY"),
            "medication.person.resident.two": .init(available: .confirmed(false), location: "BO-MEDICINE-LOCATION"),
            "medication.equipment.medicine.unassigned": .init(location: "UNASSIGNED-MEDICINE-LOCATION"),
            "equipmentSupplies.device.one": .init(available: .confirmed(true), location: "AN-DEVICE-LOCATION"),
            "equipmentSupplies.device.two": .init(available: .confirmed(false), location: "BO-DEVICE-LOCATION"),
            "medication.person.resident": .init(available: .confirmed(true), location: "WRONG-SUBJECT-CANARY")
        ])
        for locale in ["en", "es", "vi"] {
            let localizer = try PlanBuilderTests.localizer(locale)
            for medication in [false, true] {
                for critical in [false, true] {
                    let document = PlanBuilder.build(household: household, home: nil, results: [], localizer: localizer,
                        resources: [], contentVersion: "test", generatedAt: LeadTestSupport.fixedDate,
                        options: .init(includePrivateNotes: false, familyCardSelection: .init(includeCriticalInformation: critical, includeMedication: medication)))
                    let page = try #require(document.pages.first { $0.id == "family-card" })
                    let lines = page.sections.first { $0.id == "continuity" }?.lines.map(\.text) ?? []
                    let text = lines.joined(separator: "\n")
                    for location in ["AN-MEDICINE-LOCATION", "BO-MEDICINE-LOCATION", "UNASSIGNED-MEDICINE-LOCATION"] {
                        #expect(text.contains(location) == medication)
                    }
                    for location in ["AN-DEVICE-LOCATION", "BO-DEVICE-LOCATION"] {
                        #expect(text.contains(location) == critical)
                    }
                    #expect(!text.contains("PRIVATE-NOTES-CANARY") && !text.contains("WRONG-SUBJECT-CANARY"))
                    if medication {
                        #expect(lines.contains { $0.contains("Fictional An") && $0.contains("AN-MEDICINE-LOCATION") && $0.contains(localizer("ui.yes")) })
                        #expect(lines.contains { $0.contains("Fictional Bo") && $0.contains("BO-MEDICINE-LOCATION") && $0.contains(localizer("ui.no")) })
                        #expect(lines.contains { $0.contains("Recorded medicine") && $0.contains("UNASSIGNED-MEDICINE-LOCATION") && $0.contains(localizer("ui.notSure")) })
                    }
                    if critical {
                        #expect(lines.contains { $0.contains("Fictional An") && $0.contains("An device") && $0.contains("AN-DEVICE-LOCATION") && $0.contains(localizer("ui.yes")) })
                        #expect(lines.contains { $0.contains("Fictional Bo") && $0.contains("Bo device") && $0.contains("BO-DEVICE-LOCATION") && $0.contains(localizer("ui.no")) })
                    }
                    #expect(!text.contains("prep.medication.title") && !text.contains("prep.equipmentSupplies.title"))
                }
            }
        }
    }

    @Test func cardUsesRecordedSupplyOwnershipAndWaterQuantityWithoutCertifyingContradictions() throws {
        var household = SampleHouseholds.oak
        household.supplies.firstAidKit = .confirmed(true)
        household.supplies.shelfStableFoodDays = .confirmed(3)
        household.supplies.flashlights = .confirmed(2)
        household.supplies.storedWaterGallons = .confirmed(4)
        household.preparedness = .init(items: [
            "firstAid": .init(location: "FIRST-AID-CABINET"),
            "food": .init(location: "FOOD-PANTRY"),
            "flashlight": .init(location: "LIGHT-DRAWER"),
            "water": .init(location: "WATER-SHELF")
        ])
        for locale in ["en", "es", "vi"] {
            let localizer = try PlanBuilderTests.localizer(locale)
            for country in ["US", "VN"] {
                household.privateLocation = .init(countryCode: country)
                let page = FamilyEmergencyCardBuilder.page(household: household, localizer: localizer)
                let lines = try #require(page.sections.first { $0.id == "continuity" }).lines.map(\.text)
                for location in ["FIRST-AID-CABINET", "FOOD-PANTRY", "LIGHT-DRAWER", "WATER-SHELF"] {
                    #expect(lines.contains { $0.contains(location) && $0.contains(localizer("family.haveItem") + ": " + localizer("ui.yes")) })
                }
                let water = try #require(lines.first { $0.contains("WATER-SHELF") })
                let quantity = country == "US" ? "4" : (locale == "en" ? "15.1" : "15,1")
                #expect(water.contains(localizer(country == "US" ? "ui.setup.water.gallons" : "family.waterLitres") + ": " + quantity))
                #expect(!BaselinePreparedness.evaluate(household: household).contains { ["prep.firstAid", "prep.food", "prep.flashlight"].contains($0.actionID) })
            }
            var contradiction = household
            contradiction.preparedness?.items["firstAid"]?.available = .confirmed(false)
            contradiction.supplies.shelfStableFoodDays = .confirmed(0)
            contradiction.preparedness?.items["food"]?.available = .confirmed(true)
            let contradicted = FamilyEmergencyCardBuilder.page(household: contradiction, localizer: localizer)
            let lines = try #require(contradicted.sections.first { $0.id == "continuity" }).lines.map(\.text)
            for location in ["FIRST-AID-CABINET", "FOOD-PANTRY"] {
                #expect(lines.contains { $0.contains(location) && $0.contains(localizer("family.haveItem") + ": " + localizer("ui.no")) })
            }
            let remaining = BaselinePreparedness.evaluate(household: contradiction)
            #expect(remaining.contains { $0.actionID == "prep.firstAid" })
            #expect(remaining.contains { $0.actionID == "prep.food" })
        }
    }
}

@Suite("Family card layout parts")
struct FamilyCardLayoutPartsTests {
    /// The renderer may lay parts out as a table, so every part must also be in the line's full text, and missing
    /// facts must be flagged rather than left blank.
    @Test func partsNeverAddTextAndMissingFactsAreFlagged() throws {
        var household = SampleHouseholds.oak
        household.people[0].emergencyInformation = .init(severeAllergies: "PEANUT-CANARY")
        household.contacts.append(HouseholdContact(id: "c-nophone", role: .outOfAreaContact, alias: "No phone yet", relationship: "Cousin"))
        let page = FamilyEmergencyCardBuilder.page(household: household, localizer: try PlanBuilderTests.localizer("en"),
                                                   selection: .init(includeCriticalInformation: true))
        let lines = page.sections.flatMap(\.lines)
        for line in lines {
            guard let parts = line.parts else { continue }
            let pieces = [parts.subject, parts.detail, parts.phone].compactMap { $0 } + parts.fields.flatMap { [$0.label, $0.value].compactMap { $0 } }
            for piece in pieces { #expect(line.text.contains(piece), "\(piece) is not in \(line.text)") }
        }
        let critical = try #require(page.sections.first { $0.id == "critical" })
        let first = try #require(critical.lines.first?.parts)
        #expect(first.fields.contains { $0.value == "PEANUT-CANARY" && $0.label != nil } && !first.isMissing)
        #expect(critical.lines.dropFirst().contains { $0.parts?.isMissing == true }, "People with nothing selected read as not provided")
        let contacts = try #require(page.sections.first { $0.id == "contacts" })
        let noPhone = try #require(contacts.lines.first { $0.parts?.subject == "No phone yet" }?.parts)
        #expect(noPhone.isMissing && noPhone.phone == nil && noPhone.detail?.contains("Cousin") == true)
        // No backup meetup saved: the slot is explicitly missing, never omitted.
        let backup = try #require(page.sections.first { $0.id == "backupMeetingPlace" })
        #expect(backup.lines.first?.parts?.isMissing == true)
    }
}
