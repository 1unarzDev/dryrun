import Foundation
import Testing
@testable import DryRunCore

@Suite("Selected-language plan and card content")
struct PlanSelectedLanguageTests {
    static let date = ISO8601DateFormatter().date(from: "2026-10-10T03:00:00Z")!
    static let zone = TimeZone(identifier: "America/Chicago")!

    static func household() -> HouseholdProfile {
        var h = SampleHouseholds.oak
        h.isFictional = false
        h.displayName = "USER-HOUSEHOLD"
        h.people = [Person(id: "self", alias: "", ageBand: .unknown, isSelf: true)]
        h.privateLocation = PrivateLocation(addressLine: "USER-ADDRESS", countryCode: "FR")
        h.equipment = []; h.backupPower = []; h.contacts = []
        h.preparedness = .init(reviewedAt: date)
        return h
    }
    static func build(_ h: HouseholdProfile, home: HomeModel? = nil, results: [RehearsalResult] = [], localizer: Localizer,
                      critical: Bool = false) -> PlanDocument {
        PlanBuilder.build(household: h, home: home, results: results, localizer: localizer, resources: [],
                          contentVersion: "test", generatedAt: date,
                          options: .init(familyCardSelection: .init(includeCriticalInformation: critical, includeMedication: true, includeResponderInstructions: true), timeZone: zone))
    }

    @Test("All no-route reasons and missing start text resolve in exported EN/ES/VI documents without changing route evidence")
    func incompleteRoutesInDocuments() throws {
        var h = Self.household()
        let home = PlanBuilderTests.tinyHome()
        h.people = NoRouteReason.allCases.enumerated().map { index, _ in Person(id: "resident-\(index)", alias: "USER-\(index)", ageBand: .unknown) }
        let routes = NoRouteReason.allCases.enumerated().map { index, reason in
            RouteResult(request: RouteRequest(personID: h.people[index].id, startSpaceID: reason == .unknownStartSpace ? "missing-start" : home.spaces[0].id),
                        primary: nil, alternative: nil, alternativeStatus: .none, noRouteReason: reason, exclusions: [], homeID: home.id, homeRevision: home.revision)
        }
        let result = PlanBuilderTests.fakeResult("home-fire", household: h, home: home, routes: routes)
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            let doc = Self.build(h, home: home, results: [result], localizer: l)
            let lines = try #require(doc.pages.first { $0.id == "scenario-home-fire" }?.sections.first { $0.id == "homeplan" }?.lines)
                .filter { $0.key == "plan.route.none" }
            #expect(lines.count == NoRouteReason.allCases.count)
            for (index, reason) in NoRouteReason.allCases.enumerated() {
                #expect(lines[index].text.contains(l("plan.route.reason.\(reason.rawValue)")))
                #expect(lines[index].text.contains("USER-\(index)"))
                #expect(!lines[index].text.contains(reason.rawValue))
                #expect(lines[index].resolvedLocale == locale && !lines[index].isFallback && lines[index].unfilledPlaceholders.isEmpty)
            }
            #expect(lines.last?.text.contains(l("plan.route.unknownRoom")) == true)
            #expect(doc.visualSnapshot?.routes == routes)
            #expect(PlanValidator.validate(doc, household: h).isEmpty)
        }
    }

    @Test("App dates, decimal quantities and empty self labels use selected language while recorded medicine text stays exact")
    func formattingAndRecordedText() throws {
        var h = Self.household()
        let note = "USER-INSTRUCTION: 0.5 mg @ 08:30; unchanged {literal}."
        h.people[0].emergencyInformation = .init(essentialMedication: "USER-MEDICINE", responderInstructions: note)
        h.equipment = [PoweredEquipment(id: "device", purpose: .oxygenConcentrator, label: "USER-MODEL 2.5", personID: "self", documentedBackupRuntimeHours: .confirmed(2.5))]
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            let doc = Self.build(h, localizer: l, critical: true)
            let card = try #require(doc.pages.first { $0.id == "family-card" })
            let text = card.sections.flatMap(\.lines).map(\.text).joined(separator: "\n")
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: locale); formatter.timeZone = Self.zone; formatter.dateStyle = .medium
            let review = try #require(card.sections.first { $0.id == "review" }?.lines.first?.text)
            #expect(review == formatter.string(from: Self.date))
            #expect(text.contains(l("family.you")) && text.contains("USER-MODEL 2.5") && text.contains(note))
            #expect(text.contains(l("plan.equipment.runtimeKnown", ["hours": locale == "en" ? "2.5" : "2,5"])))
            let cardSources = Set(card.sections.flatMap(\.lines).flatMap(\.sourceIDs))
            #expect(!cardSources.isEmpty && Set(doc.sourceIDs).isSuperset(of: cardSources))
            #expect(PlanValidator.validate(doc, household: h).isEmpty, "household-authored braces are not unresolved placeholders")
        }
    }

    @Test("Emergency instructions use a known country number or the localized local-number phrase throughout the document")
    func emergencyNumberScope() throws {
        var h = Self.household()
        let home = PlanBuilderTests.tinyHome()
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            for country in ["US", "CA", "FR", "VN", ""] {
                h.privateLocation?.countryCode = country.isEmpty ? nil : country
                let results = ["home-fire", "freeze-power-loss", "heat-grid-strain"].map { PlanBuilderTests.fakeResult($0, household: h, home: home) }
                let doc = Self.build(h, home: home, results: results, localizer: l)
                let lines = doc.pages.flatMap(\.sections).flatMap(\.lines)
                let immediate = lines.filter { $0.key.hasPrefix("plan.scenario.") }
                if ["US", "CA"].contains(country) {
                    if country == "CA" {
                        #expect(lines.filter { $0.text.contains("911") }.allSatisfy { $0.sourceIDs.contains("S56") })
                        #expect(doc.sourceIDs.contains("S56"))
                    }
                    #expect(immediate.contains { $0.text.contains("911") })
                } else {
                    #expect(!lines.contains { $0.text.contains("911") })
                    #expect(immediate.contains { $0.text.contains(l("plan.help.emergencyNumber.local")) })
                    #expect(lines.contains { $0.key == "plan.help.localUnknown" })
                }
                #expect(lines.allSatisfy { $0.unfilledPlaceholders.isEmpty })
            }
        }
    }

    @Test("A fallback inside the family card is identified and retained with a visible document notice")
    func cardFallbackProvenance() throws {
        let library = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        var tables = library.tables
        for domain in tables["vi"]!.keys { tables["vi"]?[domain]?.removeValue(forKey: "family.addressMissing") }
        let l = Localizer(locale: "vi", tables: tables, manifest: library.localeManifest)
        var h = Self.household(); h.privateLocation = nil
        let doc = Self.build(h, localizer: l)
        let card = try #require(doc.pages.first { $0.id == "family-card" })
        let address = try #require(card.sections.first { $0.id == "identity" }?.lines.first { $0.text == l.with(locale: "en")("family.addressMissing") })
        #expect(address.isFallback)
        #expect(card.sections.flatMap(\.lines).contains { $0.isDraftTranslation })
        #expect(doc.fallbackNote == l("plan.fallbackNote") && doc.draftTranslationBanner != nil)
        #expect(PlanValidator.validate(doc, household: h).isEmpty)
        // Composed quantity units must carry provenance too, even when the surrounding sentence is translated.
        tables = library.tables
        tables["vi"]?["spatial"]?.removeValue(forKey: "spatial.quantity.litres.other")
        let partialUnits = Localizer(locale: "vi", tables: tables, manifest: library.localeManifest)
        h.supplies.storedWaterGallons = .confirmed(1)
        let unitsDocument = Self.build(h, localizer: partialUnits)
        let water = try #require(unitsDocument.pages.flatMap(\.sections).flatMap(\.lines).first { $0.key == "plan.water.target" })
        #expect(water.isFallback && unitsDocument.fallbackNote != nil)
    }

    @Test("Long responder instructions cannot steal translation provenance from the critical line")
    func longInstructionFallbackIsOnTheRightLine() throws {
        let library = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        var tables = library.tables
        tables["vi"]?["common"]?.removeValue(forKey: "family.allergies")
        let l = Localizer(locale: "vi", tables: tables, manifest: library.localeManifest)
        var h = Self.household()
        h.people[0].alias = "USER-PERSON"
        let note = String(repeating: "USER-NOTE; ", count: 100)
        h.people[0].emergencyInformation = .init(severeAllergies: "USER-ALLERGY", responderInstructions: note)
        let doc = Self.build(h, localizer: l, critical: true)
        let card = try #require(doc.pages.first { $0.id == "family-card" })
        let critical = try #require(card.sections.first { $0.id == "critical" }?.lines.first)
        let continuation = try #require(card.sections.first { $0.id == "instruction-continuation" }?.lines.first)
        #expect(critical.isFallback && critical.text.contains("USER-ALLERGY"))
        #expect(!continuation.isFallback && continuation.text == "USER-PERSON: " + note)
        #expect(doc.fallbackNote != nil)
    }

    @Test("Default annotation labels localize in text and selected visual snapshots without repopulating redacted labels")
    func annotationLabelsAndRedaction() throws {
        let h = Self.household()
        var home = PlanBuilderTests.tinyHome()
        home.annotations = [Annotation(id: "meet", kind: .outsideMeetingPoint, label: "outsideMeetingPoint", verification: .verified),
                            Annotation(id: "alarm", kind: .smokeAlarm, label: "", verification: .verified),
                            Annotation(id: "private", kind: .medicalEquipment, label: "USER-PRIVATE-LABEL", verification: .verified),
                            Annotation(id: "custom", kind: .supplies, label: "USER-SUPPLY-LABEL", verification: .verified)]
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            for key in ["enum.outsideMeetingPoint", "enum.smokeAlarm"] {
                #expect(!l.text(key).isMissing && !l.text(key).isFallback)
            }
            let selected = Self.build(h, home: home, localizer: l, critical: true)
            #expect(selected.pages.flatMap(\.sections).flatMap(\.lines).contains { $0.key == "plan.meeting.line" && $0.text.contains(l("enum.outsideMeetingPoint")) })
            #expect(selected.visualSnapshot?.home?.annotations.first { $0.id == "alarm" }?.label == l("enum.smokeAlarm"))
            #expect(selected.visualSnapshot?.home?.annotations.first { $0.id == "private" }?.label == "USER-PRIVATE-LABEL")
            let redacted = Self.build(h, home: home, localizer: l)
            #expect(redacted.visualSnapshot?.home?.annotations.allSatisfy { $0.label.isEmpty } == true)
            #expect(redacted.visualSnapshot?.home?.annotations.contains { $0.id == "private" || $0.id == "custom" } == false)
            #expect(home.annotations.first?.label == "outsideMeetingPoint", "export localization never mutates the canonical home")
        }
    }

    @Test("User-facing validation descriptions are localized and omit raw IDs, template text and private notes")
    func validationDescriptions() throws {
        let issues: [PlanValidationIssue] = [.missingEssentialsPage, .emptySafetySection("PRIVATE-SECTION"), .unresolvedKey("PRIVATE-KEY"), .unfilledPlaceholder("PRIVATE-NOTE"), .draftWithoutBanner, .fallbackWithoutNote, .privateNotesLeaked("PRIVATE-DEVICE")]
        for locale in ["en", "es", "vi"] {
            let l = try PlanBuilderTests.localizer(locale)
            for issue in issues {
                let text = issue.localizedDescription(l)
                #expect(!text.isEmpty && !text.hasPrefix("plan.") && !text.contains("PRIVATE"))
                if locale != "en" { #expect(text != issue.localizedDescription(l.with(locale: "en"))) }
            }
        }
        #expect(issues[1].description.contains("PRIVATE-SECTION"), "local diagnostic detail remains available separately")
    }

    @Test("Official English resource notes retain their source wording with visible fallback provenance in translated plans")
    func publicSourceLanguageIsExplicit() throws {
        let library = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        let resource = try #require(library.resources(forRegion: "48143").first { $0.contact.phoneNote != nil && $0.contact.phone != nil })
        var h = Self.household(); h.privateLocation?.countryCode = "US"
        for locale in ["en", "es", "vi"] {
            let l = library.localizer(for: locale)
            let doc = PlanBuilder.build(household: h, home: nil, results: [], localizer: l, resources: [resource],
                                        contentVersion: library.contentVersion, generatedAt: Self.date)
            let sourceLine = try #require(doc.pages.flatMap(\.sections).flatMap(\.lines).first { $0.key == "plan.help.lineNote" })
            #expect(sourceLine.text.contains(resource.name))
            #expect(sourceLine.text.contains(try #require(resource.contact.phoneNote)))
            #expect(sourceLine.sourceIDs == resource.sourceIDs)
            #expect(sourceLine.isFallback == (locale != "en"))
            if locale != "en" { #expect(doc.fallbackNote == l("plan.fallbackNote")) }
            #expect(PlanValidator.validate(doc, household: h).isEmpty)
        }
    }
}
