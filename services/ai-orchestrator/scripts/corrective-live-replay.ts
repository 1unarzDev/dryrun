import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Host} from './host.js';
const evidenceFiles=['corrective-live-v1.json','corrective-live-traces.json','corrective-live-v2.json','corrective-live-v3.json','corrective-live-v4.json','corrective-live-v5.json','corrective-live-v6.json','corrective-live-v7-groq.json','corrective-live-v8-groq.json','corrective-live-v9.json','corrective-live-v10.json'];
const host=new Host();
try{
 for(const file of evidenceFiles){
 const evidence=JSON.parse(await readFile('../../fixtures/ai/'+file,'utf8'));
 assert.equal(evidence.synthetic,true);assert.equal(evidence.scenarios.length,6);
 for(const row of evidence.scenarios){
  const replay=await host.request({op:'query',session:row.finalSession});
  assert.equal(replay.receipt.contextDigest,row.expectedDigest);
  assert.deepEqual(replay.receipt.experience,row.experience);
  console.log(JSON.stringify({runID:evidence.runID,hazard:row.hazard,replay:'exact',liveStatus:row.liveStatus}));
 }
 console.log(JSON.stringify({file,modelCalls:0,replayed:6,originalLivePassed:evidence.livePassed,note:'Replay validates committed state only; failed live rows remain failed'}));
 }
}finally{host.close();}
