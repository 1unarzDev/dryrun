import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {Host} from './host.js';
const host=new Host();
const confirmed=(value:unknown)=>({value,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]});
try{
 let state=await host.request({op:'initialize',scenarioID:'home-fire'});
 const input=state.session.initial;
 input.spatialOptions={floodAffectedSpaceIDs:[],floodIsHouseholdLeak:false,...input.spatialOptions,startingSpaceIDs:Object.fromEntries(input.household.people.map((p:any)=>[p.id,'sp-kitchen']))};
 state=await host.request({op:'initialize',input});
 state=await host.request({op:'confirmInventory',session:state.session,inventoryItems:[{id:'water',physicalID:'synthetic-container',category:'water',quantity:confirmed(5),unit:'usGallon',usableQuantity:confirmed(5),accessible:confirmed(true),locationID:'sp-kitchen',subjectIDs:[],evidenceIDs:['synthetic-intake']}]});
 const original=structuredClone(state);const person=input.household.people[0].id;
 const commit=(s:any,id:string,actor:string,commands:unknown[])=>host.request({op:'commit',session:s.session,commit:{id,actor,baseRevision:s.receipt.revision,commands}});
 const moved=await commit(state,'move-supplies','user',[{kind:'takeSupply',target:'water',value:person},{kind:'moveTo',target:person,value:'sp-living'},{kind:'transferSupply',target:'water',value:'sp-living'}]);
 const incident=[{kind:'schedule',target:'evt.home-fire.alarm',minute:0},{kind:'schedule',target:'evt.home-fire.fire-origin',minute:1},{kind:'advance',minute:1}];
 const blocked=await commit(state,'incident','director',incident);
 const protectedStock=await commit(moved,'incident','director',incident);
 assert.equal(blocked.receipt.snapshot.resources['res.water.stored'].amount,0);
 assert.equal(protectedStock.receipt.snapshot.resources['res.water.stored'].amount,5);
 for(const s of [blocked,protectedStock]){
  assert.deepEqual(s.session.inventory,original.session.inventory);
  assert.deepEqual(s.session.initial.household,original.session.initial.household);
  assert.deepEqual((await host.request({op:'query',session:s.session})).receipt,s.receipt);
 }
 const stress=await host.request({op:'stress',session:state.session,profileIDs:['evt.home-fire.alarm','evt.home-fire.fire-origin']});
 assert.equal(stress.stress.baseline.inventory.items[0].accessible,false);
 assert.ok(stress.stress.sourceInventoryDigest);
 assert.equal(state.session.dependencyPolicy,'dryrun.dependencies/2');
 for(const [branch,room,access] of [[blocked,'sp-kitchen','unavailable'],[protectedStock,'sp-living','available']] as const){
  const inspected=await host.request({op:'tool',session:branch.session,tool:{kind:'inspectDependencies',baseRevision:branch.receipt.revision}});
  const storage=inspected.tool.dependencies.find((d:any)=>d.kind==='recordedSupplyStorage');
  assert.equal(storage.id,'storage|'+room);assert.deepEqual(storage.subjectIDs,['water']);
  assert.ok(storage.evidenceIDs.includes(branch.receipt.contextDigest));assert.ok(storage.status.includes('access '+access));
  assert.ok(storage.status.includes('Recorded inventory only'));assert.ok(storage.status.includes('cause unproven'));
  assert.deepEqual(inspected.receipt,branch.receipt);
 }
 assert.ok(stress.stress.dependencies.some((d:any)=>d.kind==='recordedSupplyStorage'&&d.status.includes('access unavailable')));
 await writeFile('../../fixtures/ai/inventory-session-trace.json',JSON.stringify({synthetic:true,original,moved,blocked,protectedStock,stress:stress.stress},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',confirmedContainers:1,blockedGallons:0,transferredGallons:5,replay:true,realFactsUnchanged:true,stressUsesInventory:true,recordedAccessDependencies:true}));
}finally{host.close();}
