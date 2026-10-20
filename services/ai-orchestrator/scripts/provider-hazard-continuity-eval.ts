import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {GroqClient} from '../src/groq.js';
import {GeminiPrimaryFallback} from '../src/provider-fallback.js';
import {Gateway} from '../src/gateway.js';
import {minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
import {executeDirectorTool} from './director-tools.js';
import {Host} from './host.js';
const fixture=JSON.parse(await readFile('../../fixtures/ai/six-hazard-mechanics.json','utf8'));
const host=new Host();let calls=0;
try{
 for(const hazard of ['home-fire','tornado','flash-flood','freeze-power-loss','heat-grid-strain','water-outage']){
  // Completed flood departure intentionally has no further at-home actions.
  const branch=fixture.branches.find((b:any)=>b.hazard===hazard&&b.expected.experience.feasibleCommands.length>0);assert(branch);
  let state=await host.request({op:'query',session:{...branch.session,initial:{...branch.session.initial,household:fixture.household,home:fixture.home}}});
  if(state.receipt.directorState?.awaitingUserAction)state=await host.request({op:'commit',session:state.session,commit:{id:'synthetic-recorded-resume',actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'unsupported'}]}});
  const frozen=JSON.stringify(state.session),snapshot=structuredClone(state.receipt.snapshot),pending=structuredClone(state.receipt.pending),mechanics=state.receipt.experience.mechanicsVersion;
  const action=state.receipt.experience.feasibleCommands[0];assert(action,`${hazard} lacks a feasible continuation`);
  const provider=new GeminiPrimaryFallback({async turn(){throw new Error('provider_rate_limited');}},new GroqClient('synthetic',undefined,async(_url,request)=>{
   calls++;const body=JSON.parse(String(request?.body));assert(!body.tools?.some((t:any)=>t.type==='browser_search'));assert(!JSON.stringify(body).includes('signature'));
   const message=body.tools?{tool_calls:[{id:'synthetic-preview',type:'function',function:{name:'evaluateCandidateAction',arguments:JSON.stringify({command:{kind:'requestDecision'}})}}]}:{content:JSON.stringify({commands:[{kind:'requestDecision'}],purpose:'Synthetic adapter-continuity check using the actual selected hazard receipt and host affordance.',evidenceIDs:[],suggestedActions:[{id:'synthetic-action',label:'Perform the recorded exercise action',fact:'The host reports this exact action as feasible.',implication:'The deterministic host must compute its effects.',commands:[action]}]})};
   return Response.json({choices:[{message}],usage:{prompt_tokens:1,completion_tokens:1}});
  }));
  const gateway=new Gateway(provider);
  const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home?.revision??0};
  const context={binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),experience:state.receipt.experience,household:state.householdContext,homeScene:state.homeScene,profiles:state.directorProfiles,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending};
  let result:any=await gateway.start('synthetic-'+hazard,{contractVersion:'dryrun.ai/1',requestID:hazard,role:'director',synthetic:true,providerConsent:['gemini','groq'],context});
  assert.equal(result.status,'needs_client_tools');assert.equal(result.providerAttemptGeneration,1);
  while(result.status==='needs_client_tools'){
   const call=result.calls[0],tool=await executeDirectorTool(host,state,binding,call);
   result=await gateway.resume('synthetic-'+hazard,{token:result.token,binding,callID:call.id,result:tool.result});
  }
  assert.equal(result.status,'completed');assert.equal(result.providerAttemptGeneration,1);
  assert.equal(JSON.stringify(state.session),frozen); // No model/network mutation or time advance.
  const noMutation=await host.request({op:'query',session:state.session});assert.deepEqual(noMutation.receipt.snapshot,snapshot);assert.deepEqual(noMutation.receipt.pending,pending);
  state=await host.request({op:'directorCommit',session:state.session,proposal:result.proposal,binding});
  const commit={id:'synthetic-selected-'+hazard,actor:'user',baseRevision:state.receipt.revision,commands:[action]};
  state=await host.request({op:'commit',session:state.session,commit});
  const resolution=await host.request({op:'reconcileCommit',session:JSON.parse(JSON.stringify(state.session)),commit});assert.equal(resolution.commitResolution.status,'committed');
  await assert.rejects(host.request({op:'commit',session:state.session,commit}),/duplicate/);
  const replay=await host.request({op:'query',session:state.session});assert.deepEqual(replay.receipt,state.receipt);assert.equal(state.session.initial.scenarioID,hazard);assert.equal(state.receipt.experience.mechanicsVersion,mechanics);
  console.log(JSON.stringify({hazard,passed:true,provider:'Groq adapter with synthetic HTTP responses',primary429:'injected',stateContinuity:true,replay:'exact',lostAcknowledgement:'reconciled',duplicate:'rejected',liveModelTested:false}));
 }
 console.log(JSON.stringify({hazards:6,syntheticAdapterCalls:calls,liveModelCalls:0,scoreCredit:'no score operation or preparation fact mutation; separate practice score suite'}));
}finally{host.close();}
