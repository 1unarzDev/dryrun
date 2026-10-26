import Foundation

/// Private, independently sourced planning evidence. Never populated by Gemini, a simulated event,
/// a RoomPlan floor height or a MapKit route. Native adapters resolve the saved location locally.
public struct SiteHazardSource: Codable, Sendable, Hashable {
    public enum Authority: String, Codable, Sendable { case official, household, synthetic }
    public var id: String
    public var authority: Authority
    public var publisher: String
    public var url: String
    public var jurisdictionID: String
    public var retrievedAt: Date
    public var validUntil: Date
    public var reviewed: Bool
    public var datasetVersion: String?
    public var publishedAt: Date?
    public init(id: String, authority: Authority, publisher: String, url: String, jurisdictionID: String,
                retrievedAt: Date, validUntil: Date, reviewed: Bool) {
        self.id=id; self.authority=authority; self.publisher=publisher; self.url=url; self.jurisdictionID=jurisdictionID
        self.retrievedAt=retrievedAt; self.validUntil=validUntil; self.reviewed=reviewed
    }
    public func usable(at date: Date, jurisdictionID: String) -> Bool {
        authority == .official && reviewed && id.range(of:"^[A-Za-z0-9._-]{1,100}$",options:.regularExpression) != nil && id != "household-needs" && !publisher.isEmpty && self.jurisdictionID == jurisdictionID
            && URL(string: url)?.scheme == "https" && URL(string: url)?.host != nil
            && retrievedAt <= date && date <= validUntil && validUntil > retrievedAt
    }
}
public struct SiteElevation: Codable, Sendable, Hashable {
    public enum Surface: String, Codable, Sendable { case terrain, finishedFloor }
    public var meters: Double
    public var uncertaintyMeters: Double
    public var verticalDatum: String
    public var surface: Surface
    public var sourceID: String
    public var horizontalReference: String?
    public var resolutionMeters: Double?
    public init(meters: Double, uncertaintyMeters: Double, verticalDatum: String, surface: Surface, sourceID: String) {
        self.meters=meters; self.uncertaintyMeters=uncertaintyMeters; self.verticalDatum=verticalDatum; self.surface=surface; self.sourceID=sourceID
    }
}
public struct SiteFloodLevel: Codable, Sendable, Hashable {
    public var meters: Double
    public var uncertaintyMeters: Double
    public var verticalDatum: String
    public var sourceID: String
    public init(meters: Double, uncertaintyMeters: Double, verticalDatum: String, sourceID: String) {
        self.meters=meters; self.uncertaintyMeters=uncertaintyMeters; self.verticalDatum=verticalDatum; self.sourceID=sourceID
    }
}
public struct SiteWildfireEvidence: Codable, Sendable, Hashable {
    public enum Scale: String, Codable, Sendable { case community, parcel }
    public var rating: String
    public var scale: Scale
    public var sourceID: String
    public init(rating: String, scale: Scale, sourceID: String) { self.rating=rating; self.scale=scale; self.sourceID=sourceID }
}
public struct HurricaneEvacuationPlan: Codable, Sendable, Hashable {
    /// Exact zone, route and directions stay local; cloud sees only status and evidence IDs.
    public var zone: String
    public var routeIDs: [String]
    public var sourceID: String
    public var destinationPlaceID: String?
    public var instructions: String
    public init(zone: String, routeIDs: [String], sourceID: String, destinationPlaceID: String? = nil, instructions: String = "") {
        self.zone=zone; self.routeIDs=routeIDs; self.sourceID=sourceID; self.destinationPlaceID=destinationPlaceID; self.instructions=instructions
    }
}
public struct SiteHazardProfile: Codable, Sendable, Hashable {
    public var schemaVersion = "dryrun.site-hazards/1"
    public var locationBinding: String?
    public var jurisdictionID: String
    public var sources: [SiteHazardSource]
    public var elevation: SiteElevation?
    public var floodLevel: SiteFloodLevel?
    public var wildfire: SiteWildfireEvidence?
    public var hurricane: HurricaneEvacuationPlan?
    public init(jurisdictionID: String, sources: [SiteHazardSource] = [], elevation: SiteElevation? = nil,
                floodLevel: SiteFloodLevel? = nil, wildfire: SiteWildfireEvidence? = nil, hurricane: HurricaneEvacuationPlan? = nil) {
        self.jurisdictionID=jurisdictionID; self.sources=sources; self.elevation=elevation; self.floodLevel=floodLevel; self.wildfire=wildfire; self.hurricane=hurricane
    }
}
/// Deliberately no address, coordinates, exact elevation, zone, route geometry or private directions.
/// A design flood comparison never means a building or route is safe in any event.
public struct SiteHazardSourceSummary: Codable, Sendable, Hashable {
    public var id:String; public var publisher:String; public var jurisdictionID:String
    public var retrievedAt:Date; public var validUntil:Date; public var datasetVersion:String?; public var publishedAt:Date?
}
public struct SiteHazardContext: Codable, Sendable, Hashable {
    public var schemaVersion = "dryrun.site-context/1"
    public var elevationRecorded: Bool
    public var floodComparison: String
    public var wildfireRating: String?
    public var wildfireScale: String?
    public var hurricanePlan: String
    public var sourceIDs: [String]
    public var sources: [SiteHazardSourceSummary]?
    public var limitations: [String]
    public init(_ profile: SiteHazardProfile?, jurisdictionID: String, at date: Date, locationBinding: String? = nil) {
        elevationRecorded=false; floodComparison="unknown"; hurricanePlan="unknown"; sourceIDs=[]
        limitations=["Planning evidence only; no current hazard or evacuation clearance", "Terrain and indoor relative floor height do not establish finished-floor elevation", "Wildfire community ratings do not establish individual-home risk", "Hurricane route activation and current official orders require local verification", "Wildfire and hurricane simulation and score coverage are outside the current reviewed rubric"]
        guard let p=profile, p.schemaVersion == "dryrun.site-hazards/1", p.jurisdictionID == jurisdictionID, locationBinding == nil || p.locationBinding == locationBinding,
              p.sources.count <= 20, Set(p.sources.map(\.id)).count == p.sources.count else { return }
        func usable(_ id: String) -> Bool { p.sources.contains { $0.id == id && $0.usable(at: date, jurisdictionID: jurisdictionID) } }
        if let e=p.elevation, e.meters.isFinite, e.uncertaintyMeters.isFinite, e.uncertaintyMeters >= 0,
           !e.verticalDatum.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, e.verticalDatum.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() != "unknown", usable(e.sourceID) {
            elevationRecorded=true; sourceIDs.append(e.sourceID)
            if e.surface == .finishedFloor, let f=p.floodLevel, f.meters.isFinite, f.uncertaintyMeters.isFinite,
               f.uncertaintyMeters >= 0, f.verticalDatum == e.verticalDatum, usable(f.sourceID) {
                sourceIDs.append(f.sourceID)
                let margin=e.meters-f.meters, uncertainty=e.uncertaintyMeters+f.uncertaintyMeters
                floodComparison=margin > uncertainty ? "aboveDesignLevel" : margin < -uncertainty ? "belowDesignLevel" : "overlappingUncertainty"
            }
        }
        if let w=p.wildfire, usable(w.sourceID), ["veryLow","low","moderate","high","veryHigh"].contains(w.rating) {
            wildfireRating=w.rating; wildfireScale=w.scale.rawValue; sourceIDs.append(w.sourceID)
        }
        if let h=p.hurricane, !h.zone.isEmpty, !h.routeIDs.isEmpty, h.routeIDs.count <= 8,
           h.routeIDs.allSatisfy({ !$0.isEmpty }), usable(h.sourceID) {
            hurricanePlan="recordedOfficialPlanningRoute"; sourceIDs.append(h.sourceID)
        }
        sourceIDs=Array(Set(sourceIDs)).sorted()
        sources=sourceIDs.compactMap { id in p.sources.first{$0.id==id}.map { source in
            SiteHazardSourceSummary(id:source.id,publisher:String(source.publisher.prefix(120)),jurisdictionID:source.jurisdictionID,
                retrievedAt:source.retrievedAt,validUntil:source.validUntil,datasetVersion:source.datasetVersion,publishedAt:source.publishedAt)
        }}
    }
}
public enum SiteHazardEditing {
    /// Explicit native household edit. Simulation/model observations have no corresponding mutation tool.
    public static func replace(_ profile: SiteHazardProfile?, in household: HouseholdProfile, at date: Date) -> HouseholdProfile {
        var result=household; stage(profile,in:&result); result.bumpRevision(at: date); return result
    }
    /// For a native updateHousehold transaction whose owner already bumps revision on atomic save.
    public static func stage(_ profile:SiteHazardProfile?,in household:inout HouseholdProfile) {
        var bound=profile; bound?.locationBinding=SiteHazardBinding.of(household); household.siteHazards=bound
    }
}

public enum SiteHazardBinding {
    /// Local-only change detection. This digest and the location never enter cloud context.
    public static func of(_ household:HouseholdProfile)->String {
        struct Binding:Encodable {var homeID:String;var location:PrivateLocation?}
        return StableDigest.of((try? DryRunJSON.encoder().encode(Binding(homeID:household.stableHomeID,location:household.privateLocation))) ?? Data())
    }
}
