// Exercise both published reverse-order plans through the actual portable host, then replay.
// Matching mechanical outcomes do not establish human difficulty/equivalence.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const run=promisify(execFile);
for(const nonDevice of [false,true]){
 for(const script of ['practice-phases-eval.ts','practice-phases-replay.ts']){
  const result=await run(process.execPath,['--import','tsx','scripts/'+script],{
   env:{...process.env,DRYRUN_PRACTICE_NONDEVICE:nonDevice?'1':'0',DRYRUN_PRACTICE_REVERSE:'1'},
   maxBuffer:1024*1024,
  });
  process.stdout.write(result.stdout);
 }
 const stem=nonDevice?'nondevice':'phases';
 const forward=JSON.parse(await readFile('../../fixtures/ai/practice-'+stem+'.json','utf8'));
 const reverse=JSON.parse(await readFile('../../fixtures/ai/practice-'+stem+'-reverse.json','utf8'));
 for(const source of forward.plan.phaseSources){
  assert.deepEqual(reverse.plan.phaseSources.find((s:any)=>s.sessionID===source.sessionID),source);
 }
 const correct=(f:any)=>f.branches.find((b:any)=>!b.wrongFirst);
 const credits=(f:any)=>Object.fromEntries(correct(f).checkpoints.map((c:any)=>[c.competencyID,c.observation.credit]));
 assert.deepEqual(credits(forward),credits(reverse));
 assert.equal(correct(forward).practice,correct(reverse).practice);
 assert.equal(correct(forward).practiceAssessed,correct(reverse).practiceAssessed);
}
console.log(JSON.stringify({passed:true,modelCalls:0,reverseVariants:2,gradedBranches:4,exactReplay:true,sameFrozenSources:true,correctCompetencyCreditParity:true,humanComparability:'pending'}));
