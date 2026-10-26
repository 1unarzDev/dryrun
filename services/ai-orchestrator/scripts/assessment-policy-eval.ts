import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
const host=new Host();
const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
const confirmed=(value:unknown)=>({value,status:'confirmed',origin:'userConfirmed',sourceIDs:[],inputIDs:[]});
try {
 const source=await host.request({op:'initialize',sample:'lake',scenarioID:'tornado'});
 const input=structuredClone(source.session.initial);
 // Explicit synthetic source snapshots; native must use its HomeConfirmation/save-before-publish path.
 input.household.people.forEach((p:any)=>{p.sleepingSpaceID='sp-living';p.needs=[];});
 input.household.preparedness??={items:{}};input.household.preparedness.items.food={available:confirmed(true),location:'Synthetic pantry',notes:''};
 const shelter=input.home.annotations.find((a:any)=>a.kind==='tornadoShelterCandidate');
 const room=input.home.spaces.find((r:any)=>r.id===shelter.spaceID);
 room.interiorNoWindowsConfirmed={origin:'userConfirmed',status:'unknown',sourceIDs:[],inputIDs:[]};
 const before=await host.request({op:'initialize',input});
 const assess=(state:any,inventory?:unknown)=>host.request({op:'assess',session:state.session,inventory,rubric});
 const prior=await assess(before);
 assert.deepEqual(prior.assessments.find((a:any)=>a.criterionID==='shelter').predicates,{});
 const changed=structuredClone(input);changed.home.revision++;
 changed.home.spaces.find((r:any)=>r.id===room.id).interiorNoWindowsConfirmed=confirmed(true);
 const after=await host.request({op:'initialize',input:changed});
 const reviewed=await assess(after);
 assert.deepEqual(reviewed.assessments.find((a:any)=>a.criterionID==='shelter').predicates,{suitable:true,reachable:true});
 assert.ok(reviewed.scorecard.preparation>prior.scorecard.preparation);
 // Actual local inventory confirmation, not an observation or simulation action, supplies access evidence.
 const item={id:'food',physicalID:'food-box',category:'food',quantity:confirmed(3),unit:'day',usableQuantity:confirmed(3),accessible:confirmed(false),subjectIDs:[],evidenceIDs:['synthetic-manual-review']};
 const unavailable=await host.request({op:'confirmInventory',session:after.session,inventoryItems:[item]});
 const inaccessible=await assess(unavailable,unavailable.inventory);
 const updated=await host.request({op:'confirmInventory',session:unavailable.session,inventory:unavailable.inventory,inventoryItems:[{...item,accessible:confirmed(true)}]});
 const accessible=await assess(updated,updated.inventory);
 assert.equal(inaccessible.assessments.find((a:any)=>a.criterionID==='food').predicates.accessible,false);
 assert.equal(accessible.assessments.find((a:any)=>a.criterionID==='food').predicates.accessible,true);
 assert.ok(accessible.scorecard.preparation>inaccessible.scorecard.preparation);
 const oneDay=await host.request({op:'confirmInventory',session:updated.session,inventory:updated.inventory,inventoryItems:[{...item,quantity:confirmed(1),usableQuantity:confirmed(1),accessible:confirmed(true)}],rubric});
 const twoDays=await host.request({op:'confirmInventory',session:oneDay.session,inventory:oneDay.inventory,inventoryItems:[{...item,quantity:confirmed(2),usableQuantity:confirmed(2),accessible:confirmed(true)}],rubric});
 const foodTask=oneDay.taskCatalog.find((t:any)=>t.actionID==='prep.food');assert.ok(foodTask);
 const oneKey=await host.request({op:'resourceKey',session:oneDay.session,resourceTasks:[foodTask]});
 const twoKey=await host.request({op:'resourceKey',session:twoDays.session,resourceTasks:[foodTask]});
 assert.notEqual(oneKey.resourceStrategyKey.normalizedInputDigest,twoKey.resourceStrategyKey.normalizedInputDigest);
 assert.equal(oneDay.gaps.find((g:any)=>g.category==='food').deficit,2);
 assert.equal(twoDays.gaps.find((g:any)=>g.category==='food').deficit,1);
 assert.equal(twoDays.session.initial.household.supplies.shelfStableFoodDays.value,2);
 assert.equal(prior.scorecard.assessmentVersion,'dryrun.household-assessment/7');
 await writeFile('../../fixtures/ai/assessment-policy.json',JSON.stringify({synthetic:true,modelCalls:0,method:'Fresh synthetic source snapshots plus actual Swift inventory confirmation and source assessment; no model grades.',source:{before:input,confirmed:changed},shelter:{before:prior,confirmed:reviewed},food:{inaccessible,accessible,oneDay:oneDay.gaps,twoDays:twoDays.gaps,keys:[oneKey.resourceStrategyKey,twoKey.resourceStrategyKey]},assertions:{shelterConfirmationChangesAssessment:true,foodAccessConfirmationChangesAssessment:true,unknownNotAbsent:true,foodGapProjectionAndRefresh:true}},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',shelterPreparation:[prior.scorecard.preparation,reviewed.scorecard.preparation],foodPreparation:[inaccessible.scorecard.preparation,accessible.scorecard.preparation],modelCalls:0}));
} finally {host.close();}
