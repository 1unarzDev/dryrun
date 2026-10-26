import {readFile,writeFile} from 'node:fs/promises';
const annotations=JSON.parse(await readFile('../../fixtures/ai/images/annotations.json','utf8'));
function iou(a:number[],b:number[]){const area=(x:number[])=>Math.max(0,x[2]!-x[0]!)*Math.max(0,x[3]!-x[1]!);const intersect=area([Math.max(a[0]!,b[0]!),Math.max(a[1]!,b[1]!),Math.min(a[2]!,b[2]!),Math.min(a[3]!,b[3]!)]);return intersect/(area(a)+area(b)-intersect);}
const models=[];
for(const file of ['vision-evaluation.json','vision-evaluation-gemini-3.8-flash.json']){
 const evaluation=JSON.parse(await readFile('../../fixtures/ai/'+file,'utf8'));
 const results=evaluation.results.map((r:any)=>{
  const truth=annotations.cases.find((c:any)=>c.name===r.fixture);if(!truth)throw new Error('unknown_annotation');
  const relevant=r.output.concerns.filter((c:any)=>truth.expected.includes(c.category));
  const bestIoU=truth.expectedBox&&relevant.length?Math.max(...relevant.map((c:any)=>iou(c.box,truth.expectedBox))):null;
  return {fixture:r.fixture,positive:!!truth.expected.length,concerns:r.output.concerns.length,categoryDetected:!!relevant.length,bestIoU,localizedAtIoU50:bestIoU!==null&&bestIoU>=0.5,falsePositive:!truth.expected.length&&r.output.concerns.length>0};
 });
 const positives=results.filter((r:any)=>r.positive),negatives=results.filter((r:any)=>!r.positive);
 models.push({model:evaluation.model,fixtures:results.length,positiveFixtures:positives.length,negativeFixtures:negatives.length,categoryRecall:positives.filter((r:any)=>r.categoryDetected).length/positives.length,localizationRecallAtIoU50:positives.filter((r:any)=>r.localizedAtIoU50).length/positives.length,negativeFalsePositiveCount:negatives.filter((r:any)=>r.falsePositive).length,results});
}
const output={synthetic:true,newModelCalls:0,annotationStatus:'Policy-authored boxes on six synthetic top-down diagrams, not qualified human labels or real scans',independentRooms:1,limitations:['Four positive images vary one diagram; not independent households.','A diagram box is image-level only; no world-space projection or safe-route proof.','This reanalysis does not test actual photo capture, localization robustness or calibration.','Poor overlap and false positives remain reviewable concerns, never household facts.'],models};
await writeFile('../../fixtures/ai/vision-localization.json',JSON.stringify(output,null,2)+'\n');
for(const model of models)console.log(JSON.stringify({model:model.model,categoryRecall:model.categoryRecall,localizationRecallAtIoU50:model.localizationRecallAtIoU50,negativeFalsePositiveCount:model.negativeFalsePositiveCount}));
