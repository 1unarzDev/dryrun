import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Host} from './host.js';
const host=new Host();
try{
 for(const suffix of ['','-live']){
  const fixture=JSON.parse(await readFile('../../fixtures/ai/spatial-policy'+suffix+'.json','utf8'));
  const source=await host.request({op:'query',session:fixture.source.session});
  assert.equal(source.receipt.contextDigest,fixture.context.binding.contextDigest);
  const replay=await host.request({op:'query',session:fixture.committed.session});
  assert.deepEqual(replay.receipt,fixture.committed.receipt);
  assert.deepEqual(replay.session.initial,fixture.source.session.initial);
  assert.deepEqual(replay.session.directorPolicy,fixture.source.session.directorPolicy);
  console.log(JSON.stringify({fixture:'spatial-policy'+suffix,replay:true,origin:replay.receipt.snapshot.spatialState.originSpaceID,awaitingUserAction:replay.receipt.directorState.awaitingUserAction,finished:replay.receipt.finished}));
 }
}finally{host.close();}
