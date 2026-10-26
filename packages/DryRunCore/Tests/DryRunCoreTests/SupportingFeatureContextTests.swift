import Foundation
import Testing
@testable import DryRunCore

@Suite("Private supporting features retain canonical authorized context")
struct SupportingFeatureContextTests {
    private let date = Date(timeIntervalSince1970: 1792497600)

    @Test func resourcePlanningRetainsPrivateFactsWithoutChangingPublicSearchPlans() throws {
        let household = SampleHouseholds.oak
        var home = SampleHomes.ranch; home.id = household.stableHomeID
        let state = IntegratedAIState()
        let rubric = try DryRunJSON.decoder().decode(RubricDefinition.self,
            from: Data(contentsOf: SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
        let tasks = PreparationTaskCatalog.build(household: household, home: home, rubric: rubric, at: date)
        let base = ResourceStrategyBridge.request(requestID: "public-compatible", household: household, tasks: tasks, gaps: [], at: date)
        let request = try ResourceStrategyBridge.authorizedRequest(requestID: "authored-resources", household: household,
            home: home, tasks: tasks, gaps: [], state: state, places: [], scopeSessionID: "resource-scope", locale: "es", at: date)
        let actualTasks = try DryRunJSON.encoder().encode(request.context.tasks)
        let baselineTasks = try DryRunJSON.encoder().encode(base.context.tasks)
        #expect(actualTasks == baselineTasks)
        #expect(request.context.locale == "es")
        #expect(request.context.contextBinding == request.context.privateContext?.binding)
        let context = try #require(request.context.privateContext)
        #expect(context.records.contains { $0.sourcePath == "person.\(household.people[0].id)" })
        #expect(context.records.contains { $0.sourcePath == "geometry" })
        let changed = try ResourceStrategyBridge.authorizedRequest(requestID: "authored-resources-2", household: household,
            home: home, tasks: tasks, gaps: [], state: state, places: [], scopeSessionID: "different-scope", locale: "es", at: date)
        #expect(changed.context.contextBinding != request.context.contextBinding)
        try export(request, name: "resources")
    }

    @Test func photoReviewBindsFullContextAndExactImageManifest() throws {
        let household = SampleHouseholds.oak
        var home = SampleHomes.ranch; home.id = household.stableHomeID
        let rubric = try DryRunJSON.decoder().decode(RubricDefinition.self,
            from: Data(contentsOf: SimFixtures.repoRoot.appendingPathComponent("content/ai/rubric-v0.json")))
        let bytes = Data("Authored synthetic image contract bytes; not a real photograph".utf8)
        let manifest = RoomImageManifest(id: "authored-image", homeRevision: home.revision, roomID: home.spaces.first?.id,
            digest: "d30315781045e2ec84ca3bc2f57475d851f2e6cb7d364792f59cad8b2359d188", capturedAt: date, width: 100, height: 100, orientation: "up", calibration: "none", transforms: [], redactedRegions: [])
        let request = try HomeReviewBridge.request(requestID: "authored-home", household: household, home: home, rubric: rubric,
            manifest: manifest, bytes: bytes, mimeType: "image/jpeg", at: date, state: IntegratedAIState(),
            scopeSessionID: "photo-scope", locale: "vi")
        #expect(request.context.locale == "vi")
        #expect(request.context.contextBinding == request.context.privateContext?.binding)
        #expect(request.context.privateContext?.records.contains { $0.sourcePath == "person.\(household.people[0].id)" } == true)
        #expect(request.images.first?.data == bytes.base64EncodedString())
        #expect(request.context.images.first?.manifest == manifest)
        try export(request, name: "home")
    }

    private func export(_ value: some Encodable, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["DRYRUN_SUPPORTING_INPUT_EXPORT_DIR"] else { return }
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try DryRunJSON.encoder().encode(value).write(to: folder.appendingPathComponent(name + ".json"), options: .atomic)
    }
}
