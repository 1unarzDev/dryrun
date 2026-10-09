import Foundation
import Testing
@testable import DryRunCore

@Suite("Plan builder and localization")
struct PlanBuilderTests {
    static func tinyHome(meetingVerified: Bool = true) -> HomeModel {
        HomeModel(
            id: "home-test", label: "Test", source: .manual,
            floors: [Floor(id: "f1", level: 0, label: "Ground")],
            spaces: [Space(id: "sp-bed1", floorID: "f1", label: "Bedroom 1", kind: .bedroom,
                           polygon: [Vec2(0, 0), Vec2(3, 0), Vec2(3, 3), Vec2(0, 3)])],
            portals: [],
            annotations: [Annotation(id: "an-meeting", kind: .outsideMeetingPoint, label: "Mailbox at the street",
                                     verification: meetingVerified ? .verified : .proposed)],
            isFictional: true)
    }

    static func fakeResult(_ scenarioID: String, household: HouseholdProfile, home: HomeModel, routes: [RouteResult] = [],
                           recommendations: [Recommendation] = []) -> RehearsalResult {
        let input = RehearsalInput(household: household, home: home, scenarioID: scenarioID, scenarioVersion: "test",
                                   contentVersion: "test")
        return RehearsalResult(input: input, events: [], snapshots: [], decisions: [], routes: routes,
                               recommendations: recommendations, unknowns: [], engineVersion: "test")
    }

    static func localizer(_ locale: String, tables extra: [String: [String: [String: String]]] = [:],
                          manifest: LocaleManifest? = nil) throws -> Localizer {
        let lib = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        var tables = lib.tables
        for (loc, domains) in extra { for (d, t) in domains { tables[loc, default: [:]][d] = t } }
        return Localizer(locale: locale, tables: tables, manifest: manifest ?? lib.localeManifest)
    }

    @Test("English plan for every sample household validates with no unresolved keys or placeholders")
    func englishPlansValidate() throws {
        let l = try Self.localizer("en")
        let home = Self.tinyHome()
        for h in SampleHouseholds.all {
            let results = PlanBuilder.scenarioOrder.map { Self.fakeResult($0, household: h, home: home) }
            let doc = PlanBuilder.build(household: h, home: home, results: results, localizer: l, resources: [],
                                        contentVersion: "2026.10.0", generatedAt: LeadTestSupport.fixedDate)
            #expect(doc.pages.count == 7, "one essentials page plus one page per scenario")
            #expect(PlanValidator.validate(doc, household: h).isEmpty, "\(PlanValidator.validate(doc, household: h))")
            #expect(doc.pages.flatMap(\.sections).flatMap(\.lines).contains { $0.text.contains("911") })
        }
    }

    @Test("Water storage target is 1 gal/person/day x 3 days and labeled as a storage target")
    func waterTarget() throws {
        #expect(WaterTarget.storageTargetGallons(people: 4, days: 3) == 12)
        let l = try Self.localizer("en")
        let doc = PlanBuilder.build(household: SampleHouseholds.oak, home: Self.tinyHome(), results: [], localizer: l,
                                    resources: [], contentVersion: "x", generatedAt: LeadTestSupport.fixedDate)
        let water = doc.pages[0].sections.first { $0.id == "water" }!.lines[0].text
        #expect(water.contains("12 gallons"))
        #expect(water.contains("storage target"))
    }

    @Test("Missing translation falls back to English visibly and the document carries the fallback note")
    func visibleFallback() throws {
        let partial = ["vi": ["plan": ["plan.title.essentials": "Thông tin thiết yếu của gia đình"]]]
        let manifest = LocaleManifest(schemaVersion: 1, sourceLocale: "en", locales: [
            .init(code: "en", name: "English", nativeName: "English", domains: ["plan": .reviewed, "common": .reviewed], note: nil),
            .init(code: "vi", name: "Vietnamese", nativeName: "Tiếng Việt", domains: ["plan": .draft], note: nil),
        ])
        let l = try Self.localizer("vi", tables: partial, manifest: manifest)
        let title = l.text("plan.title.essentials")
        #expect(title.resolvedLocale == "vi" && title.needsDraftLabel && !title.isFallback)
        let other = l.text("plan.section.people")
        if !l.has("plan.section.people", in: "vi") {
            #expect(other.isFallback && other.resolvedLocale == "en")
        }
        let doc = PlanBuilder.build(household: SampleHouseholds.lake, home: Self.tinyHome(), results: [], localizer: l,
                                    resources: [], contentVersion: "x", generatedAt: LeadTestSupport.fixedDate)
        #expect(doc.pages[0].title == "Thông tin thiết yếu của gia đình")
        #expect(doc.draftTranslationBanner?.contains("Draft translation - language review pending") == true,
                "the exact English draft phrase is always visible alongside the localized banner")
        #expect(PlanValidator.validate(doc, household: SampleHouseholds.lake).isEmpty)
    }

    @Test("Real ES/VI packs, when present, keep numbers, units, phone numbers, and are labeled draft")
    func realLocalePacksPreserveFacts() throws {
        let lib = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        for locale in ["es", "vi"] {
            let l = lib.localizer(for: locale)
            let doc = PlanBuilder.build(household: SampleHouseholds.oak, home: Self.tinyHome(),
                                        results: [Self.fakeResult("water-outage", household: SampleHouseholds.oak, home: Self.tinyHome())],
                                        localizer: l, resources: [], contentVersion: "x", generatedAt: LeadTestSupport.fixedDate)
            let all = doc.pages.flatMap(\.sections).flatMap(\.lines)
            #expect(all.contains { $0.text.contains("911") })
            #expect(all.contains { $0.text.contains("12") }, "water target number survives in \(locale)")
            #expect(PlanValidator.validate(doc, household: SampleHouseholds.oak).isEmpty, "\(locale): \(PlanValidator.validate(doc, household: SampleHouseholds.oak))")
            if all.contains(where: { $0.resolvedLocale == locale }) {
                #expect(doc.draftTranslationBanner != nil, "AI-drafted \(locale) text must carry the draft banner")
            }
            // Placeholders in each translated key match English exactly.
            for key in l.allKeys(in: locale) where l.has(key, in: "en") {
                #expect(Localizer.placeholders(in: rawText(lib, "en", key)) == Localizer.placeholders(in: rawText(lib, locale, key)),
                        "\(locale) \(key) placeholders differ from English")
            }
        }
    }

    private func rawText(_ lib: ContentLibrary, _ locale: String, _ key: String) -> String {
        lib.tables[locale]?.values.compactMap { $0[key] }.first ?? ""
    }

    @Test("Private care-plan notes are excluded by default and included only by explicit option")
    func privateNotes() throws {
        var h = SampleHouseholds.oak
        h.equipment[0].carePlanNotes = "CANARY-PRIVATE-CARE-NOTE"
        let l = try Self.localizer("en")
        let doc = PlanBuilder.build(household: h, home: Self.tinyHome(), results: [], localizer: l, resources: [],
                                    contentVersion: "x", generatedAt: LeadTestSupport.fixedDate)
        let text = doc.pages.flatMap(\.sections).flatMap(\.lines).map(\.text).joined()
        #expect(!text.contains("CANARY-PRIVATE-CARE-NOTE"))
        let withNotes = PlanBuilder.build(household: h, home: Self.tinyHome(), results: [], localizer: l, resources: [],
                                          contentVersion: "x", generatedAt: LeadTestSupport.fixedDate,
                                          options: .init(includePrivateNotes: true))
        #expect(withNotes.pages.flatMap(\.sections).flatMap(\.lines).contains { $0.text == "CANARY-PRIVATE-CARE-NOTE" })
    }

    @Test("Unknown device runtime is printed as unknown, never as an estimate")
    func unknownRuntime() throws {
        let l = try Self.localizer("en")
        let doc = PlanBuilder.build(household: SampleHouseholds.oak, home: Self.tinyHome(), results: [], localizer: l,
                                    resources: [], contentVersion: "x", generatedAt: LeadTestSupport.fixedDate)
        let eq = doc.pages[0].sections.first { $0.id == "equipment" }!.lines[0].text
        #expect(eq.contains("unknown"))
        #expect(eq.contains("not confirmed"))
    }

    @Test("Editing household or home revision makes a saved plan stale")
    func staleness() throws {
        let l = try Self.localizer("en")
        var h = SampleHouseholds.oak
        var home = Self.tinyHome()
        let doc = PlanBuilder.build(household: h, home: home, results: [], localizer: l, resources: [],
                                    contentVersion: "v1", generatedAt: LeadTestSupport.fixedDate)
        #expect(!doc.isStale(household: h, home: home, contentVersion: "v1"))
        home.bumpRevision()
        #expect(doc.isStale(household: h, home: home, contentVersion: "v1"))
        home.revision -= 1
        h.bumpRevision(at: LeadTestSupport.fixedDate)
        #expect(doc.isStale(household: h, home: home, contentVersion: "v1"))
        #expect(doc.isStale(household: SampleHouseholds.oak, home: Self.tinyHome(), contentVersion: "v2"))
    }

    @Test("Fire page explains no-route and shared-chokepoint results instead of inventing an exit")
    func fireRouteLines() throws {
        let l = try Self.localizer("en")
        let home = Self.tinyHome(meetingVerified: false)
        let noRoute = RouteResult(request: RouteRequest(startSpaceID: "sp-bed1"), primary: nil, alternative: nil,
                                  alternativeStatus: .none, noRouteReason: .noVerifiedExteriorExit, exclusions: [],
                                  homeID: home.id, homeRevision: home.revision)
        let doc = PlanBuilder.build(household: SampleHouseholds.oak, home: home,
                                    results: [Self.fakeResult("home-fire", household: SampleHouseholds.oak, home: home, routes: [noRoute])],
                                    localizer: l, resources: [], contentVersion: "x", generatedAt: LeadTestSupport.fixedDate)
        let lines = doc.pages[1].sections.first { $0.id == "homeplan" }!.lines.map(\.text)
        #expect(lines.contains { $0.contains("No verified practice route from Bedroom 1") && $0.contains("no verified exterior exit") })
        #expect(lines.contains { $0.contains("No outside meeting point is chosen yet") }, "unverified meeting point is not printed as chosen")
        #expect(lines.contains { $0.contains("not a real-time safest route") })
    }

    @Test("Manufactured home tornado page directs to a pre-planned sturdy building, not an interior closet")
    func manufacturedTornado() throws {
        let l = try Self.localizer("en")
        var home = Self.tinyHome()
        home.annotations.append(Annotation(id: "an-closet", kind: .tornadoShelterCandidate, label: "Closet", verification: .verified))
        let doc = PlanBuilder.build(household: SampleHouseholds.pine, home: home,
                                    results: [Self.fakeResult("tornado", household: SampleHouseholds.pine, home: home)],
                                    localizer: l, resources: [], contentVersion: "x", generatedAt: LeadTestSupport.fixedDate)
        let shelter = doc.pages[1].sections.first { $0.id == "shelter" }!.lines.map(\.text)
        #expect(shelter.contains { $0.contains("not safe shelter") })
        #expect(!shelter.contains { $0.contains("Shelter spot: Closet") })
    }

    @Test("Prohibitions keep their emphasis in every locale (styled from the source text, not translated words)")
    func prohibitionsAcrossLocales() throws {
        let lib = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        let home = Self.tinyHome()
        func prohibitionKeys(_ locale: String) -> Set<String> {
            let doc = PlanBuilder.build(household: SampleHouseholds.oak, home: home,
                                        results: PlanBuilder.scenarioOrder.map { Self.fakeResult($0, household: SampleHouseholds.oak, home: home) },
                                        localizer: lib.localizer(for: locale), resources: [], contentVersion: "x",
                                        generatedAt: LeadTestSupport.fixedDate)
            return Set(doc.pages.flatMap(\.sections).flatMap(\.lines).filter { $0.style == .prohibition }.map(\.key))
        }
        let en = prohibitionKeys("en")
        #expect(en.contains("plan.scenario.home-fire.immediate.1"))
        #expect(prohibitionKeys("es") == en)
        #expect(prohibitionKeys("vi") == en)
    }
}
