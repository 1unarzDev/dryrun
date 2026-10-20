import Foundation
/// Thin transport projection of current baseline actions. Identity, editor and completion predicates stay host-owned.
public enum PreparationTaskCatalog {
 public static func build(household:HouseholdProfile,home:HomeModel?,rubric:RubricDefinition,at date:Date,includeSatisfied:Bool=false)->[PreparationTaskProposal]{
  let mapping=["smokeAlarms":"alarms","coAlarms":"alarms","clearExits":"escape","fireDrill":"escape","layout":"escape","shelterPlan":"shelter","food":"food","water":"water","firstAid":"essentials","flashlight":"essentials","batteries":"essentials","sanitation":"essentials","radio":"contact","reconnect":"contact","contact":"contact","outOfAreaContact":"contact","waterUtility":"contact","alerts":"contact","nearMeetup":"meetups","backupMeetup":"meetups","helper":"assistance","medicalBackup":"device","equipmentSupplies":"care","coldStorage":"device","medication":"care","pets":"pets","transport":"meetups","reviewCard":"review","heatCold":"care","floodPlan":"shelter","wellFloodPlan":"water"]
  let unresolved=BaselinePreparedness.evaluate(household:household,home:home,referenceDate:date)
  let recommendations=includeSatisfied ? unresolved+BaselinePreparedness.recorded(household:household,home:home,referenceDate:date) : unresolved
  return recommendations.compactMap{rec in
   let action=String(rec.actionID.dropFirst(5));guard let criterionID=mapping[action],let criterion=rubric.criteria.first(where:{$0.id==criterionID}) else{return nil}
   let destination=PreparationEditTarget.resolve(rec,home:home)
   let editor:String
   switch destination{case .contact:editor="contacts";case .family:editor="family";case .equipment,.backups:editor="medical";case .meeting,.transport:editor="meetingPlace";case .home,.homeSetup:editor="home";default:editor="supplies"}
   // A flashlight task cannot require a first-aid kit or sanitation to complete merely
   // because these preparations share one bounded score criterion.
   let predicateSubset=["flashlight":["light"],"firstAid":["firstAid"],"sanitation":["sanitation"]][action] ?? criterion.predicateIDs
   return PreparationTaskProposal(destination:destination,id:rec.id,actionID:rec.actionID,criterionID:criterionID,subjectID:rec.subjectID ?? "household",why:rec.whyKey,evidenceIDs:["household-needs"],completionPredicates:predicateSubset,editor:editor,dependencyIDs:rec.matchedFactIDs,priority:min(3,max(0,rec.tier.rawValue-1)))
  }
 }
}
