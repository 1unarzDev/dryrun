import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {Host} from './host.js';
const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
const cases=JSON.parse(await readFile('../../fixtures/ai/rubric-cases.json','utf8'));
let expected:unknown[]|undefined;const hashes:string[]=[];
for(let process=0;process<3;process++){
 const host=new Host();const cards=[];
 try{
  const versionedRubric=structuredClone(rubric);
  if(process===2){versionedRubric.criteria.reverse();versionedRubric.domainWeights=Object.fromEntries(Object.entries(versionedRubric.domainWeights).reverse());}
  const state=await host.request({op:'initialize'});
  for(const c of cases.cases){const result=await host.request({op:'assess',session:state.session,rubric:versionedRubric,assessments:c.assessments,attempts:c.attempts});cards.push(result.scorecard);}
 }finally{host.close();}
 if(expected)assert.deepEqual(cards,expected);else expected=cards;
 hashes.push(createHash('sha256').update(JSON.stringify(cards)).digest('hex'));
}
const result={synthetic:true,passed:true,cases:cases.cases.length,independentHostProcesses:3,permutedRubric:true,exactNumberEquality:true,hashes};
await writeFile('../../fixtures/ai/score-stability.json',JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
