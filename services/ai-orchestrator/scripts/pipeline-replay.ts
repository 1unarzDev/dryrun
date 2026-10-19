import {readFile,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {Host} from './host.js';
const path=process.env.DRYRUN_PIPELINE_OUTPUT??'../../fixtures/ai/integrated-pipeline.json';
const fixture=JSON.parse(await readFile(path,'utf8'));
const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
const host=new Host();
const replays=[];
try{for(const output of fixture.outputs){
 if(!output.session||!output.inventory)throw new Error('rerun_pipeline_to_capture_source_snapshot');
 const state=await host.request({op:'query',session:output.session});
 const recorded=output.adaptiveTrace.at(-1);
 assert.equal(state.receipt.contextDigest,recorded.committed.contextDigest);
 const executed=[];
 for(const challenge of output.stress.challenges){executed.push((await host.request({op:'stress',session:output.session,profileIDs:challenge.profileIDs})).stress);}
 const recordedScore=await host.request({op:'assess',session:output.session,assessments:output.acceptedAssessments,rubric});
 assert.deepEqual(recordedScore.scorecard,output.scorecard);
 const reassessed=await host.request({op:'assess',session:output.session,inventory:output.inventory,stressFindings:executed,rubric});
 replays.push({sample:output.sample,matchedLiveReceipt:true,matchedFrozenScore:true,recordedAssessmentVersion:output.scorecard.assessmentVersion??'legacy-unversioned',recordedScore:recordedScore.scorecard,reassessment:reassessed,executed});
 console.log(JSON.stringify({sample:output.sample,matchedLiveReceipt:true,matchedFrozenScore:true,oldScore:recordedScore.scorecard.overall,currentScore:reassessed.scorecard.overall,currentCoverage:reassessed.scorecard.evidenceCoverage,assessmentVersion:reassessed.scorecard.assessmentVersion}));
}
 await writeFile(process.env.DRYRUN_REPLAY_OUTPUT??'../../fixtures/ai/pipeline-assessment-replay.json',JSON.stringify({synthetic:true,source:path,modelCalls:0,method:'Replay frozen accepted predicates exactly; separately reassess source with current version. Differences are policy/scope changes, not earned improvements.',replays},null,2)+'\n');
}finally{host.close();}
