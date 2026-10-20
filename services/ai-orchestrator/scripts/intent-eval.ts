import {writeFile,readFile} from 'node:fs/promises';
import {Host} from './host.js';
import {IntentInterpreter,inputDigest} from '../src/intents.js';
import {GeminiProvider,type AgentProvider} from '../src/provider.js';
import {Gateway} from '../src/gateway.js';
import {minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
import {executeDirectorTool} from './director-tools.js';
const host=new Host();const live=process.env.DRYRUN_LIVE_INTENT==='1';const path=live?'../../fixtures/ai/user-intent-live.json':'../../fixtures/ai/user-intent.json';
const outputs:unknown[]=[];
try{
 if(process.env.DRYRUN_REPLAY_INTENT==='1'){
  for(const file of ['../../fixtures/ai/user-intent.json','../../fixtures/ai/user-intent-live.json']){
   const fixture=JSON.parse(await readFile(file,'utf8'));const actual=await host.request({op:'query',session:fixture.session});
   if(JSON.stringify(actual.receipt)!==JSON.stringify(fixture.receipt))throw new Error('receipt_mismatch');
   console.log(JSON.stringify({file,replay:true}));
  }
 }else{
 const provider:AgentProvider=live?new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??''):{async turn(input){
  const text=JSON.stringify(input.history).toLowerCase();const value=text.includes('teleport')?{status:'unsupported'}:text.includes('mom')?{status:'needsClarification',question:'Which person and destination?'}:{status:'proposed',commands:[{kind:'useStoredWater',value:'essential'}]};
  return {steps:[],calls:[],text:JSON.stringify(value),usage:{}};
 }};
 const interpreter=new IntentInterpreter(provider);
 let state=await host.request({op:'initialize',scenarioID:'water-outage',sample:'oak'});
 state=await host.request({op:'commit',session:state.session,commit:{id:'loss',actor:'director',baseRevision:0,commands:[{kind:'schedule',target:'evt.water-outage.well-pump-failure',minute:0},{kind:'advance',minute:0}]}});
 const source=structuredClone(state.session);
 const context={people:state.session.initial.household.people.map((p:any,i:number)=>({id:p.id,selected:i===0})),rooms:state.homeScene.rooms.map((r:any)=>({id:r.id,use:r.use})),portals:state.homeScene.portals.map((p:any)=>p.id),equipment:state.session.initial.household.equipment.map((e:any)=>({id:e.id,backupIDs:e.compatibleBackupIDs})),contacts:state.session.initial.household.contacts.map((c:any)=>c.id),supplies:[],choices:[]};
 function bind(){return {sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home?.revision??0};}
 for(const [index,text] of ['Use stored water only for drinking and cooking.','Have mom move it over there.','Teleport everyone to safety.'].entries()){
  const submission={id:'input-'+index,text,binding:bind()};
  const intent=await interpreter.interpret({contractVersion:'dryrun.ai/1',requestID:'intent-'+index,synthetic:true,submission:{...submission,inputDigest:inputDigest(text)},context});
  outputs.push({submission,intent});
  const expected=['proposed','needsClarification','unsupported'][index];if(intent.status!==expected)throw new Error('intent_semantics_'+index);
  if(index===0){state=await host.request({op:'interpretCommit',session:state.session,submission,intent});if(state.intentResult.status!=='committed'||state.session.commits.at(-1).commands[0].value!=='essential')throw new Error('wrong_committed_action');}
 }
 const actionReceipt=structuredClone(state.receipt);const adaptiveTrace:unknown[]=[];let metrics:unknown;
 if(live){
  const gateway=new Gateway(provider);const binding=bind();
  let result:any=await gateway.start('synthetic-intent',{contractVersion:'dryrun.ai/1',requestID:'intent-director',role:'director',synthetic:true,context:{binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),household:state.householdContext,homeScene:state.homeScene,profiles:state.directorProfiles,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending,lastAction:state.lastAction,recentActions:state.recentActions,learningObjectives:['Inspect the actual committed water-conservation consequences and select a useful next decision.']}});
  while(result.status==='needs_client_tools'){
   const call=result.calls[0],preview=await executeDirectorTool(host,state,binding,call);adaptiveTrace.push({tool:call.name,arguments:call.arguments,result:preview.result});
   result=await gateway.resume('synthetic-intent',{token:result.token,binding,callID:call.id,result:preview.result});
  }
  if(result.status!=='completed')throw new Error('director_unavailable');
  state=await host.request({op:'directorCommit',session:state.session,binding,proposal:result.proposal});adaptiveTrace.push({proposal:result.proposal,committed:state.receipt});metrics=gateway.metrics;
 }
 const replay=await host.request({op:'query',session:state.session});if(JSON.stringify(replay.receipt)!==JSON.stringify(state.receipt))throw new Error('replay_mismatch');
 if(JSON.stringify(source.initial)!==JSON.stringify(state.session.initial))throw new Error('real_facts_changed');
 await writeFile(path,JSON.stringify({synthetic:true,liveModel:live,model:live?'gemini-3.1-flash-lite':'deterministic-fixture',intentCalls:interpreter.calls,intentUsage:interpreter.usage,outputs,actionReceipt,adaptiveTrace,metrics,session:state.session,receipt:state.receipt},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',live,intentCalls:interpreter.calls,clarification:true,unsupported:true,hostCommit:true,adaptive:live,replay:true}));
 }
}catch(error){await writeFile('/tmp/dryrun-intent-failure.json',JSON.stringify({synthetic:true,live,outputs,error:error instanceof Error?error.message:'failure'},null,2));throw error;}finally{host.close();}
