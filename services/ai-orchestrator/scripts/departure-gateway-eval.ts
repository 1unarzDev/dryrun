import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {Gateway} from '../src/gateway.js';
import {directorContext,minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
import {directorProviderSchemas} from '../src/director-provider-schema.js';
import {executeDirectorTool} from './director-tools.js';
import type {AgentProvider} from '../src/provider.js';

// Actual Core departures, not invented relocated flags. Providers are synthetic:
// this verifies policy/transport/commit/replay, never live model quality.
const host=new Host(),cases:any[]=[];
try {
 const fixture=JSON.parse(await readFile('../../fixtures/ai/departure-fallback.json','utf8'));
 for(const row of fixture.cases.filter((c:any)=>c.departed)){
  const state=await host.request({op:'query',session:row.departed.session});
  const original=JSON.stringify(state.session);
  const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home.revision};
  const context=directorContext.parse({binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),experience:state.receipt.experience,household:state.householdContext,homeScene:state.homeScene,profiles:state.directorProfiles,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending});
  assert(context.experience?.relocated);assert(context.pending?.length);
  for(const schema of Object.values(directorProviderSchemas(context))){
   const commands=JSON.stringify(schema.properties!.commands??schema.properties!.command);
   assert(commands.includes('finish'));for(const kind of ['advance','requestDecision','schedule','startIncident'])assert(!commands.includes(`"${kind}"`));
  }
  const rejected:any[]=[];
  for(const commands of [[{kind:'requestDecision'}],[{kind:'advance',minute:180}],[{kind:'schedule',target:context.profiles.find(p=>!p.spatial)!.id,minute:180}]]){
   let attempts=0;
   const provider:AgentProvider={async turn(){attempts++;const call={type:'function_call' as const,id:'reject-'+attempts,name:'evaluateCandidateAction',arguments:{commands}};return {steps:[call],calls:[call],text:'',usage:{}};}};
   const gateway=new Gateway(provider);
   const result:any=await gateway.start('synthetic',{contractVersion:'dryrun.ai/1',requestID:'reject-'+commands[0]!.kind,role:'director',synthetic:true,context});
   assert.equal(result.status,'unavailable','must reject before exposing host preview work');assert.equal(attempts,2,'only one repair');
   assert.equal(JSON.stringify(state.session),original);rejected.push({commands,result,attempts});
  }
  let turns=0;
  const provider:AgentProvider={async turn(){
   if(++turns===1){const call={type:'function_call' as const,id:'finish-preview',name:'evaluateCandidateAction',arguments:{command:{kind:'finish'}}};return {steps:[call],calls:[call],text:'',usage:{}};}
   return {steps:[],calls:[],text:JSON.stringify({commands:[{kind:'finish'}],purpose:'The recorded departure was committed. End this home exercise; destination temperature, services and equipment continuity remain unassessed.',evidenceIDs:[]}),usage:{}};
  }};
  const gateway=new Gateway(provider);let result:any=await gateway.start('synthetic',{contractVersion:'dryrun.ai/1',requestID:'finish',role:'director',synthetic:true,context});
  assert.equal(result.status,'needs_client_tools');
  const tool=await executeDirectorTool(host,state,binding,result.calls[0]);
  result=await gateway.resume('synthetic',{token:result.token,binding,callID:result.calls[0].id,result:tool.result});
  assert.equal(result.status,'completed');assert.equal(JSON.stringify(state.session),original);
  const finished=await host.request({op:'directorCommit',session:state.session,proposal:result.proposal,binding});assert(finished.receipt.finished);
  for(const key of ['snapshot','inventory','experience','pending','routes'])assert.deepEqual(finished.receipt[key],state.receipt[key],key);
  assert.deepEqual(finished.session.initial,state.session.initial);
  const replay=await host.request({op:'query',session:JSON.parse(JSON.stringify(finished.session))});assert.deepEqual(replay.receipt,finished.receipt);
  cases.push({scenarioID:row.scenarioID,context,rejected,proposal:result.proposal,finished});
 }
 assert.equal(cases.length,3);
 await writeFile('../../fixtures/ai/departure-gateway.json',JSON.stringify({synthetic:true,liveModelCalls:0,mode:'actual Core departure -> gateway policy/preview -> host commit -> exact replay',cases,native:'pending',humanReview:'pending'},null,2)+'\n');
 console.log(JSON.stringify({passed:true,hazards:3,rejectedBeforeHostPreview:9,finishCommitAndExactReplay:3,pendingTimeResourcesPreserved:true,liveModelCalls:0,native:'pending'}));
}finally{host.close();}
