import {evaluationKey} from './eval-key.js';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {Host} from './host.js';
import {FeatureRunner,featureContext,councilOutput,rubricSchema} from '../src/features.js';
import {GeminiProvider,SpendBudget} from '../src/provider.js';
const rubric=rubricSchema.parse(JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8')));
const cases=JSON.parse(await readFile('../../fixtures/ai/rubric-cases.json','utf8')).cases.slice(0,3);
const budget=new SpendBudget(Number(process.env.DRYRUN_MAX_USD??1.5));
const output=process.env.DRYRUN_COUNCIL_OUTPUT??'../../fixtures/ai/council-evaluation.json';
await mkdir(output.slice(0,output.lastIndexOf('/')),{recursive:true});
const host=new Host(),runner=new FeatureRunner(new GeminiProvider(await evaluationKey(),'gemini-3.1-flash-lite',budget),60);const results=[];
function expected(a:any){if(a.notApplicableRule)return 'notApplicable';const values=Object.values(a.predicates);if(!values.length)return 'unknown';const criterion=rubric.criteria.find(c=>c.id===a.criterionID)!;if(values.length===criterion.predicateIDs.length&&values.every(Boolean))return 'met';if(values.length===criterion.predicateIDs.length&&values.every(v=>v===false))return 'unmet';return 'partlyMet';}
try{for(const c of cases){const state=await host.request({op:'initialize',sample:c.sample});const household=state.householdContext;household.evidence=c.assessments.map((a:any)=>({id:a.evidenceIDs[0],origin:'userConfirmed',status:'confirmed',sourceIDs:rubric.criteria.find(x=>x.id===a.criterionID)!.sourceIDs,fieldIDs:Object.keys(a.predicates)}));
 for(let repeat=0;repeat<3;repeat++){
 const context=featureContext.parse({household,tasks:[],gaps:[],allowedActionIDs:state.preparationActions,allowedCriterionIDs:rubric.criteria.map(c=>c.id),rubric,acceptedPredicates:c.assessments});
 const started=Date.now();const result=await runner.council(context);const first=councilOutput.parse(result.reviews[0]),final=councilOutput.parse(result.adjudication);
 const matches=(review:typeof first)=>c.assessments.filter((a:any)=>review.assessments.find(x=>x.criterionID===a.criterionID)?.status===expected(a)).length;
 const falsePass=(review:typeof first)=>c.assessments.filter((a:any)=>rubric.criteria.find(x=>x.id===a.criterionID)?.critical&&expected(a)!=='met'&&review.assessments.find(x=>x.criterionID===a.criterionID)?.status==='met').length;
 results.push({household:c.id,repeat,expected:c.assessments.map((a:any)=>({criterionID:a.criterionID,status:expected(a)})),baselineAgreement:1,oneReviewerAgreement:matches(first)/rubric.criteria.length,councilAgreement:matches(final)/rubric.criteria.length,oneReviewerCriticalFalsePass:falsePass(first),councilCriticalFalsePass:falsePass(final),latencyMs:Date.now()-started,result});
 await writeFile(output.replace(/\.json$/, '-progress.json'),JSON.stringify({synthetic:true,model:'gemini-3.1-flash-lite',sdk:'2.30.0',completed:results.length,calls:runner.calls,usage:runner.usage,accountedUSD:budget.spentUSD,referenceStatus:'Policy-authored, not independent human review',results},null,2));console.log(JSON.stringify({household:c.id,repeat,status:'completed'}));
 }}
 await writeFile(output,JSON.stringify({synthetic:true,model:'gemini-3.1-flash-lite',sdk:'2.30.0',households:3,repeats:3,calls:runner.calls,usage:runner.usage,accountedUSD:budget.spentUSD,referenceStatus:'Policy-authored, not independent human review',results},null,2));console.log(JSON.stringify({households:3,repeats:3,calls:runner.calls,meanOneReviewer:results.reduce((s,r)=>s+r.oneReviewerAgreement,0)/results.length,meanCouncil:results.reduce((s,r)=>s+r.councilAgreement,0)/results.length}));
}finally{host.close();}
