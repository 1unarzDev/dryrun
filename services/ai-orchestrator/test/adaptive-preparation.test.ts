import {it,expect} from 'vitest';
import {FeatureRunner,featureContext} from '../src/features.js';
const household={revision:3,people:[{id:'person',ageBand:'adult',needs:['communicationSupport'],recordedConditions:'ADHD',essentialMedication:'Synthetic medication, recorded travel instructions',communicationInstructions:'Use a written two-step checklist'}],pets:[],equipment:[],transport:'noCar',limitedBudget:true,regionID:'synthetic',evidence:[{id:'recorded',origin:'userConfirmed',status:'confirmed',sourceIDs:[],fieldIDs:['people']}]};
const context={household,tasks:[],gaps:[],allowedActionIDs:['prep.contact'],allowedCriterionIDs:['contact']};
it('preserves specific fact implication action reasoning and permits grounded tasks beyond the catalog',async()=>{
 const bespoke={title:'Put the two-step departure card by the door',fact:'Written two-step instructions are recorded for this person',implication:'A long spoken checklist will not match the recorded communication arrangement',action:'Prepare a short written departure card and practice it together',completionCheck:'The household can locate and follow its written departure card'};
 const runner=new FeatureRunner({async turn(input){expect(JSON.stringify(input.history)).toContain('Synthetic medication');expect(input.instruction).toContain('not a closed task universe');return {text:JSON.stringify({tasks:[{destination:{kind:'home',subjectID:'invented-room'},id:'model-id',actionID:'anything',criterionID:'anything',subjectID:'person',why:bespoke.fact+'; '+bespoke.implication+'; '+bespoke.action,bespoke,evidenceIDs:['recorded'],completionPredicates:['invented-credit'],editor:'family',dependencyIDs:['person'],priority:0}],inventoryObservations:[],question:null}),steps:[],calls:[],usage:{}};}});
 const result:any=await runner.run('preparation',context);
 expect(result.tasks[0].destination).toBeUndefined();expect(result.tasks[0].id).toMatch(/^bespoke-/);expect(result.tasks[0].criterionID).toBe('unscored');expect(result.tasks[0].completionPredicates).toEqual([]);expect(result.tasks[0].why).toContain(bespoke.implication);expect(result.tasks[0].priority).toBe(2);
});
it('rejects a bespoke task attributed to an invented person and forbidden private fields',async()=>{
 expect(featureContext.safeParse({...context,household:{...household,contactPhones:['private']}}).success).toBe(false);
 const repairs:string[]=[];
 const runner=new FeatureRunner({async turn(input){repairs.push(JSON.stringify(input.history.at(-1)));return {text:JSON.stringify({tasks:[{id:'task',actionID:'prep.bespoke',criterionID:'unscored',subjectID:'invented-person',why:'Specific supported improvement',bespoke:{title:'Task',fact:'Recorded fact',implication:'Practical implication',action:'Concrete action',completionCheck:'Observable completion'},evidenceIDs:['recorded'],completionPredicates:[],editor:'family',dependencyIDs:[],priority:2}],inventoryObservations:[],question:null}),steps:[],calls:[],usage:{}};}});
 // The bounded repair names the rejection; a repeated invented attribution ends as a typed unavailable failure.
 await expect(runner.run('preparation',context)).rejects.toThrow('provider_validation_failure');
 expect(repairs).toHaveLength(2);expect(repairs[1]).toContain('unsupported_bespoke_task');
});
it('keeps catalog routing and predicates host-owned while retaining model reasoning',async()=>{
 const catalog={destination:{kind:'contact',contactRole:'outOfAreaContact'},id:'host-id',actionID:'prep.contact',criterionID:'contact',subjectID:'household',why:'Host explanation',evidenceIDs:['recorded'],completionPredicates:['usableContact'],editor:'contacts',dependencyIDs:['contacts'],priority:1};
 const runner=new FeatureRunner({async turn(){return {text:JSON.stringify({tasks:[{...catalog,id:'invented-id',destination:{kind:'checklist',checklistID:'unrelated',titleKey:'unrelated'},editor:'home',completionPredicates:['invented-predicate'],priority:3,why:'The recorded communication instructions call for a short written list; put the actual contact method on that list and practice locating it.'}],inventoryObservations:[],question:null}),steps:[],calls:[],usage:{}};}});
 const output:any=await runner.run('preparation',{...context,taskCatalog:[catalog]});
 expect(output.tasks[0]).toMatchObject({id:'host-id',destination:catalog.destination,editor:'contacts',priority:1,completionPredicates:['usableContact']});
 expect(output.tasks[0].why).toContain('short written list');
});
it('repairs an explicit future safety assurance while preserving the bespoke supported preparation',async()=>{
 let calls=0;
 const runner=new FeatureRunner({async turn(input){calls++;
  const why=calls===1?'Practicing your recorded two-step written list ensures safe, guided egress.':'The recorded communication arrangement uses two written steps; draft that list together and practice locating the agreed exit instructions. A practice attempt records present evidence.';
  if(calls===2)expect(input.history.at(-1)).toMatchObject({type:'user_input',content:[{type:'text',text:expect.stringContaining('unsupported_safety_assurance')}]});
  return {text:JSON.stringify({tasks:[{id:'proposal',actionID:'prep.bespoke',criterionID:'unscored',subjectID:'person',why,bespoke:{title:'Prepare the recorded written list',fact:'Two-step written instructions are recorded',implication:'The practice format should match those instructions',action:'Draft the list together and practice locating it',completionCheck:'Record whether the person found the list and identified the instructions'},evidenceIDs:['recorded'],completionPredicates:[],editor:'family',dependencyIDs:['person'],priority:2}],inventoryObservations:[],question:null}),steps:[],calls:[],usage:{}};
 }});
 const output:any=await runner.run('preparation',context);
 expect(calls).toBe(2);expect(output.tasks[0].why).toContain('draft that list together');
});
it('repairs unsupported inventory extraction by removing it rather than assigning household evidence',async()=>{
 let calls=0;const runner=new FeatureRunner({async turn(input){calls++;
  // Without intake evidence the output schema permits no observations; the bounded repair names the rejected field.
  if(calls===2)expect(JSON.stringify(input.history.at(-1))).toContain('inventoryObservations');
  return {text:JSON.stringify({tasks:[],inventoryObservations:calls===1?[{id:'invented'}]:[],question:null}),steps:[],calls:[],usage:{}};
 }});
 const output:any=await runner.run('preparation',context);expect(calls).toBe(2);expect(output.inventoryObservations).toEqual([]);
});
it('retains member-restricted inaccessible stock and backup setup uncertainty in substantive supply tasks',async()=>{
 const value=(v:unknown)=>({value:v,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]});
 const inventory={scope:'recordedHouseholdInventory',revision:2,asOf:'2026-10-20T00:00:00Z',items:[{id:'water-case',category:'water',unit:'liter',quantity:value(12),usableQuantity:value(8),accessible:value(false),locationID:'upstairs',subjectIDs:['person'],evidenceIDs:['typed-water']}]};
 const backupPower=[{id:'battery',kind:'portableBatteryStation',usableEnergyWh:value(600),continuousOutputW:value(500),setupConfirmed:{origin:'unknown',status:'unknown',sourceIDs:[],inputIDs:[]},islandingConfirmed:value(false),safeOutdoorPlacementConfirmed:{origin:'unknown',status:'unknown',sourceIDs:[],inputIDs:[]},assumedEfficiency:0.85}];
 const runner=new FeatureRunner({async turn(input){const sent=JSON.parse((input.history[0] as any).content[0].text);expect(sent.household.inventory).toEqual(inventory);expect(sent.household.backupPower).toEqual(backupPower);expect(input.instruction).toContain('Never add its totals to legacy supplies');
  return {steps:[],calls:[],usage:{},text:JSON.stringify({tasks:[{id:'proposal',actionID:'prep.bespoke',criterionID:'unscored',subjectID:'water-case',why:'Eight usable liters are recorded upstairs but inaccessible; review a reachable storage arrangement for the recorded member rather than buying the same stock again.',bespoke:{title:'Review access to the recorded water case',fact:'The case has eight usable liters recorded and access is confirmed false.',implication:'Owned stock does not currently provide recorded accessible coverage.',action:'Agree a reachable storage arrangement and explicitly update its access record after checking.',completionCheck:'Record the reviewed location and observed access.'},evidenceIDs:['recorded'],completionPredicates:[],editor:'supplies',dependencyIDs:['water-case'],priority:2}],inventoryObservations:[],question:'Who can check the recorded case and its intended access arrangement?'})};
 }});
 const result:any=await runner.run('preparation',{...context,household:{...household,inventory,backupPower}});
 expect(result.tasks[0].subjectID).toBe('water-case');expect(result.tasks[0].why).toContain('rather than buying');expect(result.inventoryObservations).toEqual([]);
});

it('accepts precise existing destinations and rejects incomplete or invented editor targets',()=>{
 const base={id:'task',actionID:'prep.fireDrill',criterionID:'escape',subjectID:'household',why:'Review the actual drill',evidenceIDs:['recorded'],completionPredicates:[],editor:'supplies',dependencyIDs:[],priority:2};
 for(const destination of [{kind:'checklist',checklistID:'fireDrill',titleKey:'prep.fireDrill.title'},{kind:'water'},{kind:'transport'},{kind:'home',subjectID:'opening-one'}])expect(featureContext.safeParse({...context,tasks:[{...base,destination}]}).success).toBe(true);
 for(const destination of [{kind:'checklist'},{kind:'newScreen'},{kind:'contact',contactRole:'invented'}])expect(featureContext.safeParse({...context,tasks:[{...base,destination}]}).success).toBe(false);
});
