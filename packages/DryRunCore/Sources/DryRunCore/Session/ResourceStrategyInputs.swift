import Foundation

/// Only deliberately selected strategy dependencies enter this local key. No household-wide
/// revision, free-text medical note, contact list, image collection or geographic payload is used.
public struct ResourceStrategyDependency:Codable,Hashable,Sendable {
    public var id:String
    public var state:String
    public init(id:String,state:String){self.id=id;self.state=state}
}
public extension ResourceStrategyKey {
    static func normalized(gaps:[SupplyGap],tasks:[PreparationTaskProposal],transport:String,limitedBudget:Bool,
        regionID:String,dependencies:[ResourceStrategyDependency]=[])throws->ResourceStrategyKey {
        guard gaps.count<=30,tasks.count<=100,dependencies.count<=100,
              ["car","noCar","unknown","walking","transit","driving","assistance"].contains(transport),
              !regionID.isEmpty,regionID.count<=120,Set(tasks.map(\.id)).count==tasks.count,
              Set(dependencies.map(\.id)).count==dependencies.count,
              dependencies.allSatisfy({!$0.id.isEmpty && $0.id.count<=120 && !$0.state.isEmpty && $0.state.count<=120}) else {throw SessionError.invalidCommand}
        struct Gap:Codable {var category:String;var required:Double;var confirmedUsable:Double;var deficit:Double?;var unit:String;var unknown:Bool;var sourceIDs:[String]}
        struct Task:Codable {var id:String;var actionID:String;var criterionID:String;var subjectID:String;var completionPredicates:[String];var editor:String;var dependencyIDs:[String];var priority:Int}
        struct Inputs:Encodable {var version:String;var gaps:[Gap];var tasks:[Task];var dependencies:[ResourceStrategyDependency]}
        var canonicalGaps:[String:Gap]=[:]
        for gap in gaps {
            guard !gap.category.isEmpty,gap.category.count<=120,!gap.unit.isEmpty,gap.unit.count<=120,
                  gap.required.isFinite,gap.required>=0,gap.confirmedUsable.isFinite,gap.confirmedUsable>=0,
                  gap.deficit.map({$0.isFinite && $0>=0}) ?? true else {throw SessionError.invalidCommand}
            let canonical=Gap(category:gap.category,required:gap.required==0 ? 0:gap.required,confirmedUsable:gap.confirmedUsable==0 ? 0:gap.confirmedUsable,
                deficit:gap.deficit.map{$0==0 ? 0:$0},unit:gap.unit,unknown:gap.unknown,sourceIDs:Array(Set(gap.sourceIDs)).sorted())
            let encoded=String(decoding:try DryRunJSON.encoder().encode(canonical),as:UTF8.self)
            canonicalGaps[encoded]=canonical
        }
        var canonicalTasks:[Task]=[]
        for task in tasks.sorted(by:{$0.id<$1.id}) {
            guard !task.id.isEmpty,!task.actionID.isEmpty,!task.subjectID.isEmpty,(0...3).contains(task.priority) else {throw SessionError.invalidCommand}
            // Explanatory wording/evidence ordering is not a new resource need. Stable task identity,
            // relevant subject, prerequisites, priority and editor drive the strategy instead.
            canonicalTasks.append(Task(id:task.id,actionID:task.actionID,criterionID:task.criterionID,subjectID:task.subjectID,
                completionPredicates:Array(Set(task.completionPredicates)).sorted(),editor:task.editor,
                dependencyIDs:Array(Set(task.dependencyIDs)).sorted(),priority:task.priority))
        }
        let inputs=Inputs(version:"dryrun.resource-strategy-inputs/1",gaps:canonicalGaps.keys.sorted().map{canonicalGaps[$0]!},tasks:canonicalTasks,dependencies:dependencies.sorted{$0.id<$1.id})
        var key=ResourceStrategyKey(gapCategories:gaps.map(\.category),transport:transport,limitedBudget:limitedBudget,regionID:regionID)
        key.schemaVersion="dryrun.resource-strategy-key/1"
        key.normalizedInputDigest=StableDigest.of(try DryRunJSON.encoder().encode(inputs))
        key.relatedTaskIDs=tasks.map(\.id).sorted()
        return key
    }
}
