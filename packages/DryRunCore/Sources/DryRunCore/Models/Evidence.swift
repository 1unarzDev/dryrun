import Foundation

/// Where a value came from. A scanned category confidence is never proof of exit safety,
/// centimetre accuracy, operability, or code compliance.
public enum EvidenceOrigin: String, Codable, Sendable, Hashable, CaseIterable {
    case userConfirmed
    case scanObserved
    case officialSource
    case derived
    case scenarioAssumption
    case unknown
}

public enum EvidenceStatus: String, Codable, Sendable, Hashable, CaseIterable {
    /// The household (or an official source) confirmed this value.
    case confirmed
    /// A value exists but has not been confirmed (e.g. scan-proposed).
    case needsVerification
    /// Exercise or scenario assumption, stated explicitly.
    case assumed
    /// No value. Unknown is never treated as "no" or as a default.
    case unknown
}

/// A value with explicit provenance. `value == nil` means unknown; nothing is invented.
public struct EvidenceValue<Value: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    public var value: Value?
    public var origin: EvidenceOrigin
    public var status: EvidenceStatus
    public var sourceIDs: [String]
    public var inputIDs: [String]
    public var recordedAt: Date?
    public var verifiedAt: Date?
    public var unit: String?

    public init(
        value: Value?,
        origin: EvidenceOrigin,
        status: EvidenceStatus,
        sourceIDs: [String] = [],
        inputIDs: [String] = [],
        recordedAt: Date? = nil,
        verifiedAt: Date? = nil,
        unit: String? = nil
    ) {
        self.value = value
        self.origin = origin
        self.status = value == nil ? .unknown : status
        self.sourceIDs = sourceIDs
        self.inputIDs = inputIDs
        self.recordedAt = recordedAt
        self.verifiedAt = verifiedAt
        self.unit = unit
    }

    public static var unknown: EvidenceValue { EvidenceValue(value: nil, origin: .unknown, status: .unknown) }

    public static func confirmed(_ value: Value, unit: String? = nil, verifiedAt: Date? = nil) -> EvidenceValue {
        EvidenceValue(value: value, origin: .userConfirmed, status: .confirmed, verifiedAt: verifiedAt, unit: unit)
    }

    public static func assumed(_ value: Value, unit: String? = nil) -> EvidenceValue {
        EvidenceValue(value: value, origin: .scenarioAssumption, status: .assumed, unit: unit)
    }

    public static func scanned(_ value: Value, unit: String? = nil) -> EvidenceValue {
        EvidenceValue(value: value, origin: .scanObserved, status: .needsVerification, unit: unit)
    }

    private enum CodingKeys: String, CodingKey {
        case value, origin, status, sourceIDs, inputIDs, recordedAt, verifiedAt, unit
    }

    /// Lenient decoding: omitted arrays default to empty; a missing value always decodes as unknown.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let value = try c.decodeIfPresent(Value.self, forKey: .value)
        self.init(
            value: value,
            origin: try c.decodeIfPresent(EvidenceOrigin.self, forKey: .origin) ?? .unknown,
            status: try c.decodeIfPresent(EvidenceStatus.self, forKey: .status) ?? .unknown,
            sourceIDs: try c.decodeIfPresent([String].self, forKey: .sourceIDs) ?? [],
            inputIDs: try c.decodeIfPresent([String].self, forKey: .inputIDs) ?? [],
            recordedAt: try c.decodeIfPresent(Date.self, forKey: .recordedAt),
            verifiedAt: try c.decodeIfPresent(Date.self, forKey: .verifiedAt),
            unit: try c.decodeIfPresent(String.self, forKey: .unit)
        )
    }

    public var isKnown: Bool { value != nil }
    /// Only confirmed values may satisfy a hard requirement (exit, backup compatibility, ...).
    public var isConfirmed: Bool { value != nil && status == .confirmed }
    /// The value if and only if it has been confirmed.
    public var confirmedValue: Value? { isConfirmed ? value : nil }
}

/// Shared JSON coding so fixtures, the app, and contract tests agree on formats.
public enum DryRunJSON {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
