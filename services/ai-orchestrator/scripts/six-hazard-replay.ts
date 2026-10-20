import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Host} from './host.js';
const fixture=JSON.parse(await readFile('../../fixtures/ai/six-hazard-mechanics.json','utf8'));
assert.equal(fixture.version,'dryrun.six-hazard-replay/1');assert.equal(fixture.synthetic,true);
const host=new Host(),hazards=new Set<string>();
try{
 for(const branch of fixture.branches){
  const session={...branch.session,initial:{...branch.session.initial,household:fixture.household,home:fixture.home}};
  const result=await host.request({op:'query',session});
  assert.equal(result.receipt.contextDigest,branch.expected.contextDigest,branch.hazard+': '+branch.decision);
  assert.deepEqual(result.receipt.experience,branch.expected.experience);
  assert.deepEqual(result.receipt.snapshot,branch.expected.snapshot);
  assert.equal(result.session.initial.scenarioID,branch.hazard);hazards.add(branch.hazard);
 }
 assert.equal(hazards.size,6);assert.equal(fixture.branches.length,24);
 console.log(JSON.stringify({passed:true,synthetic:true,hazards:hazards.size,branches:fixture.branches.length,replay:'exact',modelCalls:0,native:'pending'}));
}finally{host.close();}
