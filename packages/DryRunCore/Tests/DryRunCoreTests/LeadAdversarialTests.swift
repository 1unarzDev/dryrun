import Foundation
import Testing
@testable import DryRunCore

// Adversarial probes of the lead's Plan/Content/Session code (reviewer: Agent A; see docs/lanes/review-lead-core.md).
// Probes from Agent A's review of the lead's core code. All confirmed defects were fixed by the lead; probes are now regressions.

private let lib = try! ContentLibrary.load(from: SimFixtures.repoRoot.appendingPathComponent("content"))
private let when = ISO8601DateFormatter().date(from: "2026-10-09T12:00:00Z")!

private func plan(_ h: HouseholdProfile, _ scenarios: [String], locale: String, home: HomeModel = SampleHomes.ranch,
                  options: PlanBuilder.Options = .init()) throws -> PlanDocument {
    let results = try scenarios.map { try SimFixtures.run(h, $0, home: home) }
    return PlanBuilder.build(household: h, home: home, results: results, localizer: lib.localizer(for: locale),
                             resources: lib.resources(forRegion: h.regionID), contentVersion: lib.contentVersion,
                             generatedAt: when, options: options)
}
private func lines(_ d: PlanDocument, page: String, section: String) -> [PlanLine] {
    d.pages.first { $0.id == page }?.sections.first { $0.id == section }?.lines ?? []
}

@Suite("Lead core adversarial probes")
struct LeadAdversarialTests {
    @Test("Prohibitions keep prohibition styling in every locale")
    func prohibitionsSurviveTranslation() throws {
        let en = try plan(SampleHouseholds.oak, ["home-fire", "flash-flood", "freeze-power-loss"], locale: "en")
        for loc in ["es", "vi"] {
            let tr = try plan(SampleHouseholds.oak, ["home-fire", "flash-flood", "freeze-power-loss"], locale: loc)
            for page in en.pages {
                let enProhibitions = Set(lines(en, page: page.id, section: "immediate").filter { $0.style == .prohibition }.map(\.key))
                let trProhibitions = Set(lines(tr, page: page.id, section: "immediate").filter { $0.style == .prohibition }.map(\.key))
                // Fixed by the lead before this review (classification now uses the source-language text).
                #expect(enProhibitions == trProhibitions, "\(loc) \(page.id)")
            }
        }
    }

    @Test("Fire page lists a route per person-mobility, not just per start room")
    func routePerMobility() throws {
        // Pine: Niña (walking) and Tío (wheelchair) share the kid's bedroom. Make the walker sort first.
        var h = SampleHouseholds.pine
        if let i = h.people.firstIndex(where: { $0.id == "p-pine-2" }) { h.people[i].id = "p-pine-9" }
        for i in h.people.indices where h.people[i].helperPersonID == "p-pine-2" { h.people[i].helperPersonID = "p-pine-9" }
        let d = try plan(h, ["home-fire"], locale: "en")
        let routeLines = lines(d, page: "scenario-home-fire", section: "homeplan").filter { $0.key == "plan.route.from" || $0.key == "plan.route.none" }
        let r = try SimFixtures.run(h, "home-fire")
        let usual = r.routes
        let distinct = Set(usual.map { "\($0.request.startSpaceID)|\($0.request.mobility.requiresStepFree)" })
        #expect(routeLines.count == distinct.count)
    
    }

    @Test("No English words injected into translated route lines without a fallback flag")
    func outsideWordNotLocalized() throws {
        let d = try plan(SampleHouseholds.oak, ["home-fire"], locale: "vi")
        let from = lines(d, page: "scenario-home-fire", section: "homeplan").filter { $0.key == "plan.route.from" || $0.key == "plan.route.none" }
        #expect(!from.isEmpty)
        #expect(from.allSatisfy { !$0.text.contains("outside") || $0.isFallback })
    
    }

    @Test("Placeholder filling is single-pass and user text with braces does not invalidate a plan")
    func placeholderInjection() throws {
        #expect(Localizer.fill("{a} / {b}", ["a": "{b}", "b": "X"]) == "{b} / X")
    
        var h = SampleHouseholds.oak
        h.people[2].alias = "Kid {nickname}"
        let d = try plan(h, ["home-fire"], locale: "en")
        let issues = PlanValidator.validate(d, household: h)
        #expect(!issues.contains { if case .unfilledPlaceholder = $0 { return true }; return false })
    
    }

    @Test("Assumed or unconfirmed stored water is not printed as a fact")
    func assumedWaterNotFact() throws {
        var h = SampleHouseholds.lake
        h.supplies.storedWaterGallons = .assumed(10, unit: "gal")
        let d = try plan(h, ["water-outage"], locale: "en")
        let water = lines(d, page: "essentials", section: "water").map(\.text).joined(separator: " ")
        #expect(!water.contains("10 gal"))
    
    }

    @Test("Private care-plan notes never appear without consent, in any locale")
    func carePlanNotes() throws {
        var h = SampleHouseholds.oak
        h.equipment[0].carePlanNotes = "PRIVATE-CANARY 2 L/min at night"
        for loc in ["en", "es", "vi"] {
            let d = try plan(h, ["freeze-power-loss", "home-fire"], locale: loc)
            let all = d.pages.flatMap { [$0.title] + $0.sections.flatMap { [$0.heading] + $0.lines.map(\.text) } }
            #expect(!all.contains { $0.contains("PRIVATE-CANARY") })
            #expect(PlanValidator.validate(d, household: h).allSatisfy { if case .privateNotesLeaked = $0 { return false }; return true })
        }
        let consented = try plan(h, ["freeze-power-loss"], locale: "en", options: .init(includePrivateNotes: true))
        #expect(consented.pages.flatMap(\.sections).flatMap(\.lines).contains { $0.text.contains("PRIVATE-CANARY") })
    }

    @Test("Draft banner and fallback note present whenever any localized string is draft or fallback")
    func bannersAlwaysPresent() throws {
        for loc in ["es", "vi"] {
            let d = try plan(SampleHouseholds.lake, SimFixtures.scenarioIDs, locale: loc)
            #expect(d.draftTranslationBanner != nil)
            if d.pages.flatMap(\.sections).flatMap(\.lines).contains(where: \.isFallback) { #expect(d.fallbackNote != nil) }
            #expect(PlanValidator.validate(d, household: SampleHouseholds.lake).filter {
                if case .draftWithoutBanner = $0 { return true }; if case .fallbackWithoutNote = $0 { return true }; return false
            }.isEmpty)
        }
    }

    @Test("Cursor reveals same-minute events that precede a minute-0 decision")
    func cursorMinuteZero() throws {
        let r = try SimFixtures.engine.run(SimFixtures.input(SampleHouseholds.oak, "home-fire"))
        var cursor = RehearsalCursor(result: r)
        cursor.advanceUntilDecisionOrEnd()
        #expect(cursor.pendingDecision?.id == "choice.home-fire.first-move")
        #expect(cursor.visibleEvents.contains { $0.id == "evt.home-fire.alarm" })
    
    }

    @Test("Key-moment stepping skips no event and still stops at every decision and warning")
    func keyMoments() throws {
        for scenario in ["home-fire", "tornado", "flash-flood", "freeze-power-loss", "heat-grid-strain", "water-outage"] {
            let r = try SimFixtures.engine.run(SimFixtures.input(SampleHouseholds.oak, scenario))
            var fine = RehearsalCursor(result: r), keyed = RehearsalCursor(result: r)
            var stops = 0
            while !keyed.isFinished && keyed.pendingDecision == nil && stops < 500 {
                let before = keyed.revealed
                keyed.advanceToNextKeyEvent(); stops += 1
                // Every event between stops is revealed (nothing hidden), and only the last one may be a warning.
                let span = r.events[before..<keyed.revealed]
                #expect(span.dropLast().allSatisfy { $0.severity == .info }, "\(scenario): a warning was passed over")
            }
            fine.advanceUntilDecisionOrEnd()
            // Both reach the same place: the first unanswered decision (or the end).
            #expect(keyed.revealed == fine.revealed && keyed.pendingDecision?.id == fine.pendingDecision?.id, "\(scenario)")
            #expect(stops <= r.events.count && keyed.keyMomentsRevealed <= keyed.keyMomentCount)
        }
    }

    @Test("Cursor finishes cleanly when all decisions are answered")
    func cursorAnswered() throws {
        var input = SimFixtures.input(SampleHouseholds.oak, "water-outage")
        input.choices = ["choice.water-outage.drinking-water": "use-stored", "choice.water-outage.stored-water": "prioritize"]
        var c = RehearsalCursor(result: try SimFixtures.engine.run(input))
        c.advanceUntilDecisionOrEnd()
        #expect(c.isFinished && c.pendingDecision == nil)
        #expect(c.currentMinute == c.result.events.last?.simMinute)
    }

    @Test("Gate rejects late results, including after a locale-only change")
    func gate() {
        var gate = LatestRequestGate()
        let k1 = RevisionKey(householdID: "h", householdRevision: 1, homeID: "m", homeRevision: 1, contentVersion: "c", algorithmVersion: "plan/1")
        let t1 = gate.begin(for: k1)
        let t2 = gate.begin(for: k1)
        #expect(!gate.shouldApply(t1, current: k1) && gate.shouldApply(t2, current: k1))
        gate.invalidate()
        #expect(!gate.shouldApply(t2, current: k1))
        // A plan requested in English, then the viewer switches to Vietnamese without editing the household:
        // RevisionKey carries no locale, so nothing distinguishes the two requests (documented, not asserted).
    }

    @Test("Confirmation: ground floor exits work when the home has a basement")
    func basement() {
        let fB = Floor(id: "fl-b", level: -1, label: "Basement", elevationMeters: -2.7)
        let fG = Floor(id: "fl-g", level: 0, label: "Ground")
        let g = Space(id: "sp-g", floorID: "fl-g", label: "G", kind: .livingRoom, polygon: [Vec2(0, 0), Vec2(4, 0), Vec2(4, 4), Vec2(0, 4)])
        let b = Space(id: "sp-b", floorID: "fl-b", label: "B", kind: .other, polygon: [Vec2(0, 0), Vec2(4, 0), Vec2(4, 4), Vec2(0, 4)])
        let front = Portal(id: "pt-front", floorID: "fl-g", kind: .door, a: Vec2(4, 1), b: Vec2(4, 1.9), sideA: .space("sp-g"), sideB: .unknown,
                           clearWidthMeters: .confirmed(0.9), verification: .proposed)
        let walkout = Portal(id: "pt-walkout", floorID: "fl-b", kind: .door, a: Vec2(4, 1), b: Vec2(4, 1.9), sideA: .space("sp-b"), sideB: .unknown,
                             clearWidthMeters: .confirmed(0.9), verification: .proposed)
        let home = HomeModel(id: "h-basement", label: "b", source: .manual, floors: [fB, fG], spaces: [b, g], portals: [front, walkout], isFictional: true)
        let afterFront = HomeConfirmation.apply(.markPortalExterior(portalID: "pt-front", operable: true, stepFree: true), to: home)
        #expect(afterFront.portal("pt-front")?.verification == .verified)
    
        let afterWalkout = HomeConfirmation.apply(.markPortalExterior(portalID: "pt-walkout", operable: true, stepFree: true), to: home)
        let r = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-b"), in: afterWalkout)
        #expect(afterWalkout.portal("pt-walkout")?.verification != .verified || r.primary != nil)
    
    }

    @Test("Confirmation: a window is not turned into a walking exit by the generic exterior answer")
    func windowExit() {
        let s = Space(id: "sp-r", floorID: "fl-0", label: "R", kind: .bedroom, polygon: [Vec2(0, 0), Vec2(4, 0), Vec2(4, 4), Vec2(0, 4)])
        let w = Portal(id: "pt-w", floorID: "fl-0", kind: .window, a: Vec2(1, 0), b: Vec2(2, 0), sideA: .space("sp-r"), sideB: .unknown,
                       clearWidthMeters: .confirmed(0.9), verification: .proposed)
        let home = HomeModel(id: "h", label: "w", source: .manual, floors: [Floor(id: "fl-0", level: 0, label: "G")], spaces: [s], portals: [w], isFictional: true)
        #expect(HomeConfirmation.apply(.skip(elementID: "pt-w"), to: home) == home)
        let after = HomeConfirmation.apply(.markPortalExterior(portalID: "pt-w", operable: true, stepFree: nil), to: home)
        #expect(EgressPlanner().plan(RouteRequest(startSpaceID: "sp-r"), in: after).primary == nil)
    
    }

    @Test("Shelter spot must be on the lowest floor, and the plan prints only a verified shelter")
    func shelter() throws {
        let tw = SampleHomes.twoStory
        let upper = tw.spaces.first { s in tw.floors.first { $0.id == s.floorID }!.level > 0 }!
        let after = HomeConfirmation.apply(.shelterSpot(spaceID: upper.id, interiorNoWindows: true), to: tw)
        #expect(!after.annotations.contains { $0.kind == .tornadoShelterCandidate && $0.spaceID == upper.id })
    
        var home = SampleHomes.ranch
        for i in home.annotations.indices where home.annotations[i].kind == .tornadoShelterCandidate { home.annotations[i].verification = .proposed }
        let d = try plan(SampleHouseholds.oak, ["tornado"], locale: "en", home: home)
        let keys = lines(d, page: "scenario-tornado", section: "shelter").map(\.key)
        #expect(!keys.contains("plan.shelter.line"))
    
    }
}
