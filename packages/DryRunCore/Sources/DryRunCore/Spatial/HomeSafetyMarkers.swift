import Foundation

/// Location and household confirmation are distinct from operational readiness or structural safety.
public enum HomeSafetyMarkers {
    /// A schematic suggestion only. It stays proposed until the household reviews the actual location.
    /// Bound the anchor search before processing imported geometry; unknown or oversized captures need review.
    public static func suggestedPosition(roomID: String, in home: HomeModel) -> Vec2? {
        guard let room = home.space(roomID), room.geometryNeedsReview != true,
              (3...128).contains(room.polygon.count),
              room.polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 10_000 && abs($0.y) <= 10_000 }),
              Geometry.isSimplePolygon(room.polygon),
              let minX = room.polygon.map(\.x).min(), let maxX = room.polygon.map(\.x).max(),
              let minY = room.polygon.map(\.y).min(), let maxY = room.polygon.map(\.y).max(),
              maxX - minX <= 100, maxY - minY <= 100,
              (ceil((maxX - minX) / 0.25) + 1) * (ceil((maxY - minY) / 0.25) + 1) <= 20_000 else { return nil }
        return RoomPaths.anchor(in: room, home: home, clearance: 0)
    }

    public static func hasValidPlacement(_ marker: Annotation, in home: HomeModel) -> Bool {
        guard let roomID=marker.spaceID,let room=home.space(roomID),let point=marker.position,
              point.x.isFinite,point.y.isFinite,room.floorID==marker.floorID,
              room.geometryNeedsReview != true,Geometry.isSimplePolygon(room.polygon) else {return false}
        return Geometry.contains(room.polygon,point)
    }
    public static func place(id:String,kind:AnnotationKind,roomID:String,position:Vec2,label:String="",note:String?=nil,
                             verified:Bool,in home:HomeModel) throws -> HomeModel {
        guard !id.isEmpty,home.annotations.filter({$0.id==id}).count <= 1,let room=home.space(roomID) else {throw SessionError.invalidCommand}
        var marker=Annotation(id:id,kind:kind,floorID:room.floorID,spaceID:roomID,position:position,label:label,
                              verification:verified ? .verified:.proposed,note:note)
        marker.savedPlaceID = home.annotations.first { $0.id == id }?.savedPlaceID
        guard hasValidPlacement(marker,in:home) else {throw SessionError.invalidCommand}
        var result=home
        result.annotations.removeAll{$0.id==id};result.annotations.append(marker);result.bumpRevision()
        return result
    }
}
