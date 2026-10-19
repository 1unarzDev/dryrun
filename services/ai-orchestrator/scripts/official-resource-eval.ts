import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {Host} from './host.js';
import {FeatureRunner,resourceOutput} from '../src/features.js';
import {PublicEvidenceTools} from '../src/evidence.js';
import {GeminiProvider} from '../src/provider.js';
const host=new Host(),provider=new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??''),tools=await PublicEvidenceTools.bundled(resolve('../..')),runner=new FeatureRunner(provider,12,tools);
const results=[];
try {
 const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
 const state=await host.request({op:'initialize',sample:'oak',scenarioID:'water-outage',rubric});
 const task=state.taskCatalog.find((t:any)=>t.actionID==='prep.alerts');if(!task)throw new Error('host_alert_task_missing');
 for(const regionID of ['48439','99999']) {
  const before=runner.calls,start=Date.now();
  const output=resourceOutput.parse(await runner.run('resources',{household:{...state.householdContext,regionID},tasks:[task],gaps:[],allowedActionIDs:[task.actionID],allowedCriterionIDs:[task.criterionID]}));
  const recs=output.officialRecommendations??[],records=tools.find_official_resources(regionID,'all');
  const valid=recs.every(rec=>records.some(record=>record.id===rec.resourceID)&&rec.taskID===task.id&&rec.reason.includes('need confirmation'));
  results.push({regionID,reference:'Synthetic development query for actual host alert-enrollment task; no native listings or private data',task,output,calls:runner.calls-before,latencyMs:Date.now()-start,matched:valid&&(regionID==='48439'?recs.length>0:recs.length===0),officialRecordCount:records.length});
 }
 await writeFile('../../fixtures/ai/official-resource-evaluation-v1.json',JSON.stringify({synthetic:true,model:provider.model,sdk:'2.30.0',prompt:'resources/3',calls:runner.calls,usage:runner.usage,estimatedUSD:provider.budget.spentUSD,results,limits:'Two synthetic region/task queries; repeated source pack, no independent household sample, native search/identity joins and live service capability unverified. Host explanation normalization, not model-prose factual certification.'},null,2)+'\n');
 console.log(JSON.stringify({cases:results.length,matched:results.filter(r=>r.matched).length,calls:runner.calls,officialRecommendations:results.map(r=>r.output.officialRecommendations?.length??0)}));
}finally{host.close();}
