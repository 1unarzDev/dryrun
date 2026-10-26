import XCTest
import DryRunCore
@testable import DryRun

/// No camera or synthetic CapturedRoom decoder is involved. The app's SDK projection seam feeds the
/// real importer and room-association service, so capture ordering and display IDs can change independently.
final class RoomPlanMappingTests: XCTestCase {
    func testSDKRoomIdentitySurvivesReorderingWithoutReassigningThePhysicalRoom() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "A0000000-0000-0000-0000-000000000001"))
        let secondID = try XCTUnwrap(UUID(uuidString: "B0000000-0000-0000-0000-000000000002"))
        func room(_ identifier: UUID, x: Double) -> ScanRoom {
            let floor = ScanSurface(id: "floor-\(identifier)", category: .floor, transform: .identity,
                dimensions: Vec3(4, 0, 4),
                polygonCorners: [Vec3(x, 0, 0), Vec3(x + 4, 0, 0), Vec3(x + 4, 0, -4), Vec3(x, 0, -4)], confidence: .high)
            return RoomPlanMapping.projectedRoom(identifier: identifier, story: 0, surfaces: [floor], objects: [])
        }
        let first = room(firstID, x: 0), second = room(secondID, x: 4)
        func imported(_ rooms: [ScanRoom], frame: String = "shared-frame") throws -> HomeModel {
            try ScanImport.importCapture(.init(rooms: rooms, sharedCoordinateFrame: true, coordinateFrameID: frame), homeID: "stable-home").home
        }
        let original = try imported([first, second]), reordered = try imported([second, first])
        let assigned = try XCTUnwrap(original.spaces.first { $0.sourceScanRoomID == firstID.uuidString })
        XCTAssertEqual(assigned.label, "Room 1")
        let remappedID = try XCTUnwrap(HomeRoomAssociations.remappedRoomID(assigned.id, from: original, to: reordered))
        let remapped = try XCTUnwrap(reordered.space(remappedID))
        XCTAssertEqual(remapped.sourceScanRoomID, firstID.uuidString)
        XCTAssertEqual(remapped.polygon, assigned.polygon)
        XCTAssertEqual(remapped.label, "Room 2")
        XCTAssertNotEqual(remappedID, assigned.id)
        XCTAssertNotEqual(reordered.space(assigned.id)?.sourceScanRoomID, assigned.sourceScanRoomID)
        let unrelated = try imported([second, first], frame: "new-capture-frame")
        XCTAssertNil(HomeRoomAssociations.remappedRoomID(assigned.id, from: original, to: unrelated))
    }
}
