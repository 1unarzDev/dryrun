import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {GroqClient,ProviderOperation} from '../src/groq.js';
import {GroqResourceDiscovery} from '../src/groq-discovery.js';

// Recorded source/extractor response only. The clock is frozen at the actual
// extraction, not extended to make expired evidence appear current to families.
const captured=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-extraction-live.json','utf8'));
let replayedCalls=0;
const client=new GroqClient('synthetic','openai/gpt-oss-120b',async()=>{
 replayedCalls++;return Response.json(captured.response);
});
const result=await new GroqResourceDiscovery(client,()=>new Date(captured.extractionRecordedAt)).formatEvidence(
 captured.found,captured.brief,new ProviderOperation(AbortSignal.timeout(10000)),
 {retrievedAt:captured.sourceRetrievedAt,expiresAt:captured.sourceExpiresAt},
);
assert.equal(replayedCalls,1);
assert.equal(result.status,'cached_sourced');
assert.deepEqual(result.comparison.options.map(o=>o.name),['Albuquerque City Drug','Highland Pharmacy','University Hospital Outpatient Pharmacy']);
assert.equal(result.retrievedAt,captured.sourceRetrievedAt);
assert.equal(result.expiresAt,captured.sourceExpiresAt);
assert(result.comparison.comparison.includes('Medicaid'));
assert(result.comparison.options.every(o=>o.unknowns.length&&o.sourceURLs.length));
console.log(JSON.stringify({passed:true,mode:'recorded-live-response-revalidation',liveCalls:0,newSearch:false,originalPrimaryFailure:captured.primaryFailure,originalSearchSteps:captured.found.searchSteps,originalOpenSteps:captured.found.inspectionSteps,options:result.comparison.options.map(o=>({name:o.name,documentedService:o.documentedService,unknowns:o.unknowns})),comparison:result.comparison.comparison,retrievedAt:result.retrievedAt,expiresAt:result.expiresAt,native:'pending',humanReview:'pending'}));
