import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {Host} from './host.js';
const host=new Host();
try{for(const action of ['all','essential']){
 const fixture=JSON.parse(await readFile(`../../fixtures/ai/adaptive-trace-${action}.json`,'utf8'));
 const committed=fixture.trace.filter((t:any)=>t.committed).at(-1).committed;
 const replay=await host.request({op:'query',session:committed.session});
 assert.equal(replay.receipt.contextDigest,committed.receipt.contextDigest);
 assert.deepEqual(replay.receipt.snapshot,committed.receipt.snapshot);
 console.log(JSON.stringify({action,replayed:true,revision:replay.receipt.revision}));
}}finally{host.close();}
