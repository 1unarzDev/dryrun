import Foundation
import CryptoKit
import DryRunCore

/// Development transport to the private AI gateway (services/ai-orchestrator) for Beacon, the app's assistant.
///
/// DEBUG builds only. Configured by launch arguments on a wired device (`-aiGateway <url> -aiGatewayToken <token>`) or,
/// so the app works when opened from the home screen, by `BeaconGateway.json` that `scripts/mac/beacon-gateway.sh`
/// writes into the (git-ignored) app resources from the Mac's `.env`. The Gemini key never reaches the phone: the token
/// is the gateway's local fixture credential. The preserved App Attest option signs in with a synthetic-scoped
/// session. Real-household authorization and durable deployment state remain separate requirements.
struct DirectorGatewayClient: Sendable {
    let baseURL: URL
    enum Credential: Sendable { case fixture(String), attest(AppAttestSession) }
    let credential: Credential

    static let current: DirectorGatewayClient? = {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["DRYRUN_SYNTHETIC_GATEWAY_URL"],
           let token = environment["DRYRUN_SYNTHETIC_GATEWAY_TOKEN"] { return make(raw, token) }
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let raw = value("-aiGateway"), let token = value("-aiGatewayToken") { return make(raw, token) }
        if let raw = value("-aiGateway"), let url = URL(string: raw),
           ["http", "https"].contains(url.scheme ?? ""), args.contains("-aiGatewayAttest") {
            return DirectorGatewayClient(baseURL: url, credential: .attest(AppAttestSession(baseURL: url)))
        }
        // UI tests that must not reach a gateway pass -noBeaconConfig.
        guard !args.contains("-noBeaconConfig") else { return nil }
        struct LocalConfig: Decodable { let url: String; let token: String }
        guard let file = Bundle.main.url(forResource: "BeaconGateway", withExtension: "json"),
              let data = try? Data(contentsOf: file),
              let config = try? JSONDecoder().decode(LocalConfig.self, from: data) else { return nil }
        return make(config.url, config.token)
        #else
        return nil
        #endif
    }()

    private static func make(_ raw: String, _ token: String) -> DirectorGatewayClient? {
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme ?? ""), token.count >= 24 else { return nil }
        return DirectorGatewayClient(baseURL: url, credential: .fixture(token))
    }

    private func authorization() async throws -> String {
        switch credential {
        case .fixture(let token): return "Bearer \(token)"
        case .attest(let session): return "Bearer \(try await session.bearer())"
        }
    }

    struct ToolCall: Decodable, Sendable { let id: String; let name: String; let arguments: DirectorGatewayBridge.ToolArguments }

    enum Outcome: Sendable {
        case completed(DirectorProposal)
        case needsTools(token: String, binding: AgentContextBinding, call: DirectorGatewayBridge.ToolCall)
        case needsUserAction
        case unavailable(String)
    }

    private struct Response: Decodable {
        let status: String
        let reason: String?
        let token: String?
        let binding: AgentContextBinding?
        let calls: [ToolCall]?
        let proposal: DirectorProposal?
        let contextBinding: AuthorizedAIContext.Binding?
    }

    private struct Continuation: Encodable {
        let token: String
        let binding: AgentContextBinding
        let callID: String
        let result: DirectorGatewayBridge.ToolResult
    }

    func start(_ request: DirectorGatewayBridge.OperationRequest) async -> Outcome {
        await post("v1/operations", request, expectedContextBinding: request.context.contextBinding)
    }

    func resume(token: String, binding: AgentContextBinding, callID: String, result: DirectorGatewayBridge.ToolResult,
                expectedContextBinding: AuthorizedAIContext.Binding? = nil) async -> Outcome {
        await post("v1/continue", Continuation(token: token, binding: binding, callID: callID, result: result), expectedContextBinding: expectedContextBinding)
    }

    enum PhotoReviewOutcome: Sendable {
        case reviewed(HomeReviewBridge.Response)
        case unavailable(String)
    }

    /// Private resource planning; public discovery is a separately minimized server operation.
    func planResources(_ request: ResourceStrategyBridge.Request) async -> Result<ResourceStrategyBridge.Response, ReasonError> {
        let result: Result<ResourceStrategyBridge.Response, ReasonError> = await postFeatures(request, timeout: 70)
        if case .success(let response) = result,
           response.requestID != request.requestID || response.contextBinding != request.context.contextBinding {
            return .failure(ReasonError(reason: "binding"))
        }
        return result
    }

    struct ReasonError: Error { let reason: String }

    private func postFeatures<T: Decodable>(_ body: some Encodable, timeout: TimeInterval) async -> Result<T, ReasonError> {
        do {
            var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v1/features"))
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = timeout
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue(try await authorization(), forHTTPHeaderField: "Authorization")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            urlRequest.httpBody = try encoder.encode(body)
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            try Task.checkCancellation()
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .failure(ReasonError(reason: "http \(status)")) }
            guard data.count <= 1_000_000 else { return .failure(ReasonError(reason: "response_budget")) }
            return .success(try DryRunJSON.decoder().decode(T.self, from: data))
        } catch let error as URLError {
            return .failure(ReasonError(reason: "transport \(error.code.rawValue)"))
        } catch is CancellationError {
            return .failure(ReasonError(reason: "cancelled"))
        } catch {
            return .failure(ReasonError(reason: SignInReason(error)?.text ?? "decode"))
        }
    }

    /// Optional room-photo review (role `home`). The photo bytes go only in this request; nothing is retained here.
    func reviewPhoto(_ request: HomeReviewBridge.Request) async -> PhotoReviewOutcome {
        switch await postFeatures(request, timeout: 70) as Result<HomeReviewBridge.Response, ReasonError> {
        case .success(let decoded):
            guard decoded.requestID == request.requestID, decoded.contextBinding == request.context.contextBinding else { return .unavailable("binding") }
            return decoded.status == "completed" ? .reviewed(decoded) : .unavailable(decoded.status)
        case .failure(let error): return .unavailable(error.reason)
        }
    }

    enum PreparationOutcome: Sendable {
        /// `replay` marks a recorded Beacon answer used because the gateway or its provider was unavailable.
        case completed(PreparationFeatureBridge.Output, householdRevision: Int, replay: Bool)
        case unavailable(String)
    }

    private struct PreparationResponse: Decodable {
        let status: String; let reason: String?; let requestID: String?; let householdRevision: Int?; let contextBinding: AuthorizedAIContext.Binding?; let proposal: PreparationFeatureBridge.Output?
    }

    /// One `preparation` feature turn: Beacon selects, orders and explains up to three preparations. The answer is
    /// only a proposal; `PreparationFeatureBridge.accept` decides what the Prepare tab may show.
    func preparation(_ request: PreparationFeatureBridge.Request, householdID: String) async -> PreparationOutcome {
        let outcome: PreparationOutcome
        var sent = await send("v1/features", request)
        // The first request after launch can fail while iOS is still granting Local Network access (-1009); one retry.
        if case .failure(let failure) = sent, failure.reason.hasPrefix("transport") {
            do { try await Task.sleep(for: .seconds(2)) } catch { return .unavailable("cancelled") }
            guard !Task.isCancelled else { return .unavailable("cancelled") }
            sent = await send("v1/features", request)
        }
        switch sent {
        case .failure(let failure): outcome = .unavailable(failure.reason)
        case .success(let data):
            guard let decoded = try? DryRunJSON.decoder().decode(PreparationResponse.self, from: data) else { return .unavailable("decode") }
            guard decoded.status == "completed", decoded.requestID == request.requestID, decoded.contextBinding == request.context.contextBinding,
                  let proposal = decoded.proposal, let revision = decoded.householdRevision, revision == request.context.household.revision else {
                outcome = .unavailable(decoded.reason ?? decoded.status)
                break
            }
            #if DEBUG
            Self.keepRecording(data, name: "preparation-\(householdID)", request: request)
            #endif
            return .completed(proposal, householdRevision: revision, replay: false)
        }
        guard case .unavailable(let reason) = outcome, Self.replayable(reason),
              let recorded = Self.recordedPreparation(householdID: householdID, request: request) else { return outcome }
        return .completed(recorded, householdRevision: request.context.household.revision, replay: true)
    }

    enum DebriefOutcome: Sendable {
        case completed(DebriefFeatureBridge.Output, replay: Bool)
        case unavailable(String)
    }

    private struct DebriefResponse: Decodable { let status: String; let reason: String?; let requestID: String?; let contextBinding: AuthorizedAIContext.Binding?; let proposal: DebriefFeatureBridge.Output? }

    /// One `debrief` turn after a finished rehearsal. Same transport, retry, recording and replay rules as Prepare.
    func debrief(_ request: PreparationFeatureBridge.Request, householdID: String, scenarioID: String) async -> DebriefOutcome {
        var sent = await send("v1/features", request)
        if case .failure(let failure) = sent, failure.reason.hasPrefix("transport") {
            do { try await Task.sleep(for: .seconds(2)) } catch { return .unavailable("cancelled") }
            guard !Task.isCancelled else { return .unavailable("cancelled") }
            sent = await send("v1/features", request)
        }
        let name = "debrief-\(householdID)-\(scenarioID)"
        var reason: String
        switch sent {
        case .failure(let failure): reason = failure.reason
        case .success(let data):
            guard let decoded = try? DryRunJSON.decoder().decode(DebriefResponse.self, from: data) else { return .unavailable("decode") }
            if decoded.status == "completed", decoded.requestID == request.requestID, decoded.contextBinding == request.context.contextBinding, let proposal = decoded.proposal {
                #if DEBUG
                Self.keepRecording(data, name: name, request: request)
                #endif
                return .completed(proposal, replay: false)
            }
            reason = decoded.reason ?? decoded.status
        }
        guard Self.replayable(reason), householdID.hasPrefix("hh-"),
              let data = Self.recordedData(name: name, request: request),
              let recorded = try? DryRunJSON.decoder().decode(DebriefResponse.self, from: data),
              recorded.status == "completed", recorded.contextBinding == request.context.contextBinding, let proposal = recorded.proposal else { return .unavailable(reason) }
        return .completed(proposal, replay: true)
    }

    private struct DrillSetupResponse: Decodable { let status: String; let reason: String?; let requestID: String?; let contextBinding: AuthorizedAIContext.Binding?; let proposal: DrillSetupBridge.Output? }

    /// One `drillSetup` turn before a rehearsal starts. Same retry, recording and replay rules as the other features.
    func drillSetup(_ request: PreparationFeatureBridge.Request, householdID: String, scenarioID: String) async -> Result<(DrillSetupBridge.Output, replay: Bool), TransportFailure> {
        var sent = await send("v1/features", request)
        if case .failure(let failure) = sent, failure.reason.hasPrefix("transport") {
            do { try await Task.sleep(for: .seconds(2)) } catch { return .failure(.init(reason: "cancelled")) }
            guard !Task.isCancelled else { return .failure(.init(reason: "cancelled")) }
            sent = await send("v1/features", request)
        }
        let name = "drill-\(householdID)-\(scenarioID)"
        var reason = "decode"
        switch sent {
        case .failure(let failure): reason = failure.reason
        case .success(let data):
            if let decoded = try? DryRunJSON.decoder().decode(DrillSetupResponse.self, from: data) {
                if decoded.status == "completed", decoded.requestID == request.requestID, decoded.contextBinding == request.context.contextBinding, let proposal = decoded.proposal {
                    #if DEBUG
                    Self.keepRecording(data, name: name, request: request)
                    #endif
                    return .success((proposal, false))
                }
                reason = decoded.reason ?? decoded.status
            }
        }
        guard Self.replayable(reason), householdID.hasPrefix("hh-"),
              let data = Self.recordedData(name: name, request: request),
              let recorded = try? DryRunJSON.decoder().decode(DrillSetupResponse.self, from: data),
              recorded.status == "completed", recorded.contextBinding == request.context.contextBinding, let proposal = recorded.proposal else { return .failure(.init(reason: reason)) }
        return .success((proposal, true))
    }

    /// Provider overload, quota, timeouts and an unreachable gateway replay a recording; a malformed or rejected
    /// answer does not (that would hide a real defect behind a canned one).
    static func replayable(_ reason: String) -> Bool {
        reason.hasPrefix("transport") || reason.hasPrefix("http 5") || reason == "http 429" || reason == "http 0"
            || reason.hasPrefix("provider_") || reason == "spend_budget" || reason == "operation_budget"
    }

    #if DEBUG
    /// Development only: the last live answer per fictional household, in Documents/beacon-recordings, which
    /// scripts/mac/pull-beacon-replays.sh copies into content/ai/replay for the replay fallback.
    private static func keepRecording(_ data: Data, name: String, request: PreparationFeatureBridge.Request) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("beacon-recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let digest = requestDigest(request),
              let binding = try? JSONEncoder().encode(ReplayBinding(requestDigest: digest)) else { return }
        try? data.write(to: folder.appendingPathComponent("\(name).json"), options: .atomic)
        try? binding.write(to: folder.appendingPathComponent("\(name).binding.json"), options: .atomic)
    }
    #endif

    /// A Beacon answer recorded live for a fictional sample household (content/ai/replay). It still goes through
    /// `PreparationFeatureBridge.accept`, so items that no longer match this household's list are refused.
    static func recordedPreparation(householdID: String, request: PreparationFeatureBridge.Request) -> PreparationFeatureBridge.Output? {
        guard householdID.hasPrefix("hh-"),
              let data = recordedData(name: "preparation-\(householdID)", request: request),
              let decoded = try? DryRunJSON.decoder().decode(PreparationResponse.self, from: data),
              decoded.status == "completed", decoded.contextBinding == request.context.contextBinding else { return nil }
        return decoded.proposal
    }

    /// Old ID-only recordings remain preserved, but cannot stand in for changed household facts.
    private struct ReplayBinding: Codable { let requestDigest: String }
    private static func requestDigest(_ request: PreparationFeatureBridge.Request) -> String? {
        guard let data = try? DryRunJSON.encoder().encode(request),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        object.removeValue(forKey: "requestID")
        guard let canonical = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }
    private static func recordedData(name: String, request: PreparationFeatureBridge.Request) -> Data? {
        guard !Task.isCancelled, let expected = requestDigest(request),
              let bindingURL = Bundle.main.url(forResource: "content/ai/replay/\(name).binding", withExtension: "json"),
              let bindingData = try? Data(contentsOf: bindingURL),
              let binding = try? JSONDecoder().decode(ReplayBinding.self, from: bindingData),
              binding.requestDigest == expected,
              let url = Bundle.main.url(forResource: "content/ai/replay/\(name)", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Unauthenticated, data-free GET /health. The gateway script watches for it to confirm this phone reaches the Mac.
    func ping() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 6
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Best effort: the gateway also disposes the job when the connection drops or its TTL passes.
    func cancel(token: String) async {
        struct Cancel: Encodable { let token: String }
        _ = await post("v1/cancel", Cancel(token: token))
    }

    private func post(_ path: String, _ body: some Encodable, expectedContextBinding: AuthorizedAIContext.Binding? = nil) async -> Outcome {
        switch await send(path, body) {
        case .failure(let failure): return .unavailable(failure.reason)
        case .success(let data):
            guard let decoded = try? DryRunJSON.decoder().decode(Response.self, from: data) else { return .unavailable("decode") }
            guard decoded.contextBinding == expectedContextBinding else { return .unavailable("context_mismatch") }
            switch decoded.status {
            case "completed":
                guard let proposal = decoded.proposal else { return .unavailable("missing_proposal") }
                return .completed(proposal)
            case "needs_client_tools":
                guard let token = decoded.token, let binding = decoded.binding, let call = decoded.calls?.first, decoded.calls?.count == 1 else {
                    return .unavailable("invalid_tool_request")
                }
                return .needsTools(token: token, binding: binding, call: .init(id: call.id, name: call.name, arguments: call.arguments))
            case "needs_user_action": return .needsUserAction
            default: return .unavailable(decoded.reason ?? decoded.status)
            }
        }
    }

    struct TransportFailure: Error { let reason: String }

    /// POSTs one JSON body and returns the 200 response body; failures are reduced to a short code for the UI.
    private func send(_ path: String, _ body: some Encodable) async -> Result<Data, TransportFailure> {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent(path))
            request.httpMethod = "POST"
            request.timeoutInterval = 95
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(try await authorization(), forHTTPHeaderField: "Authorization")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            request.httpBody = try encoder.encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .failure(.init(reason: "http \(status)")) }
            guard data.count <= 1_000_000 else { return .failure(.init(reason: "response_budget")) }
            return .success(data)
        } catch is CancellationError {
            return .failure(.init(reason: "cancelled"))
        } catch let error as URLError {
            // Transport detail (hosts, paths) stays out of the UI and logs; the numeric code is enough to diagnose.
            return .failure(.init(reason: "transport \(error.code.rawValue)"))
        } catch {
            return .failure(.init(reason: SignInReason(error)?.text ?? "encode"))
        }
    }
}

/// App Attest sign-in failures, reported without detail beyond a code (no keys, challenges or tokens).
struct SignInReason {
    let text: String
    init?(_ error: Error) {
        if let e = error as? AppAttestSession.SignInError {
            switch e { case .unsupported: text = "sign-in unsupported"; case .server(let s): text = "sign-in \(s)"; case .invalidResponse: text = "sign-in response" }
        } else if (error as NSError).domain == "com.apple.devicecheck.error" {
            text = "sign-in devicecheck \((error as NSError).code)"
        } else { return nil }
    }
}
