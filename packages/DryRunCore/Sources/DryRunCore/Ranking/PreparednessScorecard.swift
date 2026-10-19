import Foundation

public enum CriterionStatus: String, Codable, Sendable { case met, partlyMet, unmet, unknown, notApplicable, outsideScope }
public struct RubricCriterion: Codable, Sendable {
    public var id:String; public var domain:String; public var weight:Double
    public var predicateIDs:[String]; public var sourceIDs:[String]; public var critical:Bool
    public var applicabilityRule:String; public var freshnessDays:Int?
}
public struct RubricDefinition: Codable, Sendable {
    public var version:String; public var domainWeights:[String:Double]; public var criteria:[RubricCriterion]
    public var preparationWeight:Double; public var practiceWeight:Double
    public var knownGapCap:Double; public var unknownGapCap:Double
}
public struct CriterionAssessment: Codable, Sendable {
    public var criterionID:String
    /// Atomic, host-accepted predicates. nil is unknown; false is an assessed failure.
    public var predicates:[String:Bool]
    public var evidenceIDs:[String]
    public var notApplicableRule:String?
    public var outsideScope:Bool
    public init(criterionID:String,predicates:[String:Bool]=[:],evidenceIDs:[String]=[],notApplicableRule:String?=nil,outsideScope:Bool=false){
        self.criterionID=criterionID;self.predicates=predicates;self.evidenceIDs=evidenceIDs;self.notApplicableRule=notApplicableRule;self.outsideScope=outsideScope
    }
}
public struct PracticeAnswer: Codable, Sendable {
    public var competencyID:String; public var credit:Double; public var committedActionID:String; public var beforeFeedback:Bool
    public init(competencyID:String,credit:Double,committedActionID:String,beforeFeedback:Bool){self.competencyID=competencyID;self.credit=credit;self.committedActionID=committedActionID;self.beforeFeedback=beforeFeedback}
}
public struct PracticeAttempt: Codable, Sendable {
    public var id:String; public var sequence:Int; public var variantID:String; public var answers:[PracticeAnswer]; public var coached:Bool
    public var archivedUnverified:Bool?
    public var source:PracticeAttemptSource?
    public var observations:[PracticeObservation]?
    public init(id:String,sequence:Int,variantID:String,answers:[PracticeAnswer],coached:Bool=false){self.id=id;self.sequence=sequence;self.variantID=variantID;self.answers=answers;self.coached=coached}
}
public struct PreparednessScorecard: Codable, Sendable {
    public var rubricVersion:String; public var preparation:Double?; public var practice:Double
    public var overall:Double?; public var evidenceCoverage:Double; public var practiceAssessed:Int
    public var provisional:Bool; public var cap:Double; public var capReasons:[String]; public var statuses:[String:CriterionStatus]
}
public enum ScoreCompiler {
    public static let competencies=["initialResponse","adaptation","communication","continuity"]
    public static let variants=["practice-check-a/0","practice-check-b/0"]
    public static func compile(rubric:RubricDefinition,assessments:[CriterionAssessment],attempts:[PracticeAttempt]=[]) throws -> PreparednessScorecard {
        guard rubric.preparationWeight==0.9,rubric.practiceWeight==0.1,
              rubric.domainWeights.values.allSatisfy({$0.isFinite && $0>0}),
              rubric.knownGapCap.isFinite,rubric.unknownGapCap.isFinite,
              (0...100).contains(rubric.knownGapCap),(0...100).contains(rubric.unknownGapCap),
              Set(attempts.map(\.id)).count==attempts.count,Set(attempts.map(\.sequence)).count==attempts.count,
              abs(rubric.domainWeights.keys.sorted().reduce(0){$0 + rubric.domainWeights[$1]!}-100)<0.001,
              Set(rubric.criteria.map(\.id)).count==rubric.criteria.count,
              Set(assessments.map(\.criterionID)).count==assessments.count else {throw SessionError.invalidCommand}
        let byID=Dictionary(uniqueKeysWithValues:assessments.map{($0.criterionID,$0)})
        guard byID.keys.allSatisfy({key in rubric.criteria.contains{$0.id==key}}) else {throw SessionError.invalidCommand}
        var domainEarned:[String:Double]=[:],domainAssessed:[String:Double]=[:],domainPossible:[String:Double]=[:]
        var statuses:[String:CriterionStatus]=[:],cap=100.0,reasons:[String]=[],hasAssessed=false
        for c in rubric.criteria.sorted(by:{$0.id<$1.id}) {
            guard c.weight.isFinite,c.weight>0,!c.predicateIDs.isEmpty,Set(c.predicateIDs).count==c.predicateIDs.count,rubric.domainWeights[c.domain] != nil else {throw SessionError.invalidCommand}
            let a=byID[c.id] ?? CriterionAssessment(criterionID:c.id)
            guard a.predicates.keys.allSatisfy({c.predicateIDs.contains($0)}), a.predicates.isEmpty || !a.evidenceIDs.isEmpty else {throw SessionError.invalidCommand}
            if let rule=a.notApplicableRule {
                guard rule==c.applicabilityRule,rule != "always",a.evidenceIDs.count>0 else {throw SessionError.invalidCommand}
                statuses[c.id] = .notApplicable;continue
            }
            let assessed=a.outsideScope ? 0 : Double(a.predicates.count)/Double(c.predicateIDs.count)
            let credit=a.outsideScope ? 0 : Double(a.predicates.values.filter{$0}.count)/Double(c.predicateIDs.count)
            hasAssessed = hasAssessed || assessed>0
            domainPossible[c.domain,default:0] += c.weight
            domainEarned[c.domain,default:0] += c.weight*credit
            domainAssessed[c.domain,default:0] += c.weight*assessed
            let status:CriterionStatus=a.outsideScope ? .outsideScope : assessed==0 ? .unknown : credit==1 ? .met : assessed==1 && credit==0 ? .unmet : .partlyMet
            statuses[c.id]=status
            if c.critical && credit<1 {
                let limit=a.predicates.values.contains(false) ? rubric.knownGapCap : rubric.unknownGapCap
                if limit<cap {cap=limit};reasons.append(c.id)
            }
        }
        var earned=0.0,coverage=0.0,weight=0.0
        for domain in rubric.domainWeights.keys.sorted() {let w=rubric.domainWeights[domain]!;if let possible=domainPossible[domain],possible>0{earned += w*(domainEarned[domain,default:0]/possible);coverage += w*(domainAssessed[domain,default:0]/possible);weight += w}}
        let preparation=hasAssessed && weight>0 ? 100*earned/weight : nil
        var practice=0.0,practiceAssessed=0
        // Latest attempt governs even if interrupted. Historical successful result cannot hide contrary evidence.
        if let latest=attempts.max(by:{$0.sequence<$1.sequence}) {
            guard variants.contains(latest.variantID),Set(latest.answers.map(\.competencyID)).count==latest.answers.count,
                  Set(latest.answers.map(\.committedActionID)).count==latest.answers.count else {throw SessionError.invalidCommand}
            for a in latest.answers {
                guard competencies.contains(a.competencyID),[0,0.5,1].contains(a.credit),!a.committedActionID.isEmpty else {throw SessionError.invalidCommand}
                if !latest.coached && a.beforeFeedback {practice += 25*a.credit;practiceAssessed += 1}
            }
        }
        return PreparednessScorecard(rubricVersion:rubric.version,preparation:preparation,practice:practice,
            overall:preparation.map{min(0.9*$0+0.1*practice,cap)},evidenceCoverage:weight>0 ? 100*coverage/weight : 0,
            practiceAssessed:practiceAssessed,provisional:true,cap:cap,capReasons:reasons.sorted(),statuses:statuses)
    }
}
