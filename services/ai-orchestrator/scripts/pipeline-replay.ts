import {readFile,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {Host} from './host.js';
const path='../../fixtures/ai/integrated-pipeline.json';
const fixture=JSON.parse(await readFile(path,'utf8'));
const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
const host=new Host();
try{for(const output of fixture.outputs){
 if(!output.session||!output.inventory)throw new Error('rerun_pipeline_to_capture_source_snapshot');
 const state=await host.request({op:'query',session:output.session});
 const recorded=output.adaptiveTrace.at(-1);
 assert.equal(state.receipt.contextDigest,recorded.committed.contextDigest);
 const executed=[];
 for(const challenge of output.stress.challenges){executed.push((await host.request({op:'stress',session:output.session,profileIDs:challenge.profileIDs})).stress);}
 const assessed=await host.request({op:'assess',session:output.session,inventory:output.inventory,stressFindings:executed,rubric});
 assert.equal(assessed.scorecard.overall,output.scorecard.overall);
 output.localReplay={method:'Exact retained source snapshot and committed model commands; offline, no model calls',executed,assessments:assessed.assessments,scorecard:assessed.scorecard,matchedLiveReceipt:true};
 console.log(JSON.stringify({sample:output.sample,matchedLiveReceipt:true,score:assessed.scorecard.overall}));
}
 await writeFile(path,JSON.stringify(fixture,null,2));
}finally{host.close();}
