import XCTest
import PDFKit
import UIKit
import DryRunCore
@testable import DryRun

@MainActor
final class PlanExportTests: XCTestCase {
    func testLongSelectedMedicalBlockContinuesAndAllSupportedLanguagesRetainItsEndOnLetterAndA4() throws {
        let library = try ContentLibrary.load(from: ContentLocator.contentRoot())
        var household = SampleHouseholds.oak
        household.people[0].emergencyInformation = PersonEmergencyInformation(criticalConditions:
            "BEGIN-RECORDED-NOTE " + String(repeating: "Family supplied information, sin traducción, không dịch. ", count: 300) + " END-RECORDED-NOTE")
        for locale in ["en", "es", "vi"] {
            let doc = PlanBuilder.build(household: household, home: nil, results: [], localizer: library.localizer(for: locale), resources: [], contentVersion: library.contentVersion, generatedAt: Date(timeIntervalSince1970: 1700000000), options: .init(familyCardSelection: .init(includeCriticalInformation: true)))
            for paper in PlanPDFRenderer.Paper.allCases {
                let output = PlanPDFRenderer().render(doc, paper: paper)
                let pdf = try XCTUnwrap(PDFDocument(data: output.data))
                let text = try XCTUnwrap(pdf.string)
                XCTAssertTrue(text.contains("BEGIN-RECORDED-NOTE"))
                XCTAssertTrue(text.contains("END-RECORDED-NOTE"))
                XCTAssertGreaterThan(output.pageCount, 2)
                XCTAssertTrue(output.continuedPageIDs.contains("family-card"))
                let bounds = try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox)
                XCTAssertEqual(bounds.width, paper.size.width, accuracy: 0.1)
                XCTAssertEqual(bounds.height, paper.size.height, accuracy: 0.1)
            }
        }
    }

    func testProtectedExportIsNotPurgedWhileActivityReadsIt() throws {
        TemporaryExports.hasActiveExport = false; TemporaryExports.purgeAll()
        let url = try TemporaryExports.write(Data("fictional test export".utf8), name: "lease-test.pdf")
        TemporaryExports.retainActivity()
        TemporaryExports.purgeAll()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        TemporaryExports.releaseActivity()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

extension PlanExportTests {
    func testPartialMapSnapshotFailureNamesTheMissingInsetAndRetainsItsText() throws {
        let library = try ContentLibrary.load(from: ContentLocator.contentRoot())
        var household = SampleHouseholds.oak
        household.privateLocation = PrivateLocation(latitude: 32.2, longitude: -98.2)
        let backup = SavedPlace(id: "far-backup", homeID: household.stableHomeID, purpose: .backupMeetingPlace, label: "DISTANT-MEETUP", coordinate: GeographicCoordinate(latitude: 35, longitude: -98.2), addressText: "99 Fictional Road", findingInstructions: "Beside the public entrance")
        let doc = PlanBuilder.build(household: household, home: nil, savedPlaces: [backup], results: [], localizer: library.localizer(for: "en"), resources: [], contentVersion: library.contentVersion, generatedAt: Date(timeIntervalSince1970: 1700000000))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 520)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 520))
        }
        let local = PlanMapPanel(image: image, title: "Neighborhood", legend: [], extentID: "neighborhood")
        let distant = PlanMapPanel(image: image, title: backup.label, legend: [], extentID: "place|" + backup.id)
        for paper in PlanPDFRenderer.Paper.allCases {
            let partial = PlanPDFRenderer().render(doc, paper: paper, mapPanels: [local])
            let partialText = try XCTUnwrap(PDFDocument(data: partial.data)?.string)
            XCTAssertTrue(partialText.contains("Map image unavailable for: DISTANT-MEETUP"))
            XCTAssertTrue(partialText.contains("99 Fictional Road"))
            XCTAssertTrue(partialText.contains("Beside the public entrance"))
            let complete = PlanPDFRenderer().render(doc, paper: paper, mapPanels: [local, distant])
            XCTAssertFalse(try XCTUnwrap(PDFDocument(data: complete.data)?.string).contains("Map image unavailable for:"))
        }
    }

    func testCardOnlyExportDoesNotAppendHiddenHomeGeometry() throws {
        let library = try ContentLibrary.load(from: ContentLocator.contentRoot())
        var card = PlanBuilder.build(household: SampleHouseholds.oak, home: SampleHomes.ranch, results: [], localizer: library.localizer(for: "en"), resources: [], contentVersion: library.contentVersion, generatedAt: Date(timeIntervalSince1970: 1700000000))
        card.pages = card.pages.filter { $0.id == "family-card" }
        let withAttachedSnapshot = PlanPDFRenderer().render(card)
        card.visualSnapshot = nil
        let withoutSnapshot = PlanPDFRenderer().render(card)
        XCTAssertEqual(withAttachedSnapshot.pageCount, withoutSnapshot.pageCount)
        let attachedText = try XCTUnwrap(PDFDocument(data: withAttachedSnapshot.data)?.string)
        XCTAssertFalse(attachedText.contains("Bedroom 1"))
    }
}

extension PlanExportTests {
    func testLongMapLegendsAndSourceIndexContinueWithoutLosingTheirEnd() throws {
        let library = try ContentLibrary.load(from: ContentLocator.contentRoot())
        var doc = PlanBuilder.build(household: SampleHouseholds.oak, home: nil, results: [], localizer: library.localizer(for: "en"), resources: [], contentVersion: library.contentVersion, generatedAt: Date(timeIntervalSince1970: 1700000000))
        doc.sourceIDs = (0..<100).map { "source-\($0)" }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 520)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0,y: 0,width: 900,height: 520))
        }
        let legend = (0..<6).map { "\($0). " + String(repeating: "Long fictional landmark instructions. ", count: 80) + " LEGENDEND\($0)" }
        for paper in PlanPDFRenderer.Paper.allCases {
            let output = PlanPDFRenderer().render(doc, paper: paper, mapPanels: [PlanMapPanel(image: image, title: "Fictional map legend", legend: legend)])
            let text = try XCTUnwrap(PDFDocument(data: output.data)?.string)
            XCTAssertTrue(text.contains("LEGENDEND5"))
            XCTAssertTrue(text.contains("source-99"))
            XCTAssertTrue(output.continuedPageIDs.contains("map-legend"))
        }
    }

    func testLegacyDiagramQualificationsAreRetainedInPDFForEverySupportedLanguage() throws {
        let library = try ContentLibrary.load(from: ContentLocator.contentRoot())
        let home = SampleHomes.ranch, household = SampleHouseholds.oak
        var route = EgressPlanner().plan(RouteRequest(personID: household.people[0].id, startSpaceID: "sp-bed1"), in: home)
        route.primary = nil; route.alternative = nil; route.alternativeStatus = .none; route.noRouteReason = .blockedByScenario
        let state = SpatialExerciseState(hazard: .homeFire, seed: 7, stageID: "blocked", affectedSpaceIDs: ["sp-bed1"], routes: [route], assumption: "Authored blockage", assumptionKey: "spatial.assumption.fire-blocked")
        let input = RehearsalInput(household: household, home: home, scenarioID: "home-fire", scenarioVersion: "test", contentVersion: library.contentVersion, seed: 7)
        let result = RehearsalResult(input: input, events: [], snapshots: [.init(simMinute: 3, services: [:], resources: [:], unmetRequirements: [], unknowns: [], firedEventIDs: [], spatialState: state)], decisions: [], routes: [route], recommendations: [], unknowns: [], engineVersion: "test")
        func normalized(_ string: String) -> String { string.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        for locale in ["en", "es", "vi"] {
            let l = library.localizer(for: locale)
            let doc = PlanBuilder.build(household: household, home: home, results: [result], localizer: l, resources: [], contentVersion: library.contentVersion, generatedAt: Date(timeIntervalSince1970: 1700000000))
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as? [String: Any])
            var visual = try XCTUnwrap(object["visualSnapshot"] as? [String: Any])
            visual.removeValue(forKey: "panelDetails"); object["visualSnapshot"] = visual
            let legacy = try JSONDecoder().decode(PlanDocument.self, from: JSONSerialization.data(withJSONObject: object))
            let snapshot = try XCTUnwrap(legacy.visualSnapshot)
            XCTAssertNil(snapshot.panelDetails)
            let expected = try XCTUnwrap(snapshot.homePanels.first { $0.route != nil }).details(in: snapshot, localizer: l)
            for paper in PlanPDFRenderer.Paper.allCases {
                // Exercise the real bundled-content fallback, not an injected precomputed dictionary.
                let output = PlanPDFRenderer().render(legacy, paper: paper)
                let text = normalized(try XCTUnwrap(PDFDocument(data: output.data)?.string))
                for detail in expected { XCTAssertTrue(text.contains(normalized(detail)), "Missing diagram qualification: \(detail)") }
                XCTAssertFalse(text.contains("plan.route.reason."))
            }
        }
    }

    func testFailedRouteStillDrawsTheRecordedStartingRoomMarker() throws {
        let home = SampleHomes.ranch
        var route = EgressPlanner().plan(RouteRequest(startSpaceID: "sp-bed1"), in: home)
        route.primary = nil; route.alternative = nil; route.alternativeStatus = .none; route.noRouteReason = .blockedByScenario
        let floorID = try XCTUnwrap(HomeScenePresentation.startingRoom(in: home, route: route)?.floorID)
        XCTAssertNotNil(HomeScenePresentation.startingRoomPosition(in: home, route: route))
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        func image(selected: RouteResult?) -> Data? {
            UIGraphicsImageRenderer(size: bounds.size).image { context in
                UIColor.white.setFill(); context.fill(bounds)
                PlanPDFRenderer.drawHome(home, floorID: floorID, routes: [], selectedRoute: selected, rect: bounds)
            }.pngData()
        }
        // The original rendering produced identical diagrams when a current route was unavailable.
        // A room marker must remain visible even when there are no path legs to draw.
        XCTAssertNotEqual(try XCTUnwrap(image(selected: route)), try XCTUnwrap(image(selected: nil)))
    }
}
