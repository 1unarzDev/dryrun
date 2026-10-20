import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {Gateway} from '../src/gateway.js';
import {GeminiProvider,type AgentProvider} from '../src/provider.js';
import {minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
import {executeDirectorTool} from './director-tools.js';
const live=process.env.DRYRUN_LIVE_FOOD==='1';
const branches:any[]=[],attempts:any[]=[];
const confirmed=(value:unknown)=>({value,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]});
const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
const provider=live?new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??''):undefined;
const host=new Host();
const schedule=[{kind:'schedule',target:'evt.water-outage.well-pump-failure',minute:0},{kind:'advance',minute:0}];
const commands=[{kind:'advance',minute:1500},{kind:'requestDecision'}];
try {
 for(const foodDays of [1,3]) {
  let state=await host.request({op:'initialize',scenarioID:'water-outage'});
  const records=[{id:'food',physicalID:'synthetic-food-stock',category:'food',quantity:confirmed(foodDays),unit:'day',usableQuantity:confirmed(foodDays),accessible:confirmed(true),subjectIDs:[],evidenceIDs:['reviewed-household-days']},{id:'water',physicalID:'synthetic-water-stock',category:'water',quantity:confirmed(50),unit:'usGallon',usableQuantity:confirmed(50),accessible:confirmed(true),subjectIDs:[],evidenceIDs:['reviewed-container']}];
  state=await host.request({op:'confirmInventory',session:state.session,inventoryItems:records});
  const source=structuredClone(state);
  const originalScore=(await host.request({op:'assess',session:state.session,inventory:state.session.inventory.ledger,rubric})).scorecard;
  const commit=(id:string,actor:string,commands:unknown[])=>host.request({op:'commit',session:state.session,commit:{id,actor,baseRevision:state.receipt.revision,commands}});
  state=await commit('same-outage','director',schedule);
  state=await commit('submitted-conservation','user',[{kind:'useStoredWater',value:'essential'}]);
  state=await commit('observe-food','director',[{kind:'advance',minute:1440}]);
  assert.equal(state.receipt.snapshot.simMinute,1440);assert.equal(state.receipt.snapshot.resources['res.food.days'].amount,foodDays-1);
  const observed=structuredClone(state);
  const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home?.revision??0};
  const context={binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),household:state.householdContext,homeScene:state.homeScene,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending,profiles:state.directorProfiles,lastAction:state.lastAction,recentActions:state.recentActions,learningObjectives:['Inspect the actual recorded household food-days and current unmet requirements. Preview a useful next boundary; respond to depleted versus available food.','Food coverage is a recorded quantity, not proof of calories, storage or dietary suitability. Do not invent replenishment or punish a sound plan with forced new failures.']};
  let calls=0;
  const fixture:AgentProvider={async turn(){if(++calls===1){const call={type:'function_call' as const,id:'preview-food',name:'evaluateCandidateAction',arguments:{commands}};return {steps:[call],calls:[call],text:'',usage:{}};}return {steps:[],calls:[],usage:{},text:JSON.stringify({commands,purpose:foodDays===1?'Review the depleted recorded food supply.':'Acknowledge recorded coverage and review remaining uncertainties.',evidenceIDs:['res.food.days']})};}};
  const replies:any[]=[],trace:any[]=[];
  const gateway=new Gateway({async turn(input){try{const reply=await (provider??fixture).turn(input);replies.push({text:reply.text,calls:reply.calls.map(c=>({id:c.id,name:c.name,arguments:c.arguments})),usage:reply.usage});return reply;}catch(error){replies.push({providerFailure:error instanceof Error&&['provider_rate_limited','provider_timeout_or_cancelled','provider_unavailable','spend_budget'].includes(error.message)?error.message:'provider_failure'});throw new Error('provider_failure');}}});
  const attempt={foodDays,source,observed,context,trace,replies,metrics:gateway.metrics,result:undefined as unknown};attempts.push(attempt);
  let result:any=await gateway.start('synthetic-food',{contractVersion:'dryrun.ai/1',requestID:'food-'+foodDays,synthetic:true,role:'director',context});
  while(result.status==='needs_client_tools') {
   const call=result.calls[0],tool=await executeDirectorTool(host,state,binding,call);
   trace.push({tool:call.name,arguments:call.arguments,result:tool.result});
   assert.equal((await host.request({op:'query',session:state.session})).receipt.contextDigest,binding.contextDigest);
   result=await gateway.resume('synthetic-food',{token:result.token,binding,callID:call.id,result:tool.result});
  }
  const {token,...safeResult}=result;attempt.result=safeResult;
  assert.equal(result.status,'completed');
  state=await host.request({op:'directorCommit',session:state.session,proposal:result.proposal,binding});
  assert.deepEqual(state.session.initial,source.session.initial);assert.deepEqual(state.session.inventory,source.session.inventory);
  const replay=await host.request({op:'query',session:JSON.parse(JSON.stringify(state.session))});assert.deepEqual(replay.receipt,state.receipt);
  for(const item of state.receipt.inventory.items){const initial=records.find(r=>r.id===item.id)!;assert.ok(Math.abs(item.remaining+item.consumed-Number(initial.usableQuantity.value))<1e-8);}
  const scoreAfter=(await host.request({op:'assess',session:state.session,inventory:state.session.inventory.ledger,rubric})).scorecard;assert.deepEqual(scoreAfter,originalScore);
  const stress=await host.request({op:'stress',session:source.session,profileIDs:['evt.water-outage.well-pump-failure']});
  const foodDepletion=stress.stress.baseline.events.find((e:any)=>e.evidence.ruleID==='rule.resource.food/1');assert.equal(foodDepletion.simMinute,foodDays*1440);
  branches.push({confirmedFoodDays:foodDays,source,observed,context,trace,replies,proposal:result.proposal,committed:state,scoreBefore:originalScore,scoreAfter,stress:stress.stress,foodDepletionMinute:foodDepletion.simMinute,replayExact:true,metrics:gateway.metrics});
 }
 assert.ok(branches[1].scoreBefore.preparation>branches[0].scoreBefore.preparation);
 assert.deepEqual(branches[0].stress.schedule,branches[1].stress.schedule);
 const summary={synthetic:true,liveModel:live,...(live?{recordedAt:new Date().toISOString()}:{}),model:provider?.model??'deterministic_protocol_fixture',sdk:'2.30.0',foodPolicy:'dryrun.exercise-food/1',contentVersion:branches[0].source.session.initial.contentVersion,schedule,branches,...(provider?{estimatedUSD:provider.budget.spentUSD,providerCalls:provider.budget.calls}:{providerCalls:0})};
 await writeFile('../../fixtures/ai/food-session'+(live?'-live':'')+'.json',JSON.stringify(summary,null,2)+'\n');
 console.log(JSON.stringify({status:'passed',liveModel:live,providerCalls:provider?.budget.calls??0,foodDepletionMinutes:branches.map(b=>b.foodDepletionMinute),scoreImprovement:branches[1].scoreBefore.preparation-branches[0].scoreBefore.preparation,exerciseDoesNotChangeScore:true,replayExact:true,...(provider?{estimatedUSD:provider.budget.spentUSD}:{})}));
}catch(error){await writeFile('../../fixtures/ai/food-session'+(live?'-live':'')+'-failure.json',JSON.stringify({synthetic:true,liveModel:live,model:provider?.model??'deterministic_protocol_fixture',branches,attempts,reason:error instanceof Error?error.name:'evaluation_failure',providerCalls:provider?.budget.calls??0,estimatedUSD:provider?.budget.spentUSD??0},null,2)+'\n');throw error;}finally{host.close();}
