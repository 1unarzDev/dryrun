import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {executeDirectorTool} from './director-tools.js';
import {Gateway} from '../src/gateway.js';
import {toolResult,minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
import type {AgentProvider} from '../src/provider.js';
const host=new Host();
try {
 const fixture=JSON.parse(await readFile('../../fixtures/ai/stress-retest.json','utf8'));
 const state=await host.request({op:'query',session:fixture.source});
 const binding=fixture.trace[0].result.binding;
 const badPlan=structuredClone(fixture.retestPlan);badPlan.commands[0].value='sp-kitchen'; // valid shape and stock ID, invalid person
 const commands=[{kind:'advance',minute:1},{kind:'requestDecision'}],trace:any[]=[];let turns=0;
 const provider:AgentProvider={async turn(input){turns++;
  if(turns===2)assert.ok(JSON.stringify(input.history).includes('host_rejected_counterfactual'));
  if(turns<4){const call={type:'function_call' as const,id:'repair-'+turns,name:turns<3?'runCounterfactual':'evaluateCandidateAction',arguments:turns<3?{profileIDs:fixture.profileIDs,retestPlan:turns===1?badPlan:fixture.retestPlan}:{commands}};return {steps:[call],calls:[call],text:'',usage:{}};}
  return {steps:[],calls:[],usage:{},text:JSON.stringify({commands,purpose:'The corrected hypothetical transfer preserves recorded water; other gaps and unknowns remain.',evidenceIDs:['res.water.stored']})};
 }};
 const gateway=new Gateway(provider);
 let result:any=await gateway.start('synthetic-repair',{contractVersion:'dryrun.ai/1',requestID:'retest-host-repair',role:'director',synthetic:true,context:{binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),initialInventoryItemIDs:state.session.inventory.ledger.items.map((i:any)=>i.id),profiles:state.directorProfiles,homeScene:state.homeScene,household:state.householdContext,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,learningObjectives:['Review the controlled storage improvement.']}});
 while(result.status==='needs_client_tools'){
  const call=result.calls[0],response=await executeDirectorTool(host,state,binding,call);trace.push({call,result:response.result});
  assert.deepEqual((await host.request({op:'query',session:state.session})).receipt,state.receipt);
  result=await gateway.resume('synthetic-repair',{token:result.token,binding,callID:call.id,result:response.result});
 }
 assert.equal(result.status,'completed');assert.equal(turns,4);
 assert.deepEqual(trace[0].result.observation,{kind:'runCounterfactual',status:'unavailable',reason:'host_rejected_counterfactual'});
 assert.equal(trace[1].result.observation.controlledRetest.resources['res.water.stored'].amount,5);
 assert.ok(trace[1].result.observation.comparison.remainingRequirementIDs.length>0);
 assert.equal(toolResult.safeParse({...trace[0].result,observation:{...trace[0].result.observation,failed:false,baseline:minimizedSnapshot(state.receipt)}}).success,false);
 await assert.rejects(executeDirectorTool(host,state,{...binding,revision:binding.revision+1},trace[0].call),/stale/);
 const committed=await host.request({op:'directorCommit',session:state.session,binding,proposal:result.proposal});
 assert.deepEqual(committed.session.inventory,state.session.inventory);assert.equal(committed.receipt.inventory.items[0].locationID,'sp-kitchen');
 await writeFile('../../fixtures/ai/stress-retest-repair.json',JSON.stringify({synthetic:true,liveModel:false,sourceFixture:'stress-retest.json',sourceContextDigest:binding.contextDigest,trace,proposal:result.proposal,committedReceipt:committed.receipt,protocolTurns:turns,providerCalls:0},null,2)+'\n');
 console.log(JSON.stringify({passed:true,protocolTurns:turns,providerCalls:0,hostRejectedBeforeRepair:true,correctedRetestGallons:5,staleRemainsFatal:true,sourceUnchanged:true}));
}finally{host.close();}
