import Foundation
import Testing
@testable import DryRunCore

@Suite("Alarm records across rehearsal and preparation")
struct AlarmReadinessIntegrationTests {
    private let now = LeadTestSupport.fixedDate
    private var complete: PreparationFact {
        .init(available: .confirmed(true), location: "Hall and bedrooms", checkedAt: now, coverageReviewed: .confirmed(true))
    }

    private func fire(_ household: HouseholdProfile, home: HomeModel?) throws -> RehearsalResult {
        var input = SimFixtures.input(household, "home-fire")
        input.home = home
        return try SimFixtures.engine.run(input)
    }

    @Test("Verified markers cannot substitute for presence, location, coverage or a functional check")
    func markersDoNotCertifyChecks() throws {
        var home = SampleHomes.ranch
        home.annotations.append(Annotation(id: "reviewed-alarm", kind: .smokeAlarm, label: "Hall alarm", verification: .verified))
        var h = SampleHouseholds.oak
        var absent = complete; absent.available = .confirmed(false)
        var unknown = complete; unknown.available = .unknown
        var missingLocation = complete; missingLocation.location = " \n "
        var missingCoverage = complete; missingCoverage.coverageReviewed = .unknown
        var inadequateCoverage = complete; inadequateCoverage.coverageReviewed = .confirmed(false)
        var missingCheck = complete; missingCheck.checkedAt = nil
        for fact in [PreparationFact(), absent, unknown, missingLocation, missingCoverage, inadequateCoverage, missingCheck] {
            h.preparedness = .init(items: ["smokeAlarms": fact])
            let result = try fire(h, home: home)
            #expect(!BaselinePreparedness.hasRecordedAlarmReadiness("smokeAlarms", household: h))
            #expect(result.unknowns.contains("home.smokeAlarms"))
            #expect(result.recommendations.contains { $0.actionID == "act.fire.smoke-alarms" })
            let summary = NextSteps.summarize([result], household: h, home: home, referenceDate: now)
            let tasks = summary.toDo.filter { ["prep.smokeAlarms", "act.fire.smoke-alarms"].contains($0.recommendation.actionID) }
            #expect(tasks.count == 1 && tasks.first?.id == "prep.smokeAlarms")
            #expect(!summary.recorded.contains { $0.id == "prep.smokeAlarms" })
            if fact.available.confirmedValue == false || fact.coverageReviewed?.confirmedValue == false {
                #expect(tasks.first?.recommendation.tier == .unmetEssentialRequirement)
            }
        }
    }

    @Test("Complete alarm records close the real engine gap without a marker or home layout and survive reload")
    func recordsCloseEngineGap() throws {
        var h = SampleHouseholds.oak
        h.preparedness = .init(items: ["smokeAlarms": complete, "coAlarms": complete])
        h = try JSONDecoder().decode(HouseholdProfile.self, from: JSONEncoder().encode(h))
        var home = SampleHomes.ranch
        home.annotations.removeAll { $0.kind == .smokeAlarm }
        for layout: HomeModel? in [home, nil] {
            let result = try fire(h, home: layout)
            #expect(result == (try fire(h, home: layout)))
            #expect(!result.unknowns.contains("home.smokeAlarms"))
            #expect(!result.recommendations.contains { $0.actionID == "act.fire.smoke-alarms" })
            let summary = NextSteps.summarize([result], household: h, home: layout, referenceDate: now)
            #expect(!summary.toDo.contains { ["prep.smokeAlarms", "prep.coAlarms", "act.fire.smoke-alarms"].contains($0.recommendation.actionID) })
            #expect(summary.recorded.contains { $0.id == "prep.smokeAlarms" })
            #expect(summary.recorded.contains { $0.id == "prep.coAlarms" })
        }
    }

    @Test("Only the injected baseline date reopens alarm maintenance; the exercise remains identical")
    func maintenanceIsNotSimulationTime() throws {
        var h = SampleHouseholds.oak
        h.preparedness = .init(items: ["smokeAlarms": complete, "coAlarms": complete])
        let result = try fire(h, home: nil)
        let later = now.addingTimeInterval(31 * 86_400)
        let summary = NextSteps.summarize([result], household: h, referenceDate: later)
        for id in ["smokeAlarms", "coAlarms"] {
            #expect(BaselinePreparedness.hasRecordedAlarmReadiness(id, household: h))
            #expect(summary.toDo.contains { $0.id == "prep.\(id)" && $0.recommendation.tier == .general && $0.recommendation.whyKey == "prep.recheck.why" })
            #expect(!summary.recorded.contains { $0.id == "prep.\(id)" })
        }
        #expect(!summary.toDo.contains { $0.recommendation.actionID == "act.fire.smoke-alarms" })
        #expect(result == (try fire(h, home: nil)))
    }

    @Test("Alarm review instructions are complete in each supported language")
    func localizedWording() throws {
        for locale in ["en", "es", "vi"] {
            let localizer = try PlanBuilderTests.localizer(locale)
            for key in ["action.act.fire.smoke-alarms.title", "action.act.fire.smoke-alarms.why"] {
                let text = localizer.text(key)
                #expect(!text.isMissing && !text.isFallback && text.unfilledPlaceholders.isEmpty)
            }
        }
    }
}
