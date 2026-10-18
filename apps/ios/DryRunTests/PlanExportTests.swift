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
}
