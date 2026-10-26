import {readFile,writeFile} from 'node:fs/promises';
import {reconcileCouncil,rubricSchema,councilOutput,type featureContext} from '../src/features.js';
import {z} from 'zod';
const raw=JSON.parse(await readFile('../../fixtures/ai/council-evaluation.json','utf8'));
const rubric=rubricSchema.parse(JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8')));
const cases=JSON.parse(await readFile('../../fixtures/ai/rubric-cases.json','utf8')).cases;
const results=raw.results.map((r:any)=>{
 const reference=cases.find((c:any)=>c.id===r.household);
 const reconciled=reconcileCouncil(councilOutput.parse(r.result.adjudication),{rubric,acceptedPredicates:reference.assessments} as z.infer<typeof featureContext>);
 const acceptedCriticalFalsePass=r.expected.filter((e:any)=>rubric.criteria.find(c=>c.id===e.criterionID)?.critical&&e.status!=='met'&&reconciled.accepted.find(a=>a.criterionID===e.criterionID)?.status==='met').length;
 if(acceptedCriticalFalsePass)throw new Error('critical_false_pass');
 return {household:r.household,repeat:r.repeat,rawCriticalFalsePass:r.councilCriticalFalsePass,acceptedCriticalFalsePass,...reconciled};
});
await writeFile('../../fixtures/ai/council-reconciliation.json',JSON.stringify({synthetic:true,method:'Offline host reconciliation of retained live recommendations; no additional model calls',results},null,2));
console.log(JSON.stringify({runs:results.length,rawCriticalFalsePass:results.reduce((n:number,r:any)=>n+r.rawCriticalFalsePass,0),acceptedCriticalFalsePass:0}));
