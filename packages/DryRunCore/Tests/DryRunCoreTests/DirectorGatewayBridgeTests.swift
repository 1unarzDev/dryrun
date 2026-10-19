import Foundation
import Testing
@testable import DryRunCore

/// Writes the native director requests and tool results the iPhone sends, so the gateway's own Zod schemas can
/// parse them (services/ai-orchestrator/test/native-bridge.test.ts). Fixed date and IDs keep the files stable.
@Suite("Native director gateway bridge") struct DirectorGatewayBridgeTests {
    static let date = Date(timeIntervalSince1970: 1_792_000_000)
    static let output = SimFixtures.repoRoot.appendingPathComponent("fixtures/ai/native-bridge", isDirectory: true)

    func write(_ name: String, _ value: some Encodable) throws -> String {
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        let data = try DryRunJSON.encoder().encode(value)
        try data.write(to: Self.output.appendingPathComponent(name))
        return String(decoding: data, as: UTF8.self)
    }

    /// A session one local-director turn in, as the phone has it before asking Gemini for the next turn.
    func session(_ scenarioID: String, home: HomeModel) throws -> (SimulationSession, SessionReceipt) {
        let library = SimFixtures.library
        var session = try SimulationSession.initialize(id: "native-\(scenarioID)", initial: SimFixtures.input(SampleHouseholds.oak, scenarioID, home: home), library: library)
        var receipt = try session.query(library: library)
        let first = try #require(LocalDirector.nextCommit(session: session, receipt: receipt, library: library))
        receipt = try session.commit(first, library: library)
        if receipt.directorState?.awaitingUserAction == true, let choice = LocalDirector.dueChoice(session: session, receipt: receipt, library: library) {
            receipt = try session.commit(.init(id: "user-1", actor: "user", baseRevision: session.revision,
                                               commands: [.init(kind: "choose", target: choice.id, value: choice.options[0].id)]), library: library)
        }
        return (session, receipt)
    }

    @Test(arguments: [("home-fire", "apartment-complex"), ("water-outage", "ranch")])
    func requestsAreMinimizedAndRecorded(_ scenarioID: String, _ homeName: String) throws {
        let home = homeName == "ranch" ? SampleHomes.ranch : SampleHomes.apartmentComplex
        let (session, receipt) = try session(scenarioID, home: home)
        let request = try DirectorGatewayBridge.operationRequest(requestID: "native-\(scenarioID)-1", session: session, receipt: receipt,
                                                                 library: SimFixtures.library, at: Self.date)
        let json = try write("director-request-\(scenarioID).json", request)
        #expect(request.synthetic && request.role == "director")
        #expect(request.context.binding.revision == session.revision)
        // Names, phone numbers, addresses and free-text notes never leave the device in a director request.
        let h = session.initial.household
        for secret in [h.displayName] + h.contacts.compactMap(\.phone) + h.contacts.map(\.alias) + h.people.map(\.alias) where !secret.isEmpty {
            #expect(!json.contains(secret), "leaked \(secret)")
        }
        #expect(!json.contains("addressLine"))
    }

    @Test func toolResultsMatchTheWhitelistAndBindToTheRevision() throws {
        let library = SimFixtures.library
        let (session, receipt) = try session("home-fire", home: SampleHomes.apartmentComplex)
        let binding = AgentContextBinding(receipt: receipt, householdRevision: session.initial.household.revision, homeRevision: session.initial.home?.revision ?? 0)
        let next = try #require(LocalDirector.nextCommit(session: session, receipt: receipt, library: library))
        let calls: [DirectorGatewayBridge.ToolCall] = [
            .init(id: "c1", name: "evaluateCandidateAction", arguments: .init(commands: next.commands)),
            .init(id: "c2", name: "inspectScene", arguments: .init()),
            .init(id: "c3", name: "queryRoutes", arguments: .init()),
            .init(id: "c4", name: "evaluateResources", arguments: .init()),
            .init(id: "c5", name: "inspectDependencies", arguments: .init()),
            .init(id: "c6", name: "runCounterfactual", arguments: .init(profileIDs: ["evt.home-fire.alarm", "evt.home-fire.fire-origin"])),
        ]
        for call in calls {
            let result = try DirectorGatewayBridge.execute(call, session: session, binding: binding, library: library)
            #expect(result.binding == binding)
            #expect((result.preview != nil) == (call.name == "evaluateCandidateAction"))
            _ = try write("tool-result-\(call.name).json", result)
        }
        // A tool request never changes the session and is refused for any other revision or tool name.
        #expect(try session.query(library: library) == receipt)
        var stale = binding; stale.revision += 1
        #expect(throws: SessionError.self) { try DirectorGatewayBridge.execute(calls[2], session: session, binding: stale, library: library) }
        #expect(throws: SessionError.self) {
            try DirectorGatewayBridge.execute(.init(id: "x", name: "commitAnything", arguments: .init()), session: session, binding: binding, library: library)
        }
        #expect(throws: SessionError.self) {
            try DirectorGatewayBridge.execute(.init(id: "y", name: "evaluateCandidateAction", arguments: .init(command: next.commands[0], commands: next.commands)),
                                              session: session, binding: binding, library: library)
        }
    }

    @Test func noRequestIsBuiltWhileTheFamilyMustAct() throws {
        let library = SimFixtures.library
        var session = try SimulationSession.initialize(id: "await", initial: SimFixtures.input(SampleHouseholds.oak, "home-fire"), library: library)
        var receipt = try session.query(library: library)
        while receipt.directorState?.awaitingUserAction != true {
            receipt = try session.commit(try #require(LocalDirector.nextCommit(session: session, receipt: receipt, library: library)), library: library)
        }
        #expect(throws: SessionError.self) {
            try DirectorGatewayBridge.operationRequest(requestID: "r", session: session, receipt: receipt, library: library)
        }
    }
}
