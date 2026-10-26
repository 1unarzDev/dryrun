import {readFile,writeFile,access} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {Host} from './host.js';
import {Gateway} from '../src/gateway.js';
import {GeminiProvider} from '../src/provider.js';
import {minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
import {executeDirectorTool} from './director-tools.js';
const path=process.env.DRYRUN_HOUSING_DIRECTOR_OUTPUT??'../../fixtures/ai/housing-director-live-'+Date.now()+'.json';
try{await access(path);throw new Error('output_already_exists');}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}
const elevatorOnly=process.env.DRYRUN_HOUSING_DIRECTOR_ELEVATOR_ONLY==='1';
const host=new Host(),provider=new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??'');
const replies:any[]=[],trace:any[]=[];
const sourceHashes=Object.fromEntries(await Promise.all(['scripts/housing-director-eval.ts','src/gateway.ts','src/features.ts','src/output-quality.ts','src/contracts.ts'].map(async p=>[p,createHash('sha256').update(await readFile(p)).digest('hex')])));
try{
 const seed=await host.request({op:'initialize',scenarioID:'home-fire'});
 const input=seed.session.initial;
 input.home=JSON.parse(await readFile('../../fixtures/homes/home-sample-apartment-complex.json','utf8'));
 if(elevatorOnly)input.home.connectors=input.home.connectors.map((c:any,i:number)=>({...c,id:'synthetic-elevator-'+i,kind:'elevator'}));
 input.household.housing.homeType='apartment';input.household.housing.floorCount=3;
 input.household.people=[{...input.household.people[0],needs:[],sleepingSpaceID:'sp-bed1',helperPersonID:undefined}];
 let state=await host.request({op:'initialize',input});
 const initial=structuredClone(state);
 state=await host.request({op:'commit',session:state.session,commit:{id:'submitted-move-to-living',actor:'user',baseRevision:0,commands:[{kind:'moveTo',target:input.household.people[0].id,value:'sp-living'}]}});
 const afterAction=structuredClone(state);
 const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:input.household.revision,homeRevision:input.home.revision};
 const context={binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),household:state.householdContext,homeScene:state.homeScene,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending,closedPortalIDs:state.receipt.closedPortalIDs,profiles:state.directorProfiles,learningObjectives:[elevatorOnly?'Respond to committed living-room move. Elevator-only graph has no supported egress. Preview kitchen fire, pause for posted-procedure/assistance review. Never invent an exit or occupant action.':'Respond to the committed living-room move; preview a hypothetical kitchen-origin fire and the shared apartment stair dependency, then pause for a useful family decision. No occupant action commits.'],lastAction:state.lastAction,recentActions:state.recentActions};
 const gateway=new Gateway({async turn(input){const reply=await provider.turn(input);replies.push({text:reply.text,calls:reply.calls.map(c=>({name:c.name,arguments:c.arguments})),usage:reply.usage});return reply;}});
 let result:any=await gateway.start('synthetic-housing-director',{contractVersion:'dryrun.ai/1',requestID:'apartment-action-follow-up',role:'director',synthetic:true,context});
 while(result.status==='needs_client_tools'){
  const call=result.calls[0];const tool=await executeDirectorTool(host,state,binding,call);
  assert.equal((await host.request({op:'query',session:state.session})).receipt.contextDigest,binding.contextDigest);
  trace.push({tool:call.name,arguments:call.arguments,result:tool.result});
  result=await gateway.resume('synthetic-housing-director',{token:result.token,binding,callID:call.id,result:tool.result});
 }
 assert.equal(result.status,'completed');assert.ok(trace.some(t=>t.tool==='evaluateCandidateAction'));
 const beforeCommit=structuredClone(state);
 state=await host.request({op:'directorCommit',session:state.session,proposal:result.proposal,binding});
 const replay=await host.request({op:'query',session:state.session});assert.deepEqual(replay.receipt,state.receipt);
 assert.deepEqual(state.session.initial,beforeCommit.session.initial);
 const duplicate=await host.request({op:'directorCommit',session:state.session,proposal:result.proposal,binding}).then(()=>false,()=>true);
 assert.ok(duplicate);
 assert.ok(result.proposal.commands.some((c:any)=>c.kind==='startIncident'));
 assert.equal(state.receipt.directorState.awaitingUserAction,true);
 if(elevatorOnly){
  assert.ok(state.receipt.routes.length>0);
  for(const route of state.receipt.routes){assert.equal(route.primary,undefined);assert.ok(route.exclusions.some((e:any)=>e.reason==='elevatorNotUsedForEgress'));}
 }
 await writeFile(path,JSON.stringify({synthetic:true,liveModel:true,elevatorOnly,sourceHashes,model:provider.model,calls:provider.budget.calls,budgetAccountedUSD:provider.budget.spentUSD,initial,afterAction,context,replies,trace,proposal:result.proposal,committed:state,replay:true,staleDuplicateRejected:true,unchangedRealSource:true},null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify({passed:true,calls:provider.budget.calls,tools:trace.map(t=>t.tool),revision:state.receipt.revision,awaitingUserAction:true,replay:true,staleDuplicateRejected:true,output:path}));
}catch(error){await writeFile(path.replace(/\.json$/,'')+'-failure.json',JSON.stringify({synthetic:true,liveModel:true,sourceHashes,replies,trace,calls:provider.budget.calls,failure:error instanceof Error?error.message:'failed'},null,2)+'\n',{flag:'wx'});throw error;}finally{host.close();}
