import Foundation

public enum CriterionStatus: String, Codable, Sendable { case met, partlyMet, unmet, unknown, notApplicable, outsideScope }
public struct RubricCriterion: Codable, Sendable {
    public var id:String; public var domain:String; public var weight:Double
    public var predicateIDs:[String]; public var sourceIDs:[String]; public var critical:Bool
    public var applicabilityRule:String; public var freshnessDays:Int?
    private enum CodingKeys:String,CodingKey {case id,domain,weight,predicateIDs,sourceIDs,critical,applicabilityRule,freshnessDays}
    /// The frozen rubric contract (content/ai/rubric-v0.json, gateway rubricSchema) states "no freshness" as an explicit null.
    public func encode(to encoder:Encoder)throws {
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(id,forKey:.id);try c.encode(domain,forKey:.domain);try c.encode(weight,forKey:.weight)
        try c.encode(predicateIDs,forKey:.predicateIDs);try c.encode(sourceIDs,forKey:.sourceIDs);try c.encode(critical,forKey:.critical)
        try c.encode(applicabilityRule,forKey:.applicabilityRule);try c.encode(freshnessDays,forKey:.freshnessDays)
    }
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
    public var assessmentVersion:String?
    public init(criterionID:String,predicates:[String:Bool]=[:],evidenceIDs:[String]=[],notApplicableRule:String?=nil,outsideScope:Bool=false,assessmentVersion:String?=nil){
        self.criterionID=criterionID;self.predicates=predicates;self.evidenceIDs=evidenceIDs;self.notApplicableRule=notApplicableRule;self.outsideScope=outsideScope;self.assessmentVersion=assessmentVersion
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
    /// Four frozen independent situations for version-1 checks, in the variant competency order.
    public var phaseSources:[PracticeAttemptSource]?
    public var checkID:String?
    public var checkVariant:String?
    public var observations:[PracticeObservation]?
    /// practice-phases/3: the up-front plan (all branches) the frozen situations were built from.
    public var plan:PracticeSetPlan?
    public init(id:String,sequence:Int,variantID:String,answers:[PracticeAnswer],coached:Bool=false){self.id=id;self.sequence=sequence;self.variantID=variantID;self.answers=answers;self.coached=coached}
}
public struct PreparednessScorecard: Codable, Sendable {
    public var assessmentVersion:String?
    public var practiceEvaluatorVersion:String? = nil
    public var practiceAnchorCoverage:Double? = nil
    public var practiceHazardsAssessed:[String]? = nil
    public var rubricVersion:String; public var preparation:Double?; public var practice:Double
    public var overall:Double?; public var evidenceCoverage:Double; public var practiceAssessed:Int
    public var provisional:Bool; public var cap:Double; public var capReasons:[String]; public var statuses:[String:CriterionStatus]
}
public enum ScoreCompiler {
    public static let competencies=["initialResponse","adaptation","communication","continuity"]
    public static let variants=["practice-check-a/0","practice-check-b/0","practice-check-a/1","practice-check-b/1","practice-check-a/2","practice-check-b/2","practice-check-a/3","practice-check-b/3","practice-plan-a/1","practice-plan-b/1","hazard-check/1"]
    public static func compile(rubric:RubricDefinition,assessments:[CriterionAssessment],attempts:[PracticeAttempt]=[]) throws -> PreparednessScorecard {
        guard rubric.preparationWeight==0.9,rubric.practiceWeight==0.1,
              rubric.domainWeights.values.allSatisfy({$0.isFinite && $0>0}),
              rubric.knownGapCap.isFinite,rubric.unknownGapCap.isFinite,
              (0...100).contains(rubric.knownGapCap),(0...100).contains(rubric.unknownGapCap),
              Set(attempts.map(\.id)).count==attempts.count,Set(attempts.map(\.sequence)).count==attempts.count,
              abs(rubric.domainWeights.keys.sorted().reduce(0){$0 + rubric.domainWeights[$1]!}-100)<0.001,
              Set(rubric.criteria.map(\.id)).count==rubric.criteria.count,
              Set(assessments.map(\.criterionID)).count==assessments.count else {throw SessionError.invalidCommand}
        let assessmentVersions=Set(assessments.compactMap(\.assessmentVersion))
        guard assessmentVersions.count<=1, assessmentVersions.isEmpty || assessments.allSatisfy({$0.assessmentVersion != nil}) else {throw SessionError.invalidCommand}
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
        // The fixed 25-point competency budgets are preserved. A short check changes
        // its own competency only; untouched independent four-phase evidence survives.
        var independent:[String:(PracticeAttempt,PracticeAnswer)]=[:]
        var latestAnchors:[String:(PracticeAttempt,PracticeAnswer)]=[:]
        for attempt in attempts.sorted(by:{$0.sequence<$1.sequence}) {
            guard variants.contains(attempt.variantID),Set(attempt.answers.map(\.competencyID)).count==attempt.answers.count,
                  Set(attempt.answers.map(\.committedActionID)).count==attempt.answers.count else {throw SessionError.invalidCommand}
            for answer in attempt.answers {
                guard competencies.contains(answer.competencyID),[0,0.5,1].contains(answer.credit),!answer.committedActionID.isEmpty else {throw SessionError.invalidCommand}
            }
            guard !attempt.coached,attempt.archivedUnverified != true else {continue}
            if let id=attempt.checkID {
                guard let check=HazardPracticeCheck.bank.first(where:{$0.id==id}) else {throw SessionError.invalidCommand}
                if let answer=attempt.answers.first(where:{$0.competencyID==check.competencyID}) {latestAnchors[id]=(attempt,answer)}
            } else {
                for answer in attempt.answers where answer.beforeFeedback {independent[answer.competencyID]=(attempt,answer)}
            }
        }
        var assessedHazards=Set<String>(),anchors=0
        for check in HazardPracticeCheck.bank {
            if let (_,answer)=latestAnchors[check.id],answer.beforeFeedback {anchors += 1;assessedHazards.insert(check.scenarioID)}
        }
        for competency in competencies {
            let checks=HazardPracticeCheck.bank.filter{$0.competencyID==competency}
            let checked=checks.compactMap{latestAnchors[$0.id]}
            let latest=checked.map{$0.0.sequence}.max() ?? Int.min
            if let (attempt,answer)=independent[competency],attempt.sequence>=latest {
                practice += 25*answer.credit;practiceAssessed += 1
            } else if !checked.isEmpty {
                let eligible=checked.filter{$0.1.beforeFeedback}
                practice += 25*eligible.reduce(0){$0+$1.1.credit}/Double(checks.count)
                if !eligible.isEmpty {practiceAssessed += 1}
            }
        }
        let hasHazardChecks=attempts.contains{$0.checkID != nil}
        return PreparednessScorecard(assessmentVersion:assessmentVersions.first,practiceEvaluatorVersion:attempts.max(by:{$0.sequence<$1.sequence})?.source.map{$0.evaluatorVersion ?? PracticeEvaluator.legacyVersion},practiceAnchorCoverage:hasHazardChecks ? Double(anchors)/Double(HazardPracticeCheck.bank.count)*100:nil,practiceHazardsAssessed:hasHazardChecks ? assessedHazards.sorted():nil,rubricVersion:rubric.version,preparation:preparation,practice:practice,
            overall:preparation.map{min(0.9*$0+0.1*practice,cap)},evidenceCoverage:weight>0 ? 100*coverage/weight : 0,
            practiceAssessed:practiceAssessed,provisional:true,cap:cap,capReasons:reasons.sorted(),statuses:statuses)
    }
}
