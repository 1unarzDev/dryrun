import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
const host=new Host(),results=[];
const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
const confirmed=(value:unknown)=>({value,origin:'userConfirmed',status:'confirmed'});
try {
 for(const [kind,category,predicate,actionID] of [['flashlight','light','light','prep.flashlight'],['firstAidKit','firstAid','firstAid','prep.firstAid']] as const) {
  const initial=await host.request({op:'initialize',sample:'oak',scenarioID:'freeze-power-loss',rubric});
  const item={id:kind,physicalID:kind,category,preparationKind:kind,quantity:confirmed(0),unit:'count',usableQuantity:confirmed(0),accessible:confirmed(true),subjectIDs:[],evidenceIDs:['synthetic-review']};
  const empty=await host.request({op:'confirmInventory',session:initial.session,inventoryItems:[item],rubric});
  const before=await host.request({op:'assess',session:empty.session,inventory:empty.inventory,rubric});
  assert.equal(before.assessments.find((a:any)=>a.criterionID==='essentials').predicates[predicate],false);
  const task=empty.taskCatalog.find((t:any)=>t.actionID===actionID);assert.ok(task);
  const oldKey=await host.request({op:'resourceKey',session:empty.session,resourceTasks:[task]});
  const stock=await host.request({op:'confirmInventory',session:empty.session,inventory:empty.inventory,inventoryItems:[{...item,quantity:confirmed(2),usableQuantity:confirmed(2)}],rubric});
  const after=await host.request({op:'assess',session:stock.session,inventory:stock.inventory,rubric});
  assert.equal(after.assessments.find((a:any)=>a.criterionID==='essentials').predicates[predicate],true);
  const newKey=await host.request({op:'resourceKey',session:stock.session,resourceTasks:[task]});
  assert.notEqual(oldKey.resourceStrategyKey.normalizedInputDigest,newKey.resourceStrategyKey.normalizedInputDigest);
  assert.equal(stock.gaps.find((g:any)=>g.category===category).deficit,0);
  assert.equal(stock.taskCatalog.filter((t:any)=>t.actionID===actionID).length,1);
  assert.equal(stock.taskCatalog.find((t:any)=>t.actionID===actionID).why,'prep.location.why');
  assert.deepEqual(stock.taskCatalog.find((t:any)=>t.actionID===actionID).completionPredicates,[predicate]);
  const generic=await host.request({op:'confirmInventory',session:stock.session,inventory:stock.inventory,inventoryItems:[{...item,preparationKind:null,quantity:confirmed(2),usableQuantity:confirmed(2)}],rubric});
  const untyped=await host.request({op:'assess',session:generic.session,inventory:generic.inventory,rubric});
  assert.equal(untyped.assessments.find((a:any)=>a.criterionID==='essentials').predicates[predicate],undefined);
  results.push({kind,category,initial:before.assessments.find((a:any)=>a.criterionID==='essentials'),confirmed:after.assessments.find((a:any)=>a.criterionID==='essentials'),generic:untyped.assessments.find((a:any)=>a.criterionID==='essentials'),gap:stock.gaps.find((g:any)=>g.category===category),task:stock.taskCatalog.find((t:any)=>t.actionID===actionID),resourceRefreshChanged:true,preparation:[before.scorecard.preparation,after.scorecard.preparation]});
 }
 await writeFile('../../fixtures/ai/preparation-inventory-v1.json',JSON.stringify({synthetic:true,newModelCalls:0,assessmentVersion:'dryrun.household-assessment/5',results,limits:'Identity and usable count are reviewed; location, technique, kit suitability for specific needs and non-water consumption remain separately unassessed. Native review/save not tested.'},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',kinds:results.length,realConfirmation:true,scorePropagation:true,resourceRefresh:true,genericIdentityClearsCredit:true,newModelCalls:0}));
}finally{host.close();}
