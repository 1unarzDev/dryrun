import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {Gateway} from '../src/gateway.js';
import {GeminiProvider,type AgentProvider} from '../src/provider.js';
import {minimizedSnapshot} from '../src/contracts.js';
import {executeDirectorTool} from './director-tools.js';
const live=process.env.DRYRUN_LIVE_SPATIAL==='1';const host=new Host();
const trace:unknown[]=[];const replies:unknown[]=[];let metrics:unknown;let final:any;
try{
 let state=await host.request({op:'initialize',scenarioID:'home-fire'});
 const person=state.session.initial.household.people[0].id;
 state=await host.request({op:'commit',session:state.session,commit:{id:'submitted-move',actor:'user',baseRevision:0,commands:[{kind:'moveTo',target:person,value:'sp-living'}]}});
 const source=structuredClone(state);
 const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home.revision};
 const context={binding,snapshot:minimizedSnapshot(state.receipt),household:state.householdContext,homeScene:state.homeScene,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending,closedPortalIDs:state.receipt.closedPortalIDs,profiles:state.directorProfiles,lastAction:{id:'submitted-move',kind:'moveTo',target:person,value:'sp-living'},learningObjectives:['Start a short hypothetical fire rehearsal after this committed occupant move. Choose a recorded room as an assumed origin and a reviewed spatial profile.', 'Preview the incident AND its applied scene/routes, then commit a bounded incident/pacing proposal leading to a useful decision. Keep household facts unchanged.']};
 const commands=[{kind:'startIncident',target:'evt.home-fire.fire-origin',value:'sp-kitchen',hazard:'homeFire',minute:0},{kind:'advance',minute:0}];
 let turn=0;
 const fixture:AgentProvider={async turn(){turn++;if(turn<=2){const call={type:'function_call' as const,id:'call-'+turn,name:turn===1?'queryRoutes':'evaluateCandidateAction',arguments:turn===1?{}:{commands}};return {steps:[call],calls:[call],text:'',usage:{}};}return {steps:[],calls:[],usage:{},text:JSON.stringify({commands,purpose:'A recorded room is the hypothetical origin; inspect the host-computed routes before choosing the next action.',evidenceIDs:[]})};}};
 const provider=live?new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??''):fixture;
 const gateway=new Gateway({async turn(input){const reply=await provider.turn(input);replies.push({text:reply.text,calls:reply.calls.map(c=>({id:c.id,name:c.name,arguments:c.arguments}))});return reply;}});metrics=gateway.metrics;
 let result:any=await gateway.start('synthetic-spatial',{contractVersion:'dryrun.ai/1',requestID:'spatial-policy',role:'director',synthetic:true,context});
 while(result.status==='needs_client_tools'){
  const call=result.calls[0];const tool=await executeDirectorTool(host,state,binding,call);
  trace.push({tool:call.name,arguments:call.arguments,result:tool.result});
  assert.equal((await host.request({op:'query',session:state.session})).receipt.contextDigest,binding.contextDigest);
  result=await gateway.resume('synthetic-spatial',{token:result.token,binding,callID:call.id,result:tool.result});
 }
 assert.equal(result.status,'completed');
 const proposal=result.proposal;
 state=await host.request({op:'directorCommit',session:state.session,proposal,binding});
 assert.ok(proposal.commands.some((c:any)=>c.kind==='startIncident'));
 assert.ok(state.receipt.directorState.stageID);
 assert.equal(state.receipt.directorState.activeIncidentCount,state.receipt.finished?0:1);
 assert.ok(source.homeScene.rooms.some((r:any)=>r.id===state.receipt.snapshot.spatialState.originSpaceID));
 assert.deepEqual(state.session.initial,source.session.initial);
 assert.deepEqual((await host.request({op:'query',session:state.session})).receipt,state.receipt);
 final={synthetic:true,liveModel:live,model:live?'gemini-3.1-flash-lite':'deterministic_protocol_fixture',source,context,trace,replies,proposal,committed:state,metrics:gateway.metrics};
 await writeFile('../../fixtures/ai/spatial-policy'+(live?'-live':'')+'.json',JSON.stringify(final,null,2)+'\n');
 console.log(JSON.stringify({status:'passed',liveModel:live,calls:gateway.metrics.calls,origin:state.receipt.snapshot.spatialState.originSpaceID,stage:state.receipt.directorState.stageID,replay:true}));
}catch(error){await writeFile('../../fixtures/ai/spatial-policy-failure.json',JSON.stringify({synthetic:true,liveModel:live,trace,replies,metrics},null,2)+'\n');throw error;}finally{host.close();}
