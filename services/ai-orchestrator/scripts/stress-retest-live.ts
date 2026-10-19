import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {executeDirectorTool} from './director-tools.js';
import {Gateway} from '../src/gateway.js';
import {GeminiProvider} from '../src/provider.js';
import {minimizedSnapshot} from '../src/contracts.js';
const provider=new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??'');
const host=new Host(),trace:any[]=[],replies:any[]=[];
const evidence:any={synthetic:true,liveModel:true,recordedAt:new Date().toISOString(),model:provider.model,sdk:'2.30.0',trace,replies};
const gateway=new Gateway({async turn(input){try{const response=await provider.turn(input);replies.push({text:response.text,calls:response.calls,usage:response.usage});return response;}catch(error){replies.push({failure:error instanceof Error?error.message:'provider_failure'});throw error;}}});
try {
 const fixture=JSON.parse(await readFile('../../fixtures/ai/stress-retest.json','utf8'));
 const state=await host.request({op:'query',session:fixture.source});
 evidence.source=state;
 const binding={sessionID:state.session.id,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home?.revision??0};
 const context={initialInventoryItemIDs:state.session.inventory.ledger.items.map((item:any)=>item.id),binding,snapshot:minimizedSnapshot(state.receipt),profiles:state.directorProfiles.filter((p:any)=>fixture.profileIDs.includes(p.id)),homeScene:state.homeScene,household:state.householdContext,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,
 learningObjectives:[
 'Investigate recorded water storage with runCounterfactual under evt.home-fire.alarm and evt.home-fire.fire-origin; include a controlled retestPlan.',
 'Recorded water item water is in sp-kitchen. Before the hypothetical incident, p-oak-1 can takeSupply water, moveTo sp-living, and transferSupply water to sp-living.',
 'Compare resources and remaining gaps/unknowns from the host. A preserved supply does not resolve every gap. Preview a useful current-session follow-up and request a decision. No real household edits.'
 ]};
 evidence.context=context;
 let result:any=await gateway.start('synthetic-live-retest',{contractVersion:'dryrun.ai/1',requestID:'controlled-storage-live',role:'director',synthetic:true,context});
 while(result.status==='needs_client_tools'){
  const call=result.calls[0];const step:any={call};trace.push(step);
  const response=await executeDirectorTool(host,state,binding,call);step.result=response.result;
  if(call.name!=='evaluateCandidateAction')assert.deepEqual(response.receipt,state.receipt);
  assert.deepEqual((await host.request({op:'query',session:state.session})).receipt,state.receipt);
  result=await gateway.resume('synthetic-live-retest',{token:result.token,binding,callID:call.id,result:response.result});
 }
 const {token,...safeResult}=result;evidence.result=safeResult;
 assert.equal(result.status,'completed');
 const compared=trace.find(t=>t.call.name==='runCounterfactual'&&t.call.arguments.retestPlan&&t.result?.observation?.comparison);
 assert.ok(compared,'model must execute a controlled retest');
 assert.equal(compared.result.observation.baseline.resources['res.water.stored'].amount,0);
 assert.equal(compared.result.observation.controlledRetest.resources['res.water.stored'].amount,5);
 assert.ok(compared.result.observation.comparison.remainingRequirementIDs.length>0);
 assert.ok(compared.result.observation.comparison.remainingUnknownIDs.length>0);
 assert.ok(trace.some(t=>t.call.name==='evaluateCandidateAction'));
 const committed=await host.request({op:'directorCommit',session:state.session,binding,proposal:result.proposal});evidence.committed=committed;
 assert.deepEqual(committed.session.inventory,state.session.inventory);assert.deepEqual(committed.session.initial,state.session.initial);
 assert.equal(committed.receipt.inventory.items[0].locationID,'sp-kitchen');
 assert.deepEqual((await host.request({op:'query',session:committed.session})).receipt,committed.receipt);
 evidence.passed=true;
 await writeFile('../../fixtures/ai/stress-retest-live.json',JSON.stringify({...evidence,metrics:gateway.metrics,providerCalls:provider.budget.calls,estimatedUSD:provider.budget.spentUSD},null,2)+'\n');
 console.log(JSON.stringify({passed:true,liveModel:true,providerCalls:provider.budget.calls,estimatedUSD:provider.budget.spentUSD,tools:trace.map(t=>t.call.name),baselineGallons:0,retestGallons:5,sourceUnchanged:true,actualExerciseLocationUnchanged:true,remainingGaps:compared.result.observation.comparison.remainingRequirementIDs.length,remainingUnknowns:compared.result.observation.comparison.remainingUnknownIDs.length}));
}catch(error){await writeFile('../../fixtures/ai/stress-retest-live-failure-'+Date.now()+'.json',JSON.stringify({...evidence,passed:false,failure:error instanceof Error?error.name:'evaluation_failure',metrics:gateway.metrics,providerCalls:provider.budget.calls,estimatedUSD:provider.budget.spentUSD},null,2)+'\n');throw error;}finally{host.close();}
