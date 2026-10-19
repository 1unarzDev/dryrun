import {executeDirectorTool} from './director-tools.js';
import {writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {Gateway} from '../src/gateway.js';
import {GeminiProvider} from '../src/provider.js';
import {minimizedSnapshot} from '../src/contracts.js';
const host=new Host();
const gateway=new Gateway(new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??'',process.env.DRYRUN_MODEL??'gemini-3.1-flash-lite'));
const trace:unknown[]=[];
function safeResult(result:any){const {token,...safe}=result;return safe;}
try {
 let state=await host.request({op:'initialize',scenarioID:'water-outage'});
 const loss=state.profiles.find((p:any)=>p.id==='evt.water-outage.well-pump-failure');
 state=await host.request({op:'commit',session:state.session,commit:{id:'initial-incident',actor:'director',baseRevision:0,commands:[{kind:'schedule',target:loss.id,minute:0},{kind:'advance',minute:0}]}});
 state=await host.request({op:'commit',session:state.session,commit:{id:'submitted-water-action',actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'useStoredWater',value:process.env.DRYRUN_ACTION??'all'}]}});
 state=await host.request({op:'commit',session:state.session,commit:{id:'observe-consequences',actor:'director',baseRevision:state.receipt.revision,commands:[{kind:'advance',minute:720}]}});
 for(let turn=0;turn<2;turn++){
 if(state.receipt.directorState?.awaitingUserAction){state=await host.request({op:'commit',session:state.session,commit:{id:`submitted-followup-${turn}`,actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'useStoredWater',value:process.env.DRYRUN_FOLLOWUP_ACTION??'essential'}]}});trace.push({submittedFollowup:state});}

 const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home?.revision??0};
 const context={binding,learningObjectives:['Compare stored-water policies and protect continuity without inventing supplies'],snapshot:minimizedSnapshot(state.receipt),directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending,closedPortalIDs:state.receipt.closedPortalIDs,profiles:state.directorProfiles??state.profiles.map((p:any)=>({id:p.id,rule:p.rule,minute:p.minute})),lastAction:state.lastAction,recentActions:state.recentActions};
 let result:any=await gateway.start('synthetic-installation',{contractVersion:'dryrun.ai/1',requestID:`smoke-${turn}`,role:'director',synthetic:true,context});trace.push({context,result:safeResult(result)});
 while(result.status==='needs_client_tools'){
 const call=result.calls[0];const preview=await executeDirectorTool(host,state,binding,call);
 trace.push({tool:call.name,arguments:call.arguments,preview:preview.receipt});
 result=await gateway.resume('synthetic-installation',{token:result.token,binding,callID:call.id,result:preview.result});trace.push({result:safeResult(result)});
 }
 if(result.status!=='completed'){await writeFile('../../fixtures/ai/failed-smoke.json',JSON.stringify({synthetic:true,trace,metrics:gateway.metrics},null,2));throw new Error('director_unavailable');}
 state=await host.request({op:'directorCommit',session:state.session,proposal:result.proposal,binding});trace.push({committed:state});if(state.receipt.finished)break;
 }
 const replay=await host.request({op:'query',session:state.session});if(replay.receipt.contextDigest!==state.receipt.contextDigest)throw new Error('replay_mismatch');
 await writeFile(`../../fixtures/ai/adaptive-trace-${process.env.DRYRUN_ACTION??'all'}.json`,JSON.stringify({synthetic:true,model:process.env.DRYRUN_MODEL??'gemini-3.1-flash-lite',sdk:'2.30.0',recordedAt:new Date().toISOString(),metrics:gateway.metrics,trace},null,2));
 console.log(JSON.stringify({status:'passed',calls:gateway.metrics.calls,revision:state.receipt.revision,digest:state.receipt.contextDigest}));
}finally{host.close();}
