import Foundation
import Testing
@testable import DryRunCore

/// Response bodies recorded from the live FEMA NFHL and USGS EPQS services on 2026-10-19 (public points in Texas).
@Suite("Official flood and elevation lookups") struct OfficialSiteLookupTests {
    let galvestonAE = #"{"features":[{"attributes":{"DFIRM_ID":"48167C","FLD_ZONE":"AE","ZONE_SUBTY":null,"SFHA_TF":"T","STATIC_BFE":12.0,"V_DATUM":"NAVD88","DEPTH":-9999.0,"LEN_UNIT":"Feet"}}]}"#
    let houstonX = #"{"features":[{"attributes":{"DFIRM_ID":"48201C","FLD_ZONE":"X","ZONE_SUBTY":"AREA OF MINIMAL FLOOD HAZARD","SFHA_TF":"F","STATIC_BFE":-9999.0,"V_DATUM":null,"DEPTH":-9999.0,"LEN_UNIT":null}}]}"#
    let floodway = #"{"features":[{"attributes":{"DFIRM_ID":"48201C","FLD_ZONE":"AE","ZONE_SUBTY":"FLOODWAY","SFHA_TF":"T","STATIC_BFE":-9999.0,"V_DATUM":null,"LEN_UNIT":null}}]}"#

    @Test func baseFloodElevationIsUsedOnlyWithTheDatumFemaStates() throws {
        #expect(try OfficialSiteLookup.parseFlood(Data(galvestonAE.utf8)) == .record(.init(
            zone: "AE", subtype: nil, specialFloodHazardArea: true, baseFloodElevationFeet: 12, verticalDatum: "NAVD88", studyID: "48167C")))
        guard case .record(let x) = try OfficialSiteLookup.parseFlood(Data(houstonX.utf8)) else { Issue.record("expected a record"); return }
        #expect(x.zone == "X" && x.baseFloodElevationFeet == nil && x.verticalDatum == nil && x.specialFloodHazardArea == false)
        guard case .record(let fw) = try OfficialSiteLookup.parseFlood(Data(floodway.utf8)) else { Issue.record("expected a record"); return }
        #expect(fw.subtype == "FLOODWAY" && fw.baseFloodElevationFeet == nil)
        // A BFE without a datum is never paired with an invented one.
        let noDatum = galvestonAE.replacingOccurrences(of: #""NAVD88""#, with: "null")
        guard case .record(let nd) = try OfficialSiteLookup.parseFlood(Data(noDatum.utf8)) else { Issue.record("expected a record"); return }
        #expect(nd.baseFloodElevationFeet == nil && nd.verticalDatum == nil)
    }

    @Test func emptyDifferingAndErrorResponsesAreNotRecords() throws {
        #expect(try OfficialSiteLookup.parseFlood(Data(#"{"features":[]}"#.utf8)) == .notMapped)
        let two = #"{"features":[\#(galvestonAE.dropFirst(13).dropLast(2)),\#(houstonX.dropFirst(13).dropLast(2))]}"#
        #expect(try OfficialSiteLookup.parseFlood(Data(two.utf8)) == .ambiguous)
        #expect(throws: OfficialSiteLookup.LookupError.serviceError) {
            try OfficialSiteLookup.parseFlood(Data(#"{"error":{"code":400,"message":"Failed to execute query.","details":[]}}"#.utf8))
        }
        #expect(throws: OfficialSiteLookup.LookupError.unreadable) { try OfficialSiteLookup.parseFlood(Data("<html>".utf8)) }
    }

    @Test func terrainElevationHasNoInventedDatumOrUncertainty() throws {
        let body = #"{"location":{"x":-94.7977,"y":29.3013},"locationId":0,"value":5.80048446711156,"rasterId":45610,"resolution":1}"#
        #expect(try OfficialSiteLookup.parseElevation(Data(body.utf8)) == .init(feet: 5.80048446711156, resolutionMeters: 1))
        #expect(try OfficialSiteLookup.parseElevation(Data(#"{"value":-1000000}"#.utf8)) == nil)
        #expect(try OfficialSiteLookup.parseElevation(Data(#"{"value":"12.5"}"#.utf8))?.feet == 12.5)
    }

    @Test func queriesCarryOnlyTheCoordinatesAndRejectBadLocations() throws {
        let url = try OfficialSiteLookup.floodQueryURL(latitude: 29.3013, longitude: -94.7977)
        #expect(url.host == "hazards.fema.gov" && url.absoluteString.contains("29.3013") && url.absoluteString.contains("returnGeometry=false"))
        #expect(try OfficialSiteLookup.elevationQueryURL(latitude: 29.3, longitude: -94.8).host == "epqs.nationalmap.gov")
        #expect(throws: OfficialSiteLookup.LookupError.invalidLocation) { try OfficialSiteLookup.floodQueryURL(latitude: 0, longitude: 0) }
        #expect(throws: OfficialSiteLookup.LookupError.invalidLocation) { try OfficialSiteLookup.floodQueryURL(latitude: .nan, longitude: 1) }
    }
}
