import Foundation
import Testing
@testable import DryRunCore

@Suite("Factual preparation progress")
struct RecordedPreparationTests {
    @Test("Contact and meetup records close their tasks and stay reviewable across reload without a layout")
    func recordsSurviveAndReopen() throws {
        var h = SampleHouseholds.oak
        h.contacts = []; h.equipment = []; h.preparedness = nil
        let now = LeadTestSupport.fixedDate
        let place = SavedPlace(homeID: h.stableHomeID, purpose: .outsideMeetingPoint, label: "Family gate")
        let unrelated = SavedPlace(homeID: "some-other-home", purpose: .backupMeetingPlace, label: "Other family")
        func summary(_ household: HouseholdProfile) -> NextStepsSummary {
            NextSteps.summarize([], household: household, home: nil, savedPlaces: [place, unrelated], referenceDate: now)
        }
        #expect(summary(h).toDo.contains { $0.id == "prep.contact" })
        h.contacts.append(HouseholdContact(id: "aunt", role: .outOfAreaContact, alias: "Aunt", phone: "+33 1 23 45 67 89"))
        let restored = try JSONDecoder().decode(HouseholdProfile.self, from: JSONEncoder().encode(h))
        let recorded = summary(restored).recorded.map(\.id)
        #expect(recorded.contains("prep.contact") && recorded.contains("prep.outOfAreaContact") && recorded.contains("prep.nearMeetup"))
        #expect(!recorded.contains("prep.layout") && !recorded.contains("prep.backupMeetup"))
        #expect(!summary(restored).toDo.contains { ["prep.contact", "prep.outOfAreaContact", "prep.nearMeetup"].contains($0.id) })
        h.contacts[0].phone = ""
        #expect(summary(h).toDo.contains { $0.id == "prep.contact" })
        #expect(!summary(h).recorded.contains { $0.id == "prep.contact" })
        #expect(summary(h).recorded.contains { $0.id == "prep.nearMeetup" })
        #expect(h.completedPreparations.isEmpty)
    }

    @Test("Alarm ownership, coverage, location, and an explicit current functional check remain separate")
    func physicalCheckCanReopen() {
        var h = SampleHouseholds.oak; h.completedPreparations = []
        let now = LeadTestSupport.fixedDate
        h.preparedness = PreparednessRecord(items: ["smokeAlarms": PreparationFact(available: .confirmed(true), location: "Hall and bedrooms", coverageReviewed: .confirmed(true))])
        func recorded() -> Bool { BaselinePreparedness.recorded(household: h, referenceDate: now).contains { $0.id == "prep.smokeAlarms" } }
        #expect(!recorded())
        h.preparedness?.items["smokeAlarms"]?.checkedAt = now
        #expect(recorded())
        h.preparedness?.items["smokeAlarms"]?.checkedAt = now.addingTimeInterval(-31 * 86_400)
        #expect(!recorded())
        #expect(BaselinePreparedness.evaluate(household: h, referenceDate: now).first { $0.id == "prep.smokeAlarms" }?.whyKey == "prep.recheck.why")
        h.preparedness?.items["smokeAlarms"]?.checkedAt = nil
        #expect(!recorded())
        #expect(h.preparedness?.items["smokeAlarms"]?.available.confirmedValue == true)
    }

    @Test("Two people's medicine preparations close independently and do not fabricate generic completion records")
    func subjectSpecificProgress() throws {
        var h = SampleHouseholds.oak; h.equipment = []; h.preparedness = .init(); h.completedPreparations = []
        h.people = Array(h.people.prefix(2))
        for i in h.people.indices { h.people[i].emergencyInformation = .init(essentialMedication: "Recorded provider instructions") }
        let first = h.people[0].id, second = h.people[1].id
        h.preparedness?.items["medication.person.\(first)"] = PreparationFact(available: .confirmed(true), location: "First person's bag")
        let summary = NextSteps.summarize([], household: h)
        #expect(summary.recorded.contains { $0.id == "prep.medication|person.\(first)" })
        #expect(summary.toDo.contains { $0.id == "prep.medication|person.\(second)" })
        #expect(!summary.recorded.contains { $0.id == "prep.medication|person.\(second)" })
        let restored = try JSONDecoder().decode(HouseholdProfile.self, from: JSONEncoder().encode(h))
        #expect(NextSteps.summarize([], household: restored).recorded == summary.recorded)
    }
}
