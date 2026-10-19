import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {Host} from './host.js';
import {GeminiProvider,SpendBudget} from '../src/provider.js';
import {FeatureRunner,featureContext,councilOutput,rubricSchema} from '../src/features.js';
const bytes=await readFile('../../fixtures/ai/source-assessment-cases-v1.json');
const lock=JSON.parse(await readFile('../../fixtures/ai/source-assessment-lock-v1.json','utf8'));
assert.equal(createHash('sha256').update(bytes).digest('hex'),lock.sha256);
const fixture=JSON.parse(bytes.toString('utf8'));
const selected=['source-household-01','source-household-13','source-household-31'];
const rubric=rubricSchema.parse(JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8')));
const host=new Host(),provider=new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??''),runner=new FeatureRunner(provider,60);
const results:any[]=[];
const confirmed=(value:unknown)=>({value,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]});
function expectations(c:any){return [
 {criterionID:'food',status:c.expected.food.quantity===true?'met':c.expected.food.quantity===false&&c.expected.food.accessible===false?'unmet':'partlyMet'},
 {criterionID:'assistance',status:c.expected.assistance.notApplicableRule?'notApplicable':c.expected.assistance.assigned===null?'unknown':'partlyMet'},
 {criterionID:'care',status:c.expected.care.notApplicableRule?'notApplicable':'unknown'},
 {criterionID:'pets',status:c.expected.pets.transport===null?'unknown':'partlyMet'},
 {criterionID:'shelter',status:c.expected.shelter.reachable===true?'met':'partlyMet'}
];}
try {
 for(const id of selected){
  const c=fixture.cases.find((c:any)=>c.id===id);assert.equal(c.split,'development');
  const input=structuredClone(fixture.template);
  Object.assign(input.household,{id:c.household.id,displayName:c.household.displayName,people:c.household.people,pets:c.household.pets,preparedness:{items:{food:{available:confirmed(true),location:'Fictional pantry',notes:''}}}});
  input.household.supplies.limitedBudget=c.household.limitedBudget;
  const initial=await host.request({op:'initialize',input});
  const state=await host.request({op:'confirmInventory',session:initial.session,inventoryItems:c.items,rubric});
  const baseline=await host.request({op:'assess',session:state.session,inventory:state.inventory,rubric});
  const expected=expectations(c);
  for(const e of expected)assert.equal(baseline.scorecard.statuses[e.criterionID],e.status,id+':independent-reference');
  const evidence=baseline.assessments.flatMap((a:any)=>a.evidenceIDs.map((id:string)=>({id,origin:'derived',status:Object.keys(a.predicates).length||a.notApplicableRule?'confirmed':'unknown',sourceIDs:a.criterionID==='food'?['S64']:rubric.criteria.find(r=>r.id===a.criterionID)!.sourceIDs,fieldIDs:Object.keys(a.predicates)})));
  const context=featureContext.parse({household:{...state.householdContext,evidence:[...new Map(evidence.map((e:any)=>[e.id,e])).values()]},tasks:[],gaps:state.gaps,allowedActionIDs:state.preparationActions,allowedCriterionIDs:rubric.criteria.map(c=>c.id),rubric,acceptedPredicates:baseline.assessments});
  for(let repeat=0;repeat<3;repeat++){
   const started=Date.now(),calls=runner.calls;
   const result=await runner.council(context);
   const one=councilOutput.parse(result.reviews[0]),council=councilOutput.parse(result.adjudication);
   const agreement=(review:typeof one)=>expected.filter(e=>review.assessments.find(a=>a.criterionID===e.criterionID)?.status===e.status).length/expected.length;
   const falsePass=(review:typeof one)=>expected.filter(e=>rubric.criteria.find(c=>c.id===e.criterionID)!.critical&&e.status!=='met'&&review.assessments.find(a=>a.criterionID===e.criterionID)?.status==='met').length;
   const acceptedAgreement=expected.filter(e=>result.accepted.find(a=>a.criterionID===e.criterionID)?.status===e.status).length/expected.length;
   assert.equal(acceptedAgreement,1);
   const reproduced=await host.request({op:'assess',session:state.session,assessments:context.acceptedPredicates,rubric});
   assert.deepEqual(reproduced.scorecard,baseline.scorecard);
   results.push({household:id,repeat,referenceScope:expected,contextDigest:createHash('sha256').update(JSON.stringify(context)).digest('hex'),baselineReferenceAgreement:1,oneReviewerReferenceAgreement:agreement(one),rawCouncilReferenceAgreement:agreement(council),oneReviewerCriticalFalsePass:falsePass(one),rawCouncilCriticalFalsePass:falsePass(council),acceptedReferenceAgreement:acceptedAgreement,scoreStable:true,latencyMs:Date.now()-started,calls:runner.calls-calls,baselineScorecard:baseline.scorecard,result});
   await writeFile('../../fixtures/ai/source-council-progress-v4.json',JSON.stringify({synthetic:true,sourceFixtureHash:lock.sha256,completed:results.length,calls:runner.calls,estimatedUSD:provider.budget.spentUSD,usage:runner.usage,results},null,2)+'\n');
   console.log(JSON.stringify({household:id,repeat,oneAgreement:agreement(one),councilAgreement:agreement(council),rawCriticalFalsePass:falsePass(council),scoreStable:true}));
  }
 }
 const singleReviewerCost=new SpendBudget();
 if(results.every(r=>r.calls===4))for(let n=0;n<runner.usage.length;n+=4)singleReviewerCost.charge(runner.usage[n],provider.model);
 const summary={oneReviewerOnlyEstimatedUSD:results.every(r=>r.calls===4)?singleReviewerCost.spentUSD:null,oneReviewerLatencyMs:null,households:selected.length,repeats:3,independentReferenceCriteriaPerHousehold:5,calls:runner.calls,estimatedUSD:provider.budget.spentUSD,meanOneReviewer:results.reduce((n,r)=>n+r.oneReviewerReferenceAgreement,0)/results.length,meanRawCouncil:results.reduce((n,r)=>n+r.rawCouncilReferenceAgreement,0)/results.length,oneCriticalFalsePass:results.reduce((n,r)=>n+r.oneReviewerCriticalFalsePass,0),rawCouncilCriticalFalsePass:results.reduce((n,r)=>n+r.rawCouncilCriticalFalsePass,0),meanCouncilLatencyMs:results.reduce((n,r)=>n+r.latencyMs,0)/results.length};
 await writeFile('../../fixtures/ai/source-council-evaluation-v4.json',JSON.stringify({synthetic:true,referenceStatus:'Policy-authored five-criterion subset; not human-adjudicated. Three actual synthetic source households sharing ranch geometry, not sampled real families.',model:provider.model,sdk:'2.30.0',prompts:'coverage/1 consistency/1 fairness/1 adjudication/1',referenceAssessmentVersion:fixture.assessmentVersion,assessmentVersion:results[0]?.baselineScorecard.assessmentVersion,rubricVersion:rubric.version,sourceFixtureHash:lock.sha256,summary,usage:runner.usage,results,unrun:['source holdout live council','independent qualified human references','other criterion source references','real household and varied scan validation']},null,2)+'\n');
 console.log(JSON.stringify({status:'completed',...summary}));
} finally {host.close();}
