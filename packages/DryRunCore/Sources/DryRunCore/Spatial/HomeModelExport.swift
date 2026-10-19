import Foundation

/// Portable geometry shared with RealityKit. Floor-relative elevation is NEVER geographic altitude.
public enum HomeModelExport {
    public static func point3D(_ point: Vec2, floor: Floor) -> Vec3 {
        let p=floor.toCommon.apply(point)
        return Vec3(p.x,floor.elevationMeters,-p.y)
    }
    /// Original fixture geometry in OBJ, metres, +Y up; faces are room floors, lines are walls,
    /// openings and connectors. A visual test asset, not a structural/egress certification.
    public static func obj(_ home: HomeModel) -> String {
        var lines=["# DryRun fictional home; metres; x/elevation/-y; no route certification"], count=0
        func emit(_ id:String, _ points:[Vec3], face:Bool=false) {
            lines.append("o " + id.replacingOccurrences(of:" ",with:"_"))
            let first=count+1
            for p in points { lines.append("v \(p.x) \(p.y) \(p.z)"); count += 1 }
            if points.count > 1 { lines.append((face ? "f " : "l ")+(first...count).map(String.init).joined(separator:" ")) }
            else if points.count == 1 { lines.append("p \(count)") }
        }
        func points(_ raw:[Vec2],_ floorID:String)->[Vec3] {
            guard let f=home.floors.first(where:{$0.id==floorID}) else {return []}
            return raw.map{point3D($0,floor:f)}
        }
        for room in home.spaces {emit(room.id,points(room.polygon,room.floorID),face:true)}
        for w in HomeRenderGeometry.wallSegments(home) {emit(w.id,points([w.a,w.b],w.floorID))}
        for p in home.portals {emit(p.id+"_"+p.kind.rawValue+"_"+p.verification.rawValue,points([p.a,p.b],p.floorID))}
        for a in home.annotations {if let floor=a.floorID,let position=a.position {emit(a.id+"_"+a.kind.rawValue,points([position],floor))}}
        for c in home.connectors {
            if let a=home.space(c.fromSpaceID),let b=home.space(c.toSpaceID) {
                emit(c.id,points([c.fromPoint],a.floorID)+points([c.toPoint],b.floorID))
            }
        }
        return lines.joined(separator:"\n")+"\n"
    }
}
