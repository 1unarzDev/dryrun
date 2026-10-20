import Foundation

public enum HomeEditError: String, Error, Codable, Sendable {case stale,missingSelection,invalidKind}
/// Draft geometry may have many local edits; durable home revision advances exactly once per save.
/// Native must hold its write gate while awaiting the actual encrypted-store write and publish only on success.
public enum HomeEditTransaction {
    public static func prepare(_ draft:HomeModel,baseRevision:Int?,current:HomeModel?,homeID:String)->HomeModel? {
        guard current?.revision==baseRevision else {return nil}
        var candidate=draft
        candidate.id=current?.id ?? homeID
        candidate.revision=(current?.revision ?? 0)+1
        return candidate
    }
    public static func commit(_ draft:HomeModel,baseRevision:Int?,current:inout HomeModel?,homeID:String,
        persist:(HomeModel)throws->Void)throws {
        guard let candidate=prepare(draft,baseRevision:baseRevision,current:current,homeID:homeID) else {throw HomeEditError.stale}
        try persist(candidate)
        current=candidate
    }
    /// An opening correction preserves identity/endpoints/width/topology. It never creates a usable window exit.
    public static func reclassify(_ id:String,as kind:PortalKind,in home:inout HomeModel)throws {
        guard kind == .door || kind == .window else {throw HomeEditError.invalidKind}
        guard let index=home.portals.firstIndex(where:{$0.id==id}) else {throw HomeEditError.missingSelection}
        guard home.portals[index].kind != kind else {return}
        home.portals[index].kind=kind
        home.portals[index].operable = .unknown
        home.portals[index].emergencyEscapeConfirmed=nil
        home.portals[index].emergencyEscapePersonIDs=nil
        home.bumpRevision()
    }
}
