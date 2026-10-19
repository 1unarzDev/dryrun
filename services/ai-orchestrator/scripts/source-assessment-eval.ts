import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {Host} from './host.js';
const path='../../fixtures/ai/source-assessment-cases-v1.json';
const lockPath='../../fixtures/ai/source-assessment-lock-v1.json';
const host=new Host();
const confirmed=(value:unknown)=>({value,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]});
const unknown={origin:'userConfirmed',status:'unknown',sourceIDs:[],inputIDs:[]};
try {
 if(process.argv.includes('--generate')){
  const template=(await host.request({op:'initialize',sample:'lake',scenarioID:'tornado'})).session.initial;
  const cases=[];
  for(let assistance=0;assistance<6;assistance++)for(let food=0;food<5;food++)for(let pet=0;pet<2;pet++){
   const n:number=cases.length+1;const id:string=`source-household-${String(n).padStart(2,'0')}`;
   const people=[{id:'adult-a',alias:'Fictional adult A',ageBand:'adult',needs:[],sleepingSpaceID:'sp-living'},{id:'adult-b',alias:'Fictional adult B',ageBand:'adult',needs:[],sleepingSpaceID:'sp-living'}] as any[];
   const support=[null,{ageBand:'infant',needs:[]},{ageBand:'child',needs:[],helperPersonID:'adult-a'},{ageBand:'adult',needs:['usesWheelchair'],helperPersonID:'dependent'},{ageBand:'adult',needs:['deafOrHardOfHearing']},{ageBand:'adult',needs:['needsHelperToEvacuate'],helperPersonID:'missing-person'}][assistance];
   if(support)people.push({id:'dependent',alias:'Fictional dependent',sleepingSpaceID:'sp-living',...support});
   if(food===4)people[0].sleepingSpaceID=null;
   const amount=[1,3,6,3,null][food],unit=food===2?'count':'day';
   const item={id:'food',physicalID:'one-physical-food-batch',category:'food',quantity:amount===null?unknown:confirmed(amount),unit,usableQuantity:amount===null?unknown:confirmed(amount),accessible:confirmed(true),subjectIDs:[],evidenceIDs:[id+'-confirmed-food'],...(food===3?{expiresAt:'2026-10-18T00:00:00Z'}:{})};
   // Expectations are explicit product-policy assertions, never copied from host output.
   cases.push({id,split:n%3===0?'holdout':'development',household:{id,displayName:id,people,pets:[{id:'pet',kind:'cat',count:1,carrierAvailable:pet===0?unknown:confirmed(true)}],limitedBudget:n%2===0},items:[item],expected:{food:{quantity:[false,true,null,false,null][food],accessible:food!==3},assistance:{notApplicableRule:assistance===0?'no-assistance-needs':null,assigned:[null,null,true,false,null,false][assistance]},care:{notApplicableRule:assistance===0?'no-care-needs':null},pets:{transport:pet===0?null:true},shelter:{suitable:true,reachable:assistance===3||food===4?null:true}}});
  }
  await writeFile(path,JSON.stringify({version:'dryrun.source-assessment-cases/1',assessmentVersion:'dryrun.household-assessment/3',referenceStatus:'Policy-authored synthetic source-to-predicate expectations, not human-adjudicated. These combinations are not independent sampled families. Same sample ranch geometry; varied-home evidence remains in Core spatial tests.',splitPolicy:'40 development / 20 holdout selected before first execution; no live prompt tuning uses these cases. Do not regenerate or tune on holdout failures without retiring that holdout claim.',template,cases},null,2)+'\n',{flag:'wx'});
  await writeFile(lockPath,JSON.stringify({version:'dryrun.source-assessment-lock/1',sha256:createHash('sha256').update(await readFile(path)).digest('hex')},null,2)+'\n',{flag:'wx'});
 }
 const bytes=await readFile(path);
 const lock=JSON.parse(await readFile(lockPath,'utf8'));
 assert.equal(createHash('sha256').update(bytes).digest('hex'),lock.sha256,'source_fixture_lock_changed');
 const fixture=JSON.parse(bytes.toString('utf8'));
 assert.equal(fixture.cases.length,60);
 const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
 const results=[];
 for(const c of fixture.cases){
  const input=structuredClone(fixture.template);
  Object.assign(input.household,{id:c.household.id,displayName:c.household.displayName,people:c.household.people,pets:c.household.pets,preparedness:{items:{food:{available:confirmed(true),location:'Fictional pantry',notes:''}}}});
  input.household.supplies.limitedBudget=c.household.limitedBudget;
  const initialized=await host.request({op:'initialize',input});
  const confirmedState=await host.request({op:'confirmInventory',session:initialized.session,inventoryItems:c.items,rubric});
  const assessed=await host.request({op:'assess',session:confirmedState.session,inventory:confirmedState.inventory,rubric});
  assert.equal(assessed.scorecard.assessmentVersion,'dryrun.household-assessment/4',c.id);
  for(const [criterion,expected] of Object.entries(c.expected) as [string,Record<string,unknown>][]){
   const actual=assessed.assessments.find((a:any)=>a.criterionID===criterion);assert.ok(actual,c.id+':'+criterion);
   for(const [key,value] of Object.entries(expected)){
    const observed=key==='notApplicableRule'?actual.notApplicableRule:actual.predicates[key];
    assert.equal(observed??null,value,c.id+':'+criterion+'.'+key);
   }
  }
  const foodTask=confirmedState.taskCatalog.some((t:any)=>t.actionID==='prep.food');
  assert.equal(foodTask,c.expected.food.quantity!==true,c.id+':food-task');
  results.push({id:c.id,split:c.split,matchedSourcePredicates:true,foodTask,assessments:assessed.assessments,scorecard:assessed.scorecard});
 }
 await writeFile('../../fixtures/ai/source-assessment-evaluation-v4.json',JSON.stringify({synthetic:true,modelCalls:0,referenceStatus:fixture.referenceStatus,assessmentVersion:'dryrun.household-assessment/4',referenceAssessmentVersion:fixture.assessmentVersion,evaluationUse:'Regression against previously exercised frozen references; not a fresh held-out generalization claim.',development:results.filter(r=>r.split==='development').length,holdout:results.filter(r=>r.split==='holdout').length,passed:results.length,results},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',actualSourceCases:results.length,development:40,holdout:20,modelCalls:0}));
} finally {host.close();}
