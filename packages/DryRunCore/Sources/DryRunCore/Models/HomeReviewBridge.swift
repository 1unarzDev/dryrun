import Foundation

/// Native side of the gateway's optional room-photo review (`POST /v1/features`, role `home`): the strict request built
/// from the household snapshot, the home scene and one minimized photo the family chose to send. Only the manifest and
/// the exact submitted bytes leave the device; no capture pose, depth or location. Returned concerns are proposals
/// for review (`IntegratedAIState.reviewConcern`), never facts.
public enum HomeReviewBridge {
    /// The gateway requires the `roomID` key to be present, so `nil` encodes as JSON null instead of being omitted.
    public struct ManifestJSON: Encodable, Sendable {
        public let manifest: RoomImageManifest
        enum CodingKeys: String, CodingKey { case id, homeRevision, roomID, digest, capturedAt, width, height, orientation, transforms, calibration, redactedRegions }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(manifest.id, forKey: .id); try c.encode(manifest.homeRevision, forKey: .homeRevision)
            if let room = manifest.roomID { try c.encode(room, forKey: .roomID) } else { try c.encodeNil(forKey: .roomID) }
            try c.encode(manifest.digest, forKey: .digest); try c.encode(manifest.capturedAt, forKey: .capturedAt)
            try c.encode(manifest.width, forKey: .width); try c.encode(manifest.height, forKey: .height)
            try c.encode(manifest.orientation, forKey: .orientation); try c.encode(manifest.transforms, forKey: .transforms)
            try c.encode(manifest.calibration, forKey: .calibration); try c.encode(manifest.redactedRegions, forKey: .redactedRegions)
        }
    }
    public struct ImagePayload: Codable, Sendable { public var id: String; public var mimeType: String; public var data: String }
    public struct Context: Encodable, Sendable {
        public var household: HouseholdContextSnapshot
        public var tasks: [PreparationTaskProposal] = []
        public var gaps: [SupplyGap] = []
        public var allowedActionIDs: [String]
        public var allowedCriterionIDs: [String] = []
        public var scene: HomeSceneContext
        public var images: [ManifestJSON]
        public var locale: String?
        public var privateContext: AuthorizedAIContext?
        public var contextBinding: AuthorizedAIContext.Binding?
    }
    public struct Request: Encodable, Sendable {
        public var contractVersion = "dryrun.ai/1"
        public var requestID: String
        public var synthetic = true
        public var role = "home"
        public var context: Context
        public var images: [ImagePayload]
        public var providerConsent: [String]?
    }

    public static let maxImageBytes = 1_000_000

    /// One photo's manifest. `digest` must be the SHA-256 (lowercase hex) of exactly `bytes`; transforms list every
    /// resize/rotation/crop actually applied to reach `width`×`height`.
    public static func request(requestID: String, household: HouseholdProfile, home: HomeModel, rubric: RubricDefinition,
                               manifest: RoomImageManifest, bytes: Data, mimeType: String, at date: Date = Date(),
                               state: IntegratedAIState? = nil, places: [SavedPlace] = [], scopeSessionID: String? = nil,
                               locale: String? = nil, currentScorecard: PreparednessScorecard? = nil) throws -> Request {
        guard household.isFictional, bytes.count <= maxImageBytes, ["image/jpeg", "image/png"].contains(mimeType), manifest.homeRevision == home.revision,
              manifest.roomID.map({ home.space($0) != nil }) ?? true,
              manifest.digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw SessionError.invalidCommand }
        // The concern can only link to an existing preparation (for example keeping exits clear).
        let tasks = PreparationTaskCatalog.build(household: household, home: home, rubric: rubric, at: date, includeSatisfied: true)
        let actions = tasks.map(\.actionID)
        var context = Context(household: HouseholdContextSnapshot(household, at: date), allowedActionIDs: Array(Set(actions)).sorted(),
                              scene: HomeSceneContext(home, household: household), images: [ManifestJSON(manifest: manifest)])
        context.locale = locale ?? household.preferredLocale
        context.privateContext = try scopeSessionID.map { try AuthorizedAIContext(household: household, home: home,
            state: state ?? IntegratedAIState(), places: places, tasks: tasks, sessionID: $0,
            cloudPlanningConsent: true, currentScorecard: currentScorecard) }
        context.contextBinding = context.privateContext?.binding
        return Request(requestID: requestID, context: context,
                       images: [ImagePayload(id: manifest.id, mimeType: mimeType, data: bytes.base64EncodedString())], providerConsent: ["gemini"])
    }

    /// The gateway's normalized review proposals, decoded as Core's `HomeConcernProposal`.
    public struct Response: Decodable, Sendable {
        public var status: String
        public var requestID: String?
        public var contextBinding: AuthorizedAIContext.Binding?
        public var reviewProposals: [HomeConcernProposal]?
        public var proposal: Proposal?
        public struct Proposal: Decodable, Sendable { public var concerns: [Concern]?; public var limitations: [String]? }
        public struct Concern: Decodable, Sendable { public var id: String; public var concern: String?; public var confirmationPrompt: String? }
    }
}
