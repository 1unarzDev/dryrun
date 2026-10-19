import Foundation

/// Location and household confirmation are distinct from operational readiness or structural safety.
public enum HomeSafetyMarkers {
    public static func hasValidPlacement(_ marker: Annotation, in home: HomeModel) -> Bool {
        guard let roomID=marker.spaceID,let room=home.space(roomID),let point=marker.position,
              point.x.isFinite,point.y.isFinite,room.floorID==marker.floorID,
              room.geometryNeedsReview != true,Geometry.isSimplePolygon(room.polygon) else {return false}
        return Geometry.contains(room.polygon,point)
    }
    public static func place(id:String,kind:AnnotationKind,roomID:String,position:Vec2,label:String="",note:String?=nil,
                             verified:Bool,in home:HomeModel) throws -> HomeModel {
        guard !id.isEmpty,home.annotations.filter({$0.id==id}).count <= 1,let room=home.space(roomID) else {throw SessionError.invalidCommand}
        let marker=Annotation(id:id,kind:kind,floorID:room.floorID,spaceID:roomID,position:position,label:label,
                              verification:verified ? .verified:.proposed,note:note)
        guard hasValidPlacement(marker,in:home) else {throw SessionError.invalidCommand}
        var result=home
        result.annotations.removeAll{$0.id==id};result.annotations.append(marker);result.bumpRevision()
        return result
    }
}
