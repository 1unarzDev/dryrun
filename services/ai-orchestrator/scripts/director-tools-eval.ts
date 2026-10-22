import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {executeDirectorTool} from './director-tools.js';
import {Gateway} from '../src/gateway.js';
import {minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
import {GeminiProvider,type AgentProvider} from '../src/provider.js';
const live=process.env.DRYRUN_LIVE_TOOLS==='1';
const host=new Host();const trace:unknown[]=[];
try{
 const state=await host.request({op:'initialize',scenarioID:'water-outage'});
 const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home.revision};
 for(const name of ['inspectScene','queryRoutes','evaluateResources','inspectDependencies','runCounterfactual','evaluateCandidateAction']){
  const args=name==='runCounterfactual'?{profileIDs:[state.profiles[0].id]}:name==='evaluateCandidateAction'?{command:{kind:'advance',minute:120}}:{};
  const output=await executeDirectorTool(host,state,binding,{name,arguments:args});
  trace.push({name,arguments:args,result:output.result});
  if(name!=='evaluateCandidateAction')assert.equal(output.receipt.contextDigest,state.receipt.contextDigest);
  assert.equal((await host.request({op:'query',session:state.session})).receipt.contextDigest,state.receipt.contextDigest);
 }
 let turn=0;
 const provider:AgentProvider={async turn(){turn++;if(turn<=2){const call={type:'function_call' as const,id:'call-'+turn,name:turn===1?'inspectDependencies':'evaluateCandidateAction',arguments:turn===1?{}:{command:{kind:'advance',minute:120}}};return {steps:[call],text:'',calls:[call],usage:{}};}return {steps:[],calls:[],usage:{},text:JSON.stringify({commands:[{kind:'advance',minute:120}],purpose:'Inspect dependencies then advance to a bounded decision.',evidenceIDs:[]})};}};
 const gateway=new Gateway(live?new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??''):provider);
 let result:any=await gateway.start('synthetic-tools',{contractVersion:'dryrun.ai/1',requestID:'tool-chain',role:'director',synthetic:true,context:{binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),learningObjectives:['Investigate a recorded dependency with inspectDependencies, then preview an advance and request the next useful decision.'],directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending,closedPortalIDs:state.receipt.closedPortalIDs,profiles:state.directorProfiles??state.profiles.map((p:any)=>({id:p.id,rule:p.rule,minute:p.minute}))}});
 while(result.status==='needs_client_tools'){
  const call=result.calls[0];const output=await executeDirectorTool(host,state,binding,call);trace.push({continuation:call.name,arguments:call.arguments,result:output.result});
  result=await gateway.resume('synthetic-tools',{token:result.token,binding,callID:call.id,result:output.result});
 }
 if(result.status!=='completed'){await writeFile('../../fixtures/ai/director-tools-failure.json',JSON.stringify({synthetic:true,live,trace,metrics:gateway.metrics,result},null,2)+'\n');console.log(JSON.stringify({status:result.status,metrics:gateway.metrics}));}
 assert.equal(result.status,'completed');
 const committed=await host.request({op:'directorCommit',session:state.session,proposal:result.proposal,binding});
 if(!live)assert.equal(committed.receipt.snapshot.simMinute,120);
 assert.equal((await host.request({op:'query',session:committed.session})).receipt.contextDigest,committed.receipt.contextDigest);
 await writeFile('../../fixtures/ai/director-tools-evaluation'+(live?'-live':'')+'.json',JSON.stringify({synthetic:true,provider:live?'gemini-3.1-flash-lite':'deterministic_protocol_fixture',metrics:gateway.metrics,trace,proposal:result.proposal,receipt:committed.receipt},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',tools:6,providerCalls:gateway.metrics.calls,commitReplay:true,liveModel:live}));
}finally{host.close();}
