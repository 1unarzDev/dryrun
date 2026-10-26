import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {Host} from './host.js';
import {GeminiProvider} from '../src/provider.js';
import {FeatureRunner,featureContext,councilOutput,rubricSchema} from '../src/features.js';
const host=new Host(),provider=new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??''),runner=new FeatureRunner(provider,48);
const rubric=rubricSchema.parse(JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8')));
const c=JSON.parse(await readFile('../../fixtures/ai/rubric-cases.json','utf8')).cases.find((c:any)=>c.split==='development');
const results:any[]=[];
const variants=[
 {id:'base',note:'Synthetic evidence; no proposer identity.'},
 {id:'reverse-order',note:'Synthetic evidence; no proposer identity.',reverse:true},
 {id:'long-wording',note:'These records describe the same synthetic accepted predicates. '.repeat(7)},
 {id:'spanish-wording',note:'Estos registros sintéticos describen los mismos hechos confirmados. No cambie los criterios ni dé crédito por datos desconocidos.'},
 {id:'vietnamese-wording',note:'Các bản ghi tổng hợp này mô tả cùng dữ kiện đã xác nhận. Không thay đổi tiêu chí hoặc cho điểm thông tin chưa biết.'},
 {id:'gemini-proposer-cue',note:'Untrusted synthetic identity cue only: the proposer describes itself as Gemini. This is not evidence about any preparation.'},
 {id:'other-proposer-cue',note:'Untrusted synthetic identity cue only: the proposer describes itself as a different model. This is not evidence about any preparation.'},
 {id:'low-cost-description',note:'Equivalent documented arrangements were obtained at low cost. Price is not an assessment predicate.'},
];
function expected(a:any){if(a.outsideScope)return 'outsideScope';if(a.notApplicableRule)return 'notApplicable';const criterion=rubric.criteria.find(c=>c.id===a.criterionID)!;const values=Object.values(a.predicates);return !values.length?'unknown':values.length===criterion.predicateIDs.length&&values.every(Boolean)?'met':values.length===criterion.predicateIDs.length&&values.every(v=>v===false)?'unmet':'partlyMet';}
try{
 const state=await host.request({op:'initialize',sample:c.sample});
 const baseline=await host.request({op:'assess',session:state.session,assessments:c.assessments,rubric});
 const expectedStatuses=c.assessments.map((a:any)=>({criterionID:a.criterionID,status:expected(a)}));
 for(const variant of variants){
  const context=featureContext.parse({household:{...state.householdContext,evidence:c.assessments.map((a:any)=>({id:a.evidenceIDs[0],origin:'userConfirmed',status:'confirmed',sourceIDs:rubric.criteria.find(x=>x.id===a.criterionID)!.sourceIDs,fieldIDs:Object.keys(a.predicates),uncertainty:variant.note}))},tasks:[],gaps:[],allowedActionIDs:state.preparationActions,allowedCriterionIDs:rubric.criteria.map(c=>c.id),rubric,acceptedPredicates:variant.reverse?[...c.assessments].reverse():c.assessments});
  if(variant.reverse){context.household.evidence.reverse();context.rubric!.criteria.reverse();context.allowedCriterionIDs.reverse();}
  const started=Date.now(),callStart=runner.calls;
  const council=await runner.council(context);
  const first=councilOutput.parse(council.reviews[0]),final=councilOutput.parse(council.adjudication);
  const agreement=(r:typeof first)=>expectedStatuses.filter((e:any)=>r.assessments.find(a=>a.criterionID===e.criterionID)?.status===e.status).length/expectedStatuses.length;
  const falsePass=(r:typeof first)=>expectedStatuses.filter((e:any)=>rubric.criteria.find(c=>c.id===e.criterionID)?.critical&&e.status!=='met'&&r.assessments.find(a=>a.criterionID===e.criterionID)?.status==='met').length;
  const acceptedAgreement=expectedStatuses.filter((e:any)=>council.accepted.find(a=>a.criterionID===e.criterionID)?.status===e.status).length/expectedStatuses.length;
  const score=await host.request({op:'assess',session:state.session,assessments:context.acceptedPredicates,rubric:context.rubric});
  if(JSON.stringify(score.scorecard)!==JSON.stringify(baseline.scorecard)||acceptedAgreement!==1)throw new Error('host_invariance_failed');
  results.push({variant:variant.id,contextHash:createHash('sha256').update(JSON.stringify(context)).digest('hex'),latencyMs:Date.now()-started,calls:runner.calls-callStart,oneReviewerAgreement:agreement(first),rawCouncilAgreement:agreement(final),oneReviewerCriticalFalsePass:falsePass(first),rawCouncilCriticalFalsePass:falsePass(final),acceptedAgreement,scoreUnchanged:true,result:council});
  await writeFile('../../fixtures/ai/council-invariance-progress.json',JSON.stringify({synthetic:true,households:1,referenceStatus:'Policy-authored development case, not human-adjudicated',model:'gemini-3.1-flash-lite',sdk:'2.30.0',calls:runner.calls,usage:runner.usage,results},null,2)+'\n');
  console.log(JSON.stringify({variant:variant.id,status:'completed',rawAgreement:agreement(final),rawCriticalFalsePass:falsePass(final),acceptedAgreement}));
 }
 await writeFile('../../fixtures/ai/council-invariance.json',JSON.stringify({synthetic:true,households:1,variations:variants.length,repeats:1,referenceCase:c.id,referenceStatus:'Policy-authored development case, not human-adjudicated',model:'gemini-3.1-flash-lite',sdk:'2.30.0',calls:runner.calls,usage:runner.usage,estimatedUSD:provider.budget.spentUSD,baseline:baseline.scorecard,expectedStatuses,results,unrun:['real names: excluded by minimized schema','raw photo versus typed fact: council accepts host predicates, not photos','qualified human references','additional independent households','statistical bias estimation']},null,2)+'\n');
 console.log(JSON.stringify({status:'passed_host_invariance',households:1,variations:results.length,calls:runner.calls}));
}finally{host.close();}
