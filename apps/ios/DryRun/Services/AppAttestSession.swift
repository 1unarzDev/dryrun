import CryptoKit
import DeviceCheck
import Foundation
import Security

/// Installation sign-in to the AI gateway with App Attest (services/ai-orchestrator/src/app-attest.ts):
/// one-time key attestation over the server's challenge, then a short-lived session per assertion. Only the key ID is
/// stored (Keychain, this device only); the attested private key never leaves the Secure Enclave, and no household data
/// is part of sign-in. Verified on an iPhone 16 Pro (iOS 26.6.1) with a Personal Team development build: Apple issued a
/// development-environment attestation ("appattestdevelop") that the gateway verified against the pinned Apple root.
/// Production attestations need the App Attest entitlement set to production in a paid team's distribution profile.
actor AppAttestSession {
    enum SignInError: Error { case unsupported, server(String), invalidResponse }

    private let baseURL: URL
    private var token: String?
    private var expiresAt = Date.distantPast
    private static let account = "appattest-key-id"

    init(baseURL: URL) { self.baseURL = baseURL }

    static var isSupported: Bool { DCAppAttestService.shared.isSupported }

    /// A valid session token, signing in again when it is missing or about to expire.
    func bearer() async throws -> String {
        if let token, expiresAt.timeIntervalSinceNow > 60 { return token }
        guard Self.isSupported else { throw SignInError.unsupported }
        let keyID = try await registeredKeyID()
        do {
            return try await startSession(keyID: keyID)
        } catch let error as DCError where error.code == .invalidKey {
            // The key was invalidated (reinstall, OS reset): attest a new one once.
            Self.deleteKeyID()
            return try await startSession(keyID: try await registeredKeyID())
        }
    }

    private func registeredKeyID() async throws -> String {
        if let saved = Self.loadKeyID() { return saved }
        let service = DCAppAttestService.shared
        let keyID = try await service.generateKey()
        let challenge = try await fetchChallenge()
        let attestation = try await service.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
        struct Register: Encodable { let keyId: String; let attestation: String; let challenge: String }
        struct Registered: Decodable { let status: String }
        let result: Registered = try await post("v1/attest/register", Register(keyId: keyID, attestation: attestation.base64EncodedString(), challenge: challenge))
        guard result.status == "registered" else { throw SignInError.invalidResponse }
        Self.saveKeyID(keyID)
        return keyID
    }

    private func startSession(keyID: String) async throws -> String {
        struct ClientData: Encodable { let challenge: String; let keyId: String; let scope: String }
        struct Request: Encodable { let keyId: String; let assertion: String; let clientData: String }
        struct Session: Decodable { let token: String; let expiresAt: Date; let scope: String }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let clientData = try encoder.encode(ClientData(challenge: try await fetchChallenge(), keyId: keyID, scope: "synthetic"))
        let assertion = try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: Data(SHA256.hash(data: clientData)))
        let session: Session = try await post("v1/attest/session", Request(keyId: keyID, assertion: assertion.base64EncodedString(),
                                                                            clientData: clientData.base64EncodedString()))
        guard session.scope == "synthetic", session.token.hasPrefix("v1.") else { throw SignInError.invalidResponse }
        token = session.token; expiresAt = session.expiresAt
        return session.token
    }

    private func fetchChallenge() async throws -> String {
        struct Empty: Encodable {}
        struct Challenge: Decodable { let challenge: String }
        let c: Challenge = try await post("v1/attest/challenge", Empty())
        return c.challenge
    }

    private func post<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SignInError.server("http \(status)") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .custom { d in
            let text = try d.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = f.date(from: text) ?? ISO8601DateFormatter().date(from: text) else { throw SignInError.invalidResponse }
            return date
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: Keychain (key ID only; this device, after first unlock)

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Bundle.main.bundleIdentifier ?? "dryrun",
         kSecAttrAccount as String: account]
    }
    private static func loadKeyID() -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static func saveKeyID(_ keyID: String) {
        deleteKeyID()
        var q = query; q[kSecValueData as String] = Data(keyID.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    private static func deleteKeyID() { SecItemDelete(query as CFDictionary) }
}
