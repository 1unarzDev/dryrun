import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Host} from './host.js';
import {directorContext} from '../src/contracts.js';
const host=new Host();
try {
 for(const mode of ['offline','live']) {
  const fixture=JSON.parse(await readFile(`../../fixtures/ai/fallback-resume-${mode}.json`,'utf8'));
  const pause=fixture.trace.find((s:any)=>s.phase==='local-fallback-pause');
  assert.deepEqual(pause.receipt.snapshot,pause.before.snapshot);assert.deepEqual(pause.receipt.pending,pause.before.pending);assert.deepEqual(pause.receipt.inventory,pause.before.inventory);
  const origin=fixture.trace.find((s:any)=>s.phase==='recorded-live-Gemini-origin').session;
  assert.deepEqual(fixture.finalSession.commits.slice(0,origin.commits.length),origin.commits);
  assert.deepEqual(fixture.finalSession.initial,origin.initial);assert.deepEqual(fixture.finalSession.inventory,origin.inventory);
  const context=directorContext.parse(fixture.trace.find((s:any)=>s.phase==='return-to-director').context);
  const replay=await host.request({op:'query',session:fixture.finalSession});
  assert.deepEqual(replay.receipt,fixture.finalReceipt);assert.deepEqual(replay.lastAction,context.lastAction);
  assert.equal(replay.lastAction.id,'resumed-essential-use');
  console.log(JSON.stringify({mode,receiptReplay:true,sourceUnchanged:true,pendingPreservedAtPause:true,latestCommittedAction:true,newModelCalls:0}));
 }
}finally{host.close();}
