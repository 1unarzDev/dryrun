import Foundation
/// Annotated, per-floor context illustration for AI review. It never supplies routing truth.
public enum AIPlanDiagram {
    public static func svg(home:HomeModel,floorID:String)->String? {
        let spaces=home.spaces.filter{$0.floorID==floorID}
        let points=spaces.flatMap(\.polygon)
        guard let minX=points.map(\.x).min(),let maxX=points.map(\.x).max(),let minY=points.map(\.y).min(),let maxY=points.map(\.y).max(),maxX>minX,maxY>minY else{return nil}
        func escape(_ s:String)->String{s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;")}
        func coords(_ polygon:[Vec2])->String{polygon.map{"\($0.x),\($0.y)"}.joined(separator:" ")}
        var body="<title>Home context diagram, metres, \(escape(floorID)); verify proposed geometry; no route certification</title>"
        for room in spaces {
            body += "<polygon points=\"\(coords(room.polygon))\" fill=\"#edf2f5\" stroke=\"#555\" stroke-width=\"0.04\"/>"
            let x=room.polygon.map(\.x).reduce(0,+)/Double(room.polygon.count),y=room.polygon.map(\.y).reduce(0,+)/Double(room.polygon.count)
            body += "<text x=\"\(x)\" y=\"\(y)\" font-size=\"0.25\" text-anchor=\"middle\">\(escape(room.id))</text>"
        }
        for portal in home.portals where portal.floorID==floorID {
            body += "<line x1=\"\(portal.a.x)\" y1=\"\(portal.a.y)\" x2=\"\(portal.b.x)\" y2=\"\(portal.b.y)\" stroke=\"white\" stroke-width=\"0.12\"/>"
            body += "<line x1=\"\(portal.a.x)\" y1=\"\(portal.a.y)\" x2=\"\(portal.b.x)\" y2=\"\(portal.b.y)\" stroke=\"\(portal.verification == .verified ? "#147d65":"#b17d12")\" stroke-width=\"0.05\"/>"
            body += "<text x=\"\(portal.center.x)\" y=\"\(portal.center.y)\" font-size=\"0.17\">\(escape(portal.id))</text>"
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(minX-0.5) \(minY-0.5) \(maxX-minX+1) \(maxY-minY+1)\">\(body)</svg>"
    }
}
