import assert from 'node:assert/strict';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {GroqClient,ProviderOperation,parseGroqResearch} from '../src/groq.js';
import {GroqResourceDiscovery} from '../src/groq-discovery.js';

// Frozen original retrieval/extraction clock. No new provider request or search;
// this script does not extend expired evidence for use by a family.
const source=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-search-v5-live.json','utf8'));
const captured=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-extraction-v5-live.json','utf8'));
const repair=JSON.parse(await readFile('../../fixtures/ai/research-service-identity-repair.json','utf8'));
const found=parseGroqResearch(source.searchResponses[0]);
async function replay(correct:boolean){
 let transportCalls=0;
 const client=new GroqClient('synthetic','openai/gpt-oss-20b',async()=>{
  const turn=transportCalls++;
  return Response.json(correct&&turn>0?{choices:[{message:{content:JSON.stringify(repair.syntheticRepair)}}]}:captured.responses[Math.min(turn,captured.responses.length-1)]);
 });
 const operation=new ProviderOperation(AbortSignal.timeout(10000));
 const result=await new GroqResourceDiscovery(client,()=>new Date(captured.sourceRetrievedAt)).formatEvidence(
  found,captured.result.brief,operation,{retrievedAt:source.result.retrievedAt,expiresAt:source.result.expiresAt});
 assert.equal(transportCalls,2);assert.equal(operation.outputRepairs,1);
 assert.equal(result.retrievedAt,source.result.retrievedAt);assert.equal(result.expiresAt,source.result.expiresAt);
 return {transportCalls,outputRepairs:operation.outputRepairs,result};
}
const original=await replay(false),corrected=await replay(true);
assert.equal(original.result.status,'partial_sourced');assert.equal(original.result.execution.extractionStatus,'invalid_output');
assert.deepEqual(original.result.comparison.options,[]);assert(original.result.attribution.evidence.length>0);
assert.equal(corrected.result.status,'cached_sourced');assert.equal(corrected.result.comparison.options.length,2);
assert.equal(corrected.result.comparison.options[0]?.name,'Increasing Access to Prescriptions');
assert(corrected.result.comparison.options[1]?.whyUseful.includes('contact-only'));
assert(corrected.result.comparison.options.every(o=>o.unknowns.some(u=>/transit/i.test(u))));
assert(!JSON.stringify(corrected.result.comparison).includes('ABQ RIDE Route 8'));
const report={version:'dryrun.research-service-evidence-evaluation/1',passed:true,newProviderCalls:0,newSearch:false,
 recordedSourceProvider:'groq/openai/gpt-oss-120b',recordedExtractor:'groq/openai/gpt-oss-20b',
 actualFailedExtractionReplayed:true,actualFailureRejected:true,syntheticRepairAccepted:true,liveRepairVerified:false,
 original:{status:original.result.status,retainedOptions:original.result.comparison.options.length,errors:original.result.execution.extractionErrors},
 repaired:{status:corrected.result.status,options:corrected.result.comparison.options,comparison:corrected.result.comparison.comparison},
 perOperationSyntheticTransportCalls:2,perOperationOutputRepairs:1,retrievedAt:source.result.retrievedAt,expiresAt:source.result.expiresAt,
 native:'pending',humanReview:'pending',limits:'Identity-only service evidence is rejected. This is not a semantic entailment verifier for arbitrary reasoning prose, a current resource recommendation, or evidence of useful fresh live discovery.'};
await mkdir('../../artifacts/ai/resource-service-evidence',{recursive:true});
await writeFile('../../artifacts/ai/resource-service-evidence/report.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({passed:true,newProviderCalls:0,newSearch:false,recordedFailureRejected:true,syntheticRepairAccepted:true,liveRepairVerified:false,report:'artifacts/ai/resource-service-evidence/report.json'}));
