import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Host} from './host.js';
import {executeDirectorTool} from './director-tools.js';
const host=new Host();
try {
 const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
 for(const suffix of ['','-live']) {
  const fixture=JSON.parse(await readFile('../../fixtures/ai/food-session'+suffix+'.json','utf8'));
  assert.equal(fixture.foodPolicy,'dryrun.exercise-food/1');
  for(const branch of fixture.branches) {
   assert.equal(branch.source.session.inventory.foodPolicy,'dryrun.exercise-food/1');
   for(const tool of branch.trace) {
    const result=await executeDirectorTool(host,branch.observed,branch.context.binding,{name:tool.tool,arguments:tool.arguments});
    // Compare the JSON wire representation: optional undefined fields are omitted on transport.
    assert.deepEqual(JSON.parse(JSON.stringify(result.result)),tool.result);
   }
   const committed=await host.request({op:'directorCommit',session:branch.observed.session,proposal:branch.proposal,binding:branch.context.binding});
   assert.deepEqual(committed.receipt,branch.committed.receipt);
   const replay=await host.request({op:'query',session:JSON.parse(JSON.stringify(branch.committed.session))});assert.deepEqual(replay.receipt,branch.committed.receipt);
   assert.deepEqual(replay.session.inventory,branch.source.session.inventory);assert.deepEqual(replay.session.initial,branch.source.session.initial);
   const stress=await host.request({op:'stress',session:branch.source.session,profileIDs:['evt.water-outage.well-pump-failure']});assert.deepEqual(stress.stress,branch.stress);
   const score=await host.request({op:'assess',session:replay.session,inventory:replay.session.inventory.ledger,rubric});assert.deepEqual(score.scorecard,branch.scoreBefore);
  }
  console.log(JSON.stringify({status:'passed',retainedLiveModel:fixture.liveModel,branches:fixture.branches.length,receiptReplay:true,toolReplay:true,stressReplay:true,sourceAndScoreUnchanged:true,modelCalls:0}));
 }
}finally{host.close();}
