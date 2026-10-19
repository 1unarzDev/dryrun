import {resourceStrategyKey} from '../src/resource-refresh-contracts.js';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
const host=new Host();
try{
 const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
 let state=await host.request({op:'initialize',sample:'oak',scenarioID:'water-outage',rubric});
 const item=(gallons:number)=>({id:'water',physicalID:'one-store',category:'water',quantity:{value:gallons,origin:'userConfirmed',status:'confirmed'},unit:'usGallon',usableQuantity:{value:gallons,origin:'userConfirmed',status:'confirmed'},accessible:{value:true,origin:'userConfirmed',status:'confirmed'},subjectIDs:[],evidenceIDs:['typed-water']});
 state=await host.request({op:'confirmInventory',session:state.session,inventoryItems:[item(5)],rubric});
 const task=state.taskCatalog.find((t:any)=>t.actionID==='prep.water');if(!task)throw new Error('water_task_missing');
 const a=await host.request({op:'resourceKey',session:state.session,resourceTasks:[task]});
 resourceStrategyKey.parse(a.resourceStrategyKey);
 const wording=await host.request({op:'resourceKey',session:state.session,resourceTasks:[{...task,why:'Same need in different wording',evidenceIDs:['reordered-explanation'],dependencyIDs:[...task.dependencyIDs].reverse()}]});
 if(JSON.stringify(a.resourceStrategyKey)!==JSON.stringify(wording.resourceStrategyKey))throw new Error('wording_refresh');
 const changed=await host.request({op:'confirmInventory',session:state.session,inventory:state.inventory,inventoryItems:[item(6)],rubric});
 const b=await host.request({op:'resourceKey',session:changed.session,resourceTasks:[task]});
 if(a.resourceStrategyKey.normalizedInputDigest===b.resourceStrategyKey.normalizedInputDigest)throw new Error('quantity_change_missed');
 const dependency=await host.request({op:'resourceKey',session:changed.session,resourceTasks:[task],strategyDependencies:[{id:'water-access-arrangement',state:'unknown'}]});
 if(b.resourceStrategyKey.normalizedInputDigest===dependency.resourceStrategyKey.normalizedInputDigest)throw new Error('dependency_missed');
 const privateEdit=structuredClone(changed.session);privateEdit.initial.household.people[0].alias='Changed fictional display name';privateEdit.initial.household.revision++;
 const unrelated=await host.request({op:'resourceKey',session:privateEdit,resourceTasks:[task]});
 if(JSON.stringify(b.resourceStrategyKey)!==JSON.stringify(unrelated.resourceStrategyKey))throw new Error('unrelated_edit_refresh');
 await writeFile('../../fixtures/ai/resource-refresh.json',JSON.stringify({synthetic:true,newModelCalls:0,sourceInventoryConfirmed:true,keys:{fiveGallons:a.resourceStrategyKey,sixGallons:b.resourceStrategyKey,wording:wording.resourceStrategyKey,explicitDependency:dependency.resourceStrategyKey,unrelatedDisplayEdit:unrelated.resourceStrategyKey},gaps:{fiveGallons:state.gaps,sixGallons:changed.gaps},assertions:{changedDeficitInvalidates:true,wordingIgnored:true,explicitDependencyInvalidates:true,unrelatedDisplayEditIgnored:true}},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',actualInventoryArithmetic:true,changedDeficitInvalidates:true,wordingIgnored:true,explicitDependencyInvalidates:true,unrelatedDisplayEditIgnored:true}));
}finally{host.close();}
