import {mkdir,writeFile} from 'node:fs/promises';
import {configuredGroqClients,ProviderFailure} from '../src/groq.js';
import {GroqResourceDiscovery} from '../src/groq-discovery.js';
import {ResourceDiscovery} from '../src/resource-discovery.js';
import {groqEvaluationKey} from './eval-key.js';
const runID=new Date().toISOString().replace(/[:.]/g,'-');
const searchResponses:unknown[]=[],extractionResponses:unknown[]=[];
const clients=configuredGroqClients(await groqEvaluationKey(),{extractorModel:process.env.DRYRUN_GROQ_EXTRACTOR_MODEL,observeResponse:(raw,kind)=>(kind==='search'?searchResponses:extractionResponses).push(raw)});
const discovery=new ResourceDiscovery({async turn(){throw new Error('provider_rate_limited');}},12,()=>new Date(),new GroqResourceDiscovery(clients.client,()=>new Date(),clients.extractor));
for(const brief of [
 {taskID:'synthetic-cooling',locality:{city:'Denver',administrativeArea:'Colorado',countryCode:'US'},capabilities:['cooling','stepFree'],travelMode:'transit',maximumDistanceKm:15,limitedBudget:true},
 {taskID:'synthetic-pharmacy',locality:{city:'Albuquerque',administrativeArea:'New Mexico',countryCode:'US'},capabilities:['pharmacy'],travelMode:'transit',maximumDistanceKm:15,limitedBudget:true},
 {taskID:'synthetic-water',locality:{city:'Marfa',administrativeArea:'Texas',countryCode:'US'},capabilities:['drinkingWater','delivery'],travelMode:'assistance',maximumDistanceKm:60,limitedBudget:true},
].filter(b=>!process.env.DRYRUN_RESEARCH_CITY||b.locality.city===process.env.DRYRUN_RESEARCH_CITY)){
 searchResponses.length=0;extractionResponses.length=0;
 const started=Date.now();let artifact;
 try{const result=await discovery.discover(brief);const passed=result.status==='live_sourced'&&result.comparison.options.length>=2&&result.execution.searchSteps>0;artifact={synthetic:true,primaryFailure:'injected_at_adapter_boundary',liveModelTested:true,status:passed?'passed':'partial',latencyMs:Date.now()-started,result,nativeMapKit:'pending',humanReview:'pending'};console.log(JSON.stringify({city:brief.locality.city,status:artifact.status,options:result.comparison.options.map(o=>o.name),execution:result.execution,provider:result.provider}));if(!passed)process.exitCode=1;}
 catch(error){artifact={synthetic:true,status:'failed',primaryFailure:'injected_at_adapter_boundary',error:error instanceof Error?error.message:'unknown',latencyMs:Date.now()-started,...(error instanceof ProviderFailure?{kind:error.kind,httpStatus:error.status,retryAfterMs:error.retryAfterMs,diagnostic:error.diagnostic}:{})};console.log(JSON.stringify(artifact));process.exitCode=1;}
 const directory='../../artifacts/ai/groq-search/'+runID;await mkdir(directory,{recursive:true});await writeFile(`${directory}/${brief.locality.city.toLowerCase()}.json`,JSON.stringify({...artifact,runID,configuredProvider:{name:'groq',searchModel:clients.client.model,extractorModel:clients.extractor.model},searchResponses,extractionResponses},null,2)+'\n');
}
