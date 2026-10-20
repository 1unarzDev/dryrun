import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {directorPrompt} from '../src/gateway.js';
const root='../../artifacts/ai/six-hazard';
const report=JSON.parse(await readFile(process.env.DRYRUN_LIVE_REPORT??root+'/live-report.json','utf8'));
assert.equal(report.reports.length,6,'Export one complete six-row attempt, never a collection of historical best rows');
const scenarios=[];
for(const row of report.reports){
 const data=JSON.parse(await readFile(`${root}/runs/${report.runID}/${row.hazard}.json`,'utf8'));
 assert.equal(data.mode,'live-model-tested');
 const initial=data.trace[0].initial;
 const final=[...data.trace].reverse().find((step:any)=>step.committed)?.committed??initial;
 scenarios.push({hazard:data.hazard,liveStatus:data.status,directorPrompt:data.directorPrompt,model:data.model,provider:data.provider,keySlot:data.keySlot,finished:data.finished,requireFinish:data.requireFinish,maxTurns:data.maxTurns,evaluationScope:data.evaluationScope,recordedAt:data.recordedAt,providerTurns:data.providerTurns,providerResponses:data.providerResponses,outcomes:data.outcomes,initialSession:initial.session,finalSession:final.session,expectedDigest:final.receipt.contextDigest,experience:final.receipt.experience,decisions:data.trace.flatMap((step:any)=>step.submittedAction?[{selected:step.submittedAction}]:step.alternatives?[{feasibleAlternatives:step.alternatives.map((a:any)=>a.action)}]:step.failure?[{failure:step.failure}]:[])});
}
const evidence={version:'dryrun.corrective-live-evidence/1',synthetic:true,runID:report.runID,directorPrompt:report.directorPrompt,promptVersionVerification:report.directorPrompt.sha256===directorPrompt.sha256?{version:directorPrompt.version,method:'exact current instruction SHA256 match',originalLabel:report.directorPrompt.version}:undefined,sdk:'2.30.0',accountedUSD:report.accountedUSD,accounting:'Usage estimates plus retained unknown-outcome reservations; not a provider invoice',calls:report.calls,usage:report.usage,livePassed:scenarios.filter(s=>s.liveStatus==='passed').length,native:'pending',humanReview:'pending',scenarios};
await writeFile(process.env.DRYRUN_CORRECTIVE_EVIDENCE_OUTPUT??'../../fixtures/ai/corrective-live-traces.json',JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify({synthetic:true,runID:report.runID,livePassed:evidence.livePassed,total:6}));
