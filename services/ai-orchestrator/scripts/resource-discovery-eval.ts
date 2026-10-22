import {evaluationKey} from './eval-key.js';
import {ResourceDiscovery} from '../src/resource-discovery.js';
import {GeminiProvider,SpendBudget} from '../src/provider.js';
import {mkdir,writeFile} from 'node:fs/promises';
const runID=new Date().toISOString().replace(/[:.]/g,'-');
const budget=new SpendBudget(Number(process.env.DRYRUN_MAX_USD??1));
const provider=new GeminiProvider(await evaluationKey(),'gemini-3.1-flash-lite',budget,{research:process.env.DRYRUN_RESEARCH_MODEL??'gemini-3.8-flash'});
const discovery=new ResourceDiscovery(provider);
await mkdir('../../artifacts/ai/discovery',{recursive:true});
for(const brief of [
 {taskID:'synthetic-cooling',locality:{city:'Denver',administrativeArea:'Colorado',countryCode:'US'},capabilities:['cooling','stepFree'],travelMode:'transit',maximumDistanceKm:15,limitedBudget:true},
 {taskID:'synthetic-water',locality:{city:'Marfa',administrativeArea:'Texas',countryCode:'US'},capabilities:['drinkingWater','delivery'],travelMode:'assistance',maximumDistanceKm:60,limitedBudget:true},
]){
 const started=Date.now();let artifact:unknown;
 try{const result=await discovery.discover(brief);const passed=result.comparison.options.length>0&&result.attribution.citations.length>0;artifact={synthetic:true,liveModelTested:true,model:process.env.DRYRUN_RESEARCH_MODEL??'gemini-3.8-flash',normalizerModel:'gemini-3.1-flash-lite',sdk:'2.30.0',status:passed?'passed':'limited',latencyMs:Date.now()-started,result,nativeMapKit:'pending',humanReview:'pending'};console.log(JSON.stringify({locality:brief.locality.city,status:passed?'passed':'limited',options:result.comparison.options.map(o=>o.name),inspections:result.execution.urlInspectionSteps}));}
 catch(error){artifact={synthetic:true,status:'failed',brief,error:error instanceof Error?error.message:'unknown',latencyMs:Date.now()-started};console.log(JSON.stringify({locality:brief.locality.city,status:'failed',error:error instanceof Error?error.message:'unknown'}));process.exitCode=1;}
 await mkdir('../../artifacts/ai/discovery/runs/'+runID,{recursive:true});
 await writeFile(`../../artifacts/ai/discovery/runs/${runID}/${brief.locality.city.toLowerCase()}.json`,JSON.stringify(artifact,null,2)+'\n');
 await writeFile(`../../artifacts/ai/discovery/${brief.locality.city.toLowerCase()}-live.json`,JSON.stringify(artifact,null,2)+'\n');
}
await writeFile('../../artifacts/ai/discovery/usage.json',JSON.stringify({calls:discovery.calls,usage:discovery.usage,accountedUSD:budget.spentUSD,limitUSD:budget.limitUSD,searchBilling:'Internal query count/cost may not be reported; token accounting is not a provider billing guarantee.'},null,2)+'\n');
