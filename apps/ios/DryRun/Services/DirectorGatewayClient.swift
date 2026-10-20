import Foundation
import DryRunCore

/// Development transport to the private AI gateway (services/ai-orchestrator) for the adaptive exercise director.
///
/// Configured only by launch arguments on a wired development device (`-aiGateway <url> -aiGatewayToken <token>`), in
/// DEBUG builds. Nothing is stored, compiled in or offered as a setting, and the Gemini key never reaches the phone:
/// the token is the gateway's local fixture credential. Production needs the App Attest handshake (mac-integration-
/// handoff.md) before any real household can be sent; until then only fictional households use it.
struct DirectorGatewayClient: Sendable {
    let baseURL: URL
    let token: String

    static let current: DirectorGatewayClient? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let raw = value("-aiGateway"), let url = URL(string: raw), ["http", "https"].contains(url.scheme ?? ""),
              let token = value("-aiGatewayToken"), token.count >= 24 else { return nil }
        return DirectorGatewayClient(baseURL: url, token: token)
        #else
        return nil
        #endif
    }()

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
    }

    private struct Continuation: Encodable {
        let token: String
        let binding: AgentContextBinding
        let callID: String
        let result: DirectorGatewayBridge.ToolResult
    }

    func start(_ request: DirectorGatewayBridge.OperationRequest) async -> Outcome {
        await post("v1/operations", request)
    }

    func resume(token: String, binding: AgentContextBinding, callID: String, result: DirectorGatewayBridge.ToolResult) async -> Outcome {
        await post("v1/continue", Continuation(token: token, binding: binding, callID: callID, result: result))
    }

    enum PreparationOutcome: Sendable {
        case completed(PreparationFeatureBridge.Output, householdRevision: Int)
        case unavailable(String)
    }

    /// One `preparation` feature turn: Gemini selects, orders and explains up to three preparations. The answer is
    /// only a proposal; `PreparationFeatureBridge.accept` decides what the Prepare tab may show.
    func preparation(_ request: PreparationFeatureBridge.Request) async -> PreparationOutcome {
        struct Response: Decodable {
            let status: String; let reason: String?; let householdRevision: Int?; let proposal: PreparationFeatureBridge.Output?
        }
        switch await send("v1/features", request) {
        case .failure(let failure): return .unavailable(failure.reason)
        case .success(let data):
            guard let decoded = try? DryRunJSON.decoder().decode(Response.self, from: data) else { return .unavailable("decode") }
            guard decoded.status == "completed", let proposal = decoded.proposal, let revision = decoded.householdRevision else {
                return .unavailable(decoded.reason ?? decoded.status)
            }
            return .completed(proposal, householdRevision: revision)
        }
    }

    /// Best effort: the gateway also disposes the job when the connection drops or its TTL passes.
    func cancel(token: String) async {
        struct Cancel: Encodable { let token: String }
        _ = await post("v1/cancel", Cancel(token: token))
    }

    private func post(_ path: String, _ body: some Encodable) async -> Outcome {
        switch await send(path, body) {
        case .failure(let failure): return .unavailable(failure.reason)
        case .success(let data):
            guard let decoded = try? DryRunJSON.decoder().decode(Response.self, from: data) else { return .unavailable("decode") }
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

    private struct TransportFailure: Error { let reason: String }

    /// POSTs one JSON body and returns the 200 response body; failures are reduced to a short code for the UI.
    private func send(_ path: String, _ body: some Encodable) async -> Result<Data, TransportFailure> {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent(path))
            request.httpMethod = "POST"
            request.timeoutInterval = 95
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            request.httpBody = try encoder.encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .failure(.init(reason: "http \(status)")) }
            return .success(data)
        } catch is CancellationError {
            return .failure(.init(reason: "cancelled"))
        } catch let error as URLError {
            // Transport detail (hosts, paths) stays out of the UI and logs; the numeric code is enough to diagnose.
            return .failure(.init(reason: "transport \(error.code.rawValue)"))
        } catch {
            return .failure(.init(reason: "encode"))
        }
    }
}
