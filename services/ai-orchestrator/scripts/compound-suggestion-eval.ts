import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Gateway} from '../src/gateway.js';
import type {AgentProvider} from '../src/provider.js';
import {Host} from './host.js';
import {executeDirectorTool} from './director-tools.js';
const recorded=JSON.parse(await readFile('../../artifacts/ai/six-hazard/runs/2026-10-20T07-00-15-360Z/home-fire.json','utf8'));
const initial=recorded.trace[0].initial;
const context=recorded.trace.find((s:any)=>s.context).context;
const original=recorded.trace.find((s:any)=>s.result?.status==='completed').result.proposal;
const repaired=structuredClone(original);
repaired.suggestedActions[0].commands=original.suggestedActions[0].commands.filter((c:any)=>c.kind==='accompanyEscape');
let turns=0;
const provider:AgentProvider={async turn(input){
 turns++;
 if(turns===1){const call={type:'function_call' as const,id:'director-preview',name:'evaluateCandidateAction',arguments:{commands:original.commands}};return {steps:[call],calls:[call],text:'',usage:{}};}
 if(turns===3)assert(JSON.stringify(input.history.at(-1)).includes('invalidCommand'));
 const p=structuredClone(turns===2?original:repaired);if(turns===2)p.suggestedActions[0].implication+=' This ensures everyone reaches safety.';
 return {steps:[],calls:[],text:JSON.stringify({commands:p.commands,suggestedActions:p.suggestedActions,purpose:p.purpose,evidenceIDs:p.evidenceIDs}),usage:{}};
}};
const host=new Host();
try {
 const before=await host.request({op:'query',session:initial.session});
 // No caller may bypass gateway validation and durably publish the invalid choices.
 await assert.rejects(host.request({op:'directorCommit',session:initial.session,proposal:original,binding:context.binding}),/invalidCommand/);
 const gateway=new Gateway(provider);
 let result:any=await gateway.start('compound-regression',{contractVersion:'dryrun.ai/1',requestID:'compound-regression',role:'director',synthetic:true,context});
 const trace:any[]=[];
 while(result.status==='needs_client_tools'){
  const call=result.calls[0];const tool=await executeDirectorTool(host,initial,context.binding,call);
  assert.equal(tool.receipt.contextDigest,call.name==='validateSuggestedActions'?before.receipt.contextDigest:tool.receipt.contextDigest);
  trace.push({call,result:tool.result});
  result=await gateway.resume('compound-regression',{token:result.token,binding:context.binding,callID:call.id,result:tool.result});
 }
 assert.equal(result.status,'completed');assert.equal(turns,3);
 const validations=trace.filter(t=>t.call.name==='validateSuggestedActions');
 assert.equal(validations.length,2);assert.equal(validations[0].result.suggestionValidation[0].feasible,false);
 assert.equal(validations[1].result.suggestionValidation[0].feasible,true);
 const unchanged=await host.request({op:'query',session:initial.session});assert.deepEqual(unchanged.receipt,before.receipt);
 let committed=await host.request({op:'directorCommit',session:initial.session,proposal:result.proposal,binding:context.binding});
 committed=await host.request({op:'commit',session:committed.session,commit:{id:'selected-accompaniment',actor:'user',baseRevision:committed.receipt.revision,commands:result.proposal.suggestedActions[0].commands}});
 assert.equal(committed.receipt.experience.outsidePersonIDs.length,4);
 assert.deepEqual(committed.receipt.experience.escapeHelperByPersonID,{'p-oak-3':'p-oak-1','p-oak-4':'p-oak-2'});
 const replay=await host.request({op:'query',session:JSON.parse(JSON.stringify(committed.session))});assert.equal(replay.receipt.contextDigest,committed.receipt.contextDigest);
 const output={synthetic:true,mode:'recorded-live-failure-with-synthetic-repair',liveCalls:0,sourceRun:recorded.runID,trace,final:committed,checks:{invalidCommitRejected:true,wholeSequenceRejected:true,boundedRepair:true,independentHostCopies:true,actualAccompaniment:true,exactReplay:true}};
 await writeFile('../../fixtures/ai/compound-suggestion-evaluation.json',JSON.stringify(output,null,2)+'\n');
 console.log(JSON.stringify(output.checks));
}finally{host.close();}
