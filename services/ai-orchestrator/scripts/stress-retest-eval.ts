import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {executeDirectorTool} from './director-tools.js';
import {Gateway} from '../src/gateway.js';
import {directorToolSchemas,minimizedSnapshot,stressRetestPlan} from '../src/contracts.js';
import type {AgentProvider} from '../src/provider.js';
const host=new Host();
try {
 // The recorded source is synthetic; create a fresh versioned host session rather than upgrading its policy on resume.
 const recorded=JSON.parse(await readFile('../../fixtures/ai/inventory-session-trace.json','utf8'));
 let state=await host.request({op:'initialize',input:recorded.original.session.initial});
 state=await host.request({op:'confirmInventory',session:state.session,inventoryItems:recorded.original.session.inventory.ledger.items});
 const source=structuredClone(state.session),person=source.initial.household.people[0].id;
 const retestPlan=stressRetestPlan.parse({version:'dryrun.stress-retest/1',commands:[{kind:'takeSupply',target:'water',value:person},{kind:'moveTo',target:person,value:'sp-living'},{kind:'transferSupply',target:'water',value:'sp-living'}]});
 const profileIDs=['evt.home-fire.alarm','evt.home-fire.fire-origin'];
 const request={op:'stress',session:source,profileIDs,retestPlan};
 const finding=(await host.request(request)).stress;
 assert.equal(finding.baseline.inventory.items[0].accessible,false);
 assert.equal(finding.controlledRetest.inventory.items[0].accessible,true);
 assert.equal(finding.controlledRetest.inventory.items[0].remaining,5);
 assert.equal(finding.comparison.commonHorizonReached,true);
 assert.deepEqual(finding.comparison.remainingRequirementIDs,finding.controlledRetest.snapshot.unmetRequirements.toSorted());
 assert.deepEqual((await host.request({...request,retestPlan:finding.retestPlan})).stress,finding);
 const binding={sessionID:source.id,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:source.initial.household.revision,homeRevision:source.initial.home?.revision??0};
 const commands=[{kind:'advance',minute:1},{kind:'requestDecision'}];
 let turns=0;const trace:any[]=[];
 const fixture:AgentProvider={async turn(){turns++;if(turns<3){const call={type:'function_call' as const,id:'tool-'+turns,name:turns===1?'runCounterfactual':'evaluateCandidateAction',arguments:turns===1?{profileIDs,retestPlan}:{commands}};return {steps:[call],calls:[call],text:'',usage:{}};}return {steps:[],calls:[],text:JSON.stringify({commands,purpose:'Review the hypothetical storage comparison and ask before making real changes.',evidenceIDs:[]}),usage:{}};}};
 const gateway=new Gateway(fixture);
 let result:any=await gateway.start('synthetic-retest',{contractVersion:'dryrun.ai/1',requestID:'controlled-storage-retest',role:'director',synthetic:true,context:{initialInventoryItemIDs:source.inventory.ledger.items.map((item:any)=>item.id),binding,snapshot:minimizedSnapshot(state.receipt),profiles:state.directorProfiles,homeScene:state.homeScene,household:state.householdContext,directorPolicy:source.directorPolicy,directorState:state.receipt.directorState,learningObjectives:['Investigate recorded storage access using a controlled hypothetical retest.']}});
 while(result.status==='needs_client_tools'){
  const call=result.calls[0],response=await executeDirectorTool(host,state,binding,call);
  trace.push({call,result:response.result});
  if(call.name==='runCounterfactual')assert.deepEqual(response.receipt,state.receipt);
  assert.deepEqual((await host.request({op:'query',session:state.session})).receipt,state.receipt);
  result=await gateway.resume('synthetic-retest',{token:result.token,binding,callID:call.id,result:response.result});
 }
 assert.equal(result.status,'completed');assert.equal(turns,3);
 assert.ok(trace[0].result.observation.comparison);
 assert.ok(trace[0].result.observation.controlledRetest);
 const committed=await host.request({op:'directorCommit',session:source,binding,proposal:result.proposal});
 assert.deepEqual(committed.session.inventory,source.inventory);
 assert.deepEqual(committed.session.initial,source.initial);
 assert.equal(committed.receipt.inventory.items[0].locationID,'sp-kitchen');
 assert.deepEqual((await host.request({op:'query',session:committed.session})).receipt,committed.receipt);
 assert.equal(stressRetestPlan.safeParse({...retestPlan,commands:[{kind:'advance',minute:5}]}).success,false);
 assert.equal(directorToolSchemas.runCounterfactual.safeParse({profileIDs,retestPlan:{...retestPlan,version:'invented'}}).success,false);
 await assert.rejects(host.request({...request,retestPlan:{...retestPlan,commands:[{kind:'advance',minute:5}]}}));
 await writeFile('../../fixtures/ai/stress-retest.json',JSON.stringify({synthetic:true,liveModel:false,providerCalls:0,fixtureProtocolTurns:turns,source,profileIDs,retestPlan,finding,trace,proposal:result.proposal,committed},null,2)+'\n');
 console.log(JSON.stringify({passed:true,liveModel:false,providerCalls:0,fixtureProtocolTurns:turns,baselineAccessible:false,retestAccessible:true,conservedGallons:5,readOnly:true,exactReplay:true}));
}finally{host.close();}
