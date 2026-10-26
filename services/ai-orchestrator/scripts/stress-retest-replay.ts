import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Host} from './host.js';
import {executeDirectorTool} from './director-tools.js';
const host=new Host();
try {
 const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
 for(const suffix of ['','-live']){
  const fixture=JSON.parse(await readFile('../../fixtures/ai/stress-retest'+suffix+'.json','utf8'));
  const source=fixture.source.session??fixture.source;
  const state=await host.request({op:'query',session:source});
  const binding=fixture.context?.binding??fixture.trace[0].result.binding;
  for(const step of fixture.trace){
   const response=await executeDirectorTool(host,state,binding,step.call);
   assert.deepEqual(JSON.parse(JSON.stringify(response.result)),step.result);
   assert.deepEqual((await host.request({op:'query',session:source})).receipt,state.receipt);
  }
  if(fixture.finding){
   const stress=await host.request({op:'stress',session:source,profileIDs:fixture.profileIDs,retestPlan:fixture.retestPlan});
   assert.deepEqual(stress.stress,fixture.finding);
  }
  const proposal=fixture.result?.proposal??fixture.proposal;
  const committed=await host.request({op:'directorCommit',session:source,binding,proposal});
  assert.deepEqual(committed.receipt,fixture.committed.receipt);
  assert.deepEqual(committed.session.initial,source.initial);assert.deepEqual(committed.session.inventory,source.inventory);
  assert.equal(committed.receipt.inventory.items[0].locationID,'sp-kitchen');
  const score=(session:any)=>host.request({op:'assess',session,inventory:source.inventory.ledger,rubric});
  assert.deepEqual((await score(source)).scorecard,(await score(committed.session)).scorecard);
  console.log(JSON.stringify({passed:true,retainedLiveModel:fixture.liveModel,toolReplay:true,proposalReplay:true,realSourceAndScoreUnchanged:true,newModelCalls:0}));
 }
}finally{host.close();}
