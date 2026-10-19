import {readFile,writeFile} from 'node:fs/promises';
import {inspectOutput,outputStyleVersion} from '../src/output-quality.js';
const sources=process.env.DRYRUN_OUTPUT_AUDIT_SOURCES?.split(',')??['integrated-pipeline-current.json','housing-layout-live-v2.json','housing-features-live-v4.json','housing-features-live-v5.json','housing-features-live-v8.json','housing-features-live-v9.json','elevator-fire-live-v2.json','housing-director-live-v2.json','housing-director-live-v3.json','housing-director-live-v4.json','housing-director-elevator-live-v2.json','vision-evaluation.json'];
const cases=[];
for(const file of sources){
 const data=JSON.parse(await readFile('../../fixtures/ai/'+file,'utf8'));
 if(data.outputs)for(const o of data.outputs){
  for(const role of ['preparation','resources','stress','council'])if(o[role])cases.push({source:file,sample:o.sample,role,fields:inspectOutput(role,o[role])});
  for(const turn of o.adaptiveTrace??[])if(turn.proposal)cases.push({source:file,sample:o.sample,role:'director',fields:inspectOutput('director',turn.proposal)});
 }
 if(data.cases)for(const result of data.cases)if(result.interpretation)cases.push({source:file,sample:result.variant,role:'layout',fields:inspectOutput('layout',result.interpretation)});
 if(data.proposal)cases.push({source:file,sample:'housing-director',role:'director',fields:inspectOutput('director',data.proposal)});
 if(data.results)for(const result of data.results)cases.push({source:file,sample:result.fixture??result.id,role:result.id?'layout':'home',fields:inspectOutput('home',result.output)});
}
const fields=cases.flatMap(c=>c.fields);
const report={version:outputStyleVersion,synthetic:true,modelCalls:0,method:'Audit retained actual model text, no truncation. Word bands and claim cues are human-review flags, not quality or safety passes. Historical output predates this guidance unless source metadata establishes otherwise.',cases,fieldCount:fields.length,depthFlags:fields.filter(f=>f.flags.includes('review_depth')).length,lengthFlags:fields.filter(f=>f.flags.includes('review_length')).length,claimReviewFlags:fields.filter(f=>f.flags.includes('check_claim_against_host_evidence')).length};
await writeFile(process.env.DRYRUN_OUTPUT_AUDIT_PATH??'../../fixtures/ai/output-quality-evaluation.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({cases:cases.length,fields:report.fieldCount,depthFlags:report.depthFlags,lengthFlags:report.lengthFlags,claimReviewFlags:report.claimReviewFlags,humanReviewPending:true}));
