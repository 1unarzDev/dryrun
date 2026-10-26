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
   const score=await host.request({op:'assess',session:replay.session,inventory:replay.session.inventory.ledger,rubric});
   if(score.scorecard.assessmentVersion===branch.scoreBefore.assessmentVersion)assert.deepEqual(score.scorecard,branch.scoreBefore);
   else {
    // This legacy live artifact retained a card but not its accepted predicates. Do not relabel it:
    // /6 changed manufactured-home shelter treatment; /7 removes obsolete reconnection credit.
    // These frozen branches are single-family and record no legacy reconnection fact.
    assert.equal(branch.source.session.initial.household.housing.homeType,'singleFamily');
    assert.notEqual(branch.source.session.initial.home.dwellingType,'manufacturedHome');
    assert.equal(branch.source.session.initial.household.preparedness?.items?.reconnect,undefined);
    assert.equal(branch.scoreBefore.assessmentVersion,'dryrun.household-assessment/5');
    assert.equal(score.scorecard.assessmentVersion,'dryrun.household-assessment/7');
    const {assessmentVersion:currentVersion,...currentCard}=score.scorecard;
    const {assessmentVersion:recordedVersion,...recordedCard}=branch.scoreBefore;
    assert.deepEqual(currentCard,recordedCard);
   }
  }
  console.log(JSON.stringify({status:'passed',retainedLiveModel:fixture.liveModel,branches:fixture.branches.length,receiptReplay:true,toolReplay:true,stressReplay:true,sourceAndScoreUnchanged:true,historicalCardVersionPreserved:true,comparison:"Exact card when versions match; explicit /5-to-/7 non-manufactured numeric/status comparison otherwise (legacy accepted predicates absent).",modelCalls:0}));
 }
}finally{host.close();}
