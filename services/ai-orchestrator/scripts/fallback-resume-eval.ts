import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {Gateway} from '../src/gateway.js';
import {GeminiProvider,SpendBudget,type AgentProvider} from '../src/provider.js';
import {directorContext,minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
import {executeDirectorTool} from './director-tools.js';
const live=process.env.DRYRUN_RESUME_LIVE==='1';
const provider:AgentProvider=live?new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??''):{async turn(input){
 const first=input.history[0];if(first?.type!=='user_input'||!Array.isArray(first.content)||first.content[0]?.type!=='text')throw new Error('test_context_missing');
 const context=directorContext.parse(JSON.parse(first.content[0].text)),commands=[{kind:'advance',minute:context.snapshot.simMinute+60},{kind:'requestDecision'}];
 if(!input.history.some(step=>step.type==='function_result')){const call={type:'function_call' as const,id:'resume-preview',name:'evaluateCandidateAction',arguments:{commands}};return {steps:[call],calls:[call],text:'',usage:{}};}
 return {steps:[],calls:[],text:JSON.stringify({commands,purpose:'Continue from the committed conservation follow-up',evidenceIDs:[context.lastAction!.id]}),usage:{}};
}};
const gateway=new Gateway(provider),host=new Host(),trace:unknown[]=[];
const path=`../../fixtures/ai/fallback-resume-${live?'live':'offline'}.json`;
try {
 const recorded=JSON.parse(await readFile('../../fixtures/ai/integrated-pipeline-policy.json','utf8')).outputs.find((o:any)=>o.sample==='oak');
 let state=await host.request({op:'query',session:recorded.session});
 assert.deepEqual(state.receipt,recorded.adaptiveTrace.at(-1).committed);
 const source=structuredClone(state.session),initial=JSON.stringify(source.initial),seed=JSON.stringify(source.inventory);
 trace.push({phase:'recorded-live-Gemini-origin',session:source,receipt:state.receipt,newModelCalls:0});
 state=await host.request({op:'commit',session:state.session,commit:{id:'offline-all-use',actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'useStoredWater',value:'all'}]}});
 const minute=state.receipt.snapshot.simMinute;
 assert.ok(state.directorProfiles.some((p:any)=>p.id==='evt.water-outage.well-quality-unknown'),'applicable_pending_profile_missing');
 state=await host.request({op:'commit',session:state.session,commit:{id:'pending-quality-review',actor:'director',baseRevision:state.receipt.revision,commands:[{kind:'schedule',target:'evt.water-outage.well-quality-unknown',minute:minute+120}]}});
 const beforePause=structuredClone(state.receipt);
 state=await host.request({op:'fallback',session:state.session});
 assert.deepEqual(state.receipt.snapshot,beforePause.snapshot);assert.deepEqual(state.receipt.pending,beforePause.pending);assert.deepEqual(state.receipt.inventory,beforePause.inventory);
 assert.equal(state.receipt.directorState.awaitingUserAction,true);
 trace.push({phase:'local-fallback-pause',before:beforePause,session:state.session,receipt:state.receipt});
 const restored=await host.request({op:'query',session:JSON.parse(JSON.stringify(state.session))});assert.deepEqual(restored.receipt,state.receipt);state=restored;
 state=await host.request({op:'commit',session:state.session,commit:{id:'resumed-essential-use',actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'useStoredWater',value:'essential'}]}});
 assert.equal(state.lastAction.id,'resumed-essential-use');assert.equal(state.lastAction.value,'essential');
 assert.deepEqual(state.recentActions.slice(-2).map((a:any)=>a.value),['all','essential']);
 const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home?.revision??0};
 const context=directorContext.parse({binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),household:state.householdContext,homeScene:state.homeScene,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending,closedPortalIDs:state.receipt.closedPortalIDs,profiles:state.directorProfiles,lastAction:state.lastAction,recentActions:state.recentActions,learningObjectives:['Resume the same exercise after the local pause. Inspect the latest committed essential-only action and actual remaining resources.','Existing pending events remain scheduled; do not duplicate them. Choose a useful next boundary or finish based on actual consequences.']});
 let result:any=await gateway.start('synthetic-resume',{contractVersion:'dryrun.ai/1',requestID:'return-to-director',role:'director',synthetic:true,context});
 trace.push({phase:'return-to-director',context});
 while(result.status==='needs_client_tools'){
  const call=result.calls[0],tool=await executeDirectorTool(host,state,binding,call);trace.push({tool:call.name,arguments:call.arguments,receipt:tool.receipt});
  result=await gateway.resume('synthetic-resume',{token:result.token,binding,callID:call.id,result:tool.result});
 }
 trace.push({result});if(result.status!=='completed')throw new Error('resume_director_unavailable');
 state=await host.request({op:'directorCommit',session:state.session,proposal:result.proposal,binding});
 assert.deepEqual(state.session.commits.slice(0,source.commits.length),source.commits);
 assert.equal(JSON.stringify(state.session.initial),initial);assert.equal(JSON.stringify(state.session.inventory),seed);
 const replay=await host.request({op:'query',session:state.session});assert.deepEqual(replay.receipt,state.receipt);
 const fired=state.receipt.snapshot.firedEventIDs;assert.equal(new Set(fired).size,fired.length);
 const cost=new SpendBudget(1);if(live)for(const usage of gateway.metrics.usage)cost.charge(usage,'gemini-3.1-flash-lite');
 await writeFile(path,JSON.stringify({estimatedUSD:live?cost.spentUSD:0,synthetic:true,liveReturnToGemini:live,recordedOrigin:'integrated-pipeline-policy.json oak; no new call for origin',newModelCalls:live?gateway.metrics.calls:0,model:live?'gemini-3.1-flash-lite':null,sdk:'2.30.0',prompt:gateway.metrics.prompt,metrics:gateway.metrics,trace,finalSession:state.session,finalReceipt:state.receipt,assertions:{pausePreservesSnapshot:true,pendingPreserved:true,sourceUnchanged:true,committedPrefixPreserved:true,latestActionFromHost:true,replay:true,noDuplicateFiredProfiles:true}},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',liveReturnToGemini:live,newModelCalls:live?gateway.metrics.calls:0,revision:state.receipt.revision,simMinute:state.receipt.snapshot.simMinute,pausePreserved:true,pendingPreserved:true,latestAction:state.lastAction.id,replay:true}));
}catch(error){await writeFile(path.replace('.json','-failure.json'),JSON.stringify({synthetic:true,liveReturnToGemini:live,trace,metrics:gateway.metrics},null,2)+'\n');throw error;}finally{host.close();}
