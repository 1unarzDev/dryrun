import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
const cases=JSON.parse(await readFile('../../fixtures/ai/rubric-cases.json','utf8'));
const host=new Host();let passed=0;const results=[];
try{for(const c of cases.cases){const state=await host.request({op:'initialize',sample:c.sample});const result=await host.request({op:'assess',session:state.session,rubric,assessments:c.assessments,attempts:c.attempts});const card=result.scorecard;
 if(Math.abs((card.overall??-1)-(c.expected.overall??-1))>1e-8||card.cap!==c.expected.cap||Math.abs(card.evidenceCoverage-c.expected.coverage)>1e-8)throw new Error('rubric_case_failed:'+c.id);
 passed++;results.push({id:c.id,split:c.split,card});}
 await writeFile('../../fixtures/ai/deterministic-evaluation.json',JSON.stringify({synthetic:true,referenceStatus:cases.referenceStatus,passed,households:cases.cases.length,results},null,2));console.log(JSON.stringify({passed,development:cases.cases.filter((c:any)=>c.split==='development').length,holdout:cases.cases.filter((c:any)=>c.split==='holdout').length}));}finally{host.close();}
