import Foundation
import Testing
@testable import DryRunCore

@Suite("Selectable content languages")
struct LanguageAvailabilityTests {
    @Test func bundledLanguagesIncludeCompleteDraftsAndKeepTheirReviewState() throws {
        let content = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        let localizer = content.localizer(for: "vi")
        #expect(localizer.selectableLocales == ["en", "es", "vi"])
        for code in localizer.selectableLocales {
            let selected = localizer.with(locale: code)
            #expect(selected.text("common.tab.prepare").resolvedLocale == code)
            #expect(selected.reviewState(code, "common") == .draft)
        }
    }

    @Test func incompleteControlsAndBrokenPlaceholdersCannotBeOfferedAsCompleteLanguages() throws {
        let content = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        var tables = content.tables
        // Keep most translated content present: completeness must include the native-only domain too.
        tables["es"]?.removeValue(forKey: "native")
        tables["vi"]?["common"]?["common.tab.prepare"] = "   "
        let incomplete = Localizer(locale: "en", tables: tables, manifest: content.localeManifest)
        #expect(incomplete.availableLocales == ["en", "es", "vi"])
        #expect(incomplete.selectableLocales == ["en"])
        // Existing documents may still resolve a partial pack; the fallback stays explicitly observable.
        let fallback = incomplete.with(locale: "es").text("native.settings")
        #expect(fallback.isFallback && fallback.resolvedLocale == "en")

        tables = content.tables
        tables["es"]?["common"]?["common.simClock"] = "Tiempo del ejercicio"
        tables["vi"]?["common"]?["common.simClock"] = "Thời gian {time} {extra}"
        #expect(Localizer(locale: "en", tables: tables, manifest: content.localeManifest).selectableLocales == ["en"])
    }

    @Test func spatialPickerValuesHaveSelectedLanguageText() throws {
        let content = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        let values = SpaceKind.allCases.map(\.rawValue) + PortalKind.allCases.map(\.rawValue) + AnnotationKind.allCases.map(\.rawValue)
        for code in ["en", "es", "vi"] {
            let localizer = content.localizer(for: code)
            for value in values {
                let text = localizer.text("enum." + value)
                #expect(!text.isMissing && !text.isFallback && text.unfilledPlaceholders.isEmpty, "\(code): \(value)")
            }
        }
    }

    @Test func legacyMarkerTypeNamesLocalizeWithoutChangingCustomOrStoredLabels() throws {
        let content = try ContentLibrary.load(from: LeadTestSupport.contentRoot)
        let blank = Annotation(id: "marker", kind: .smokeAlarm, label: "")
        let legacy = Annotation(id: "legacy", kind: .smokeAlarm, label: "smokeAlarm")
        let custom = Annotation(id: "custom", kind: .smokeAlarm, label: "My hallway alarm {name}")
        for code in ["en", "es", "vi"] {
            let localizer = content.localizer(for: code)
            #expect(blank.localizedLabel(localizer) == localizer("enum.smokeAlarm"))
            #expect(legacy.localizedLabel(localizer) == blank.localizedLabel(localizer))
            #expect(custom.localizedLabel(localizer) == custom.label)
        }
        let decoded = try DryRunJSON.decoder().decode(Annotation.self, from: DryRunJSON.encoder().encode(legacy))
        #expect(decoded.label == "smokeAlarm")
    }
}
