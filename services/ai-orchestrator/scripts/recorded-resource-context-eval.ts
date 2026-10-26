import assert from 'node:assert/strict';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {Host} from './host.js';
import {featureContext,FeatureRunner} from '../src/features.js';
import {GroqClient} from '../src/groq.js';
import {GeminiPrimaryFallback} from '../src/provider-fallback.js';
import {researchBriefFromPlan} from '../src/resource-discovery.js';
const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
const host=new Host(),ev=(value:unknown)=>({value,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]});
try{
 let state=await host.request({op:'initialize',scenarioID:'water-outage'});
 const input=state.session.initial;input.household.backupPower[0].setupConfirmed={origin:'unknown',status:'unknown',sourceIDs:[],inputIDs:[]};
 state=await host.request({op:'initialize',input});
 const items=[{id:'restricted-water',physicalID:'synthetic-private-label-omit',category:'water',quantity:ev(12),usableQuantity:ev(8),accessible:ev(false),unit:'liter',locationID:'sp-closet',subjectIDs:[input.household.people[1].id],evidenceIDs:['typed-water']},{id:'reachable-water',physicalID:'second-private-label-omit',category:'water',quantity:ev(2),usableQuantity:ev(2),accessible:ev(true),unit:'liter',subjectIDs:[],evidenceIDs:['typed-water']}];
 state=await host.request({op:'confirmInventory',session:state.session,inventoryItems:items,rubric});
 const before=state;
 assert.deepEqual(state.taskCatalog.find((t:any)=>t.actionID==='prep.fireDrill').destination,{kind:'checklist',checklistID:'fireDrill',titleKey:'prep.fireDrill.title'});
 assert.deepEqual(state.taskCatalog.find((t:any)=>t.actionID==='prep.water').destination,{kind:'water'});
 const context=featureContext.parse({household:state.householdContext,taskCatalog:state.taskCatalog,tasks:[],gaps:state.gaps,allowedActionIDs:state.preparationActions,allowedCriterionIDs:rubric.criteria.map((c:any)=>c.id),scene:state.homeScene});
 assert.equal(context.household.inventory?.items[0]?.accessible.value,false);assert.equal(context.household.backupPower?.[0]?.setupConfirmed.value,undefined);
 assert(!JSON.stringify(context).includes('private-label-omit'));
 let primaryCalls=0,secondaryCalls=0;let privateRequest:any;
 const provider=new GeminiPrimaryFallback({async turn(request){primaryCalls++;const sent=JSON.parse((request.history[0] as any).content[0].text);assert.deepEqual(sent.household.inventory,context.household.inventory);assert.deepEqual(sent.household.backupPower,context.household.backupPower);throw new Error('provider_rate_limited');}},new GroqClient('synthetic',undefined,async(_url,request)=>{
  secondaryCalls++;privateRequest=JSON.parse(String(request?.body));const sent=JSON.parse(privateRequest.messages[1].content);assert.deepEqual(sent.household.inventory,context.household.inventory);assert.deepEqual(sent.household.backupPower,context.household.backupPower);assert.equal(privateRequest.tool_choice,'none');
  return Response.json({choices:[{message:{content:JSON.stringify({tasks:[{destination:{kind:'checklist',checklistID:'wrong',titleKey:'wrong'},id:'medical-review',actionID:'prep.medicalBackup',criterionID:'device',subjectID:context.household.equipment[0]!.id,why:'The recorded backup setup remains unknown; review the documented arrangement for the member-linked essential equipment without claiming future runtime.',evidenceIDs:['recorded-backup-power'],completionPredicates:[],editor:'medical',dependencyIDs:[context.household.equipment[0]!.id],priority:0},{id:'proposal',actionID:'prep.bespoke',criterionID:'unscored',subjectID:'restricted-water',why:'Eight usable liters are recorded but inaccessible and restricted to one member. Review a reachable arrangement without treating this case as shared accessible stock.',bespoke:{title:'Review access to recorded water',fact:'The case is recorded in the closet with access false and a member restriction.',implication:'Ownership does not establish accessible household coverage.',action:'Review a reachable arrangement and confirm the observed access and intended users.',completionCheck:'Record the checked location, access and member scope.'},evidenceIDs:['recorded-inventory'],completionPredicates:[],editor:'supplies',dependencyIDs:['restricted-water'],priority:2}],inventoryObservations:[],question:null})}}]});
 }));
 const proposal:any=await new FeatureRunner(provider).run('preparation',context,AbortSignal.timeout(10000),[],['gemini','groq']);
 assert.deepEqual(proposal.tasks[0].destination,{kind:'equipment',subjectID:context.household.equipment[0]!.id});
 state=await host.request({op:'commit',session:state.session,commit:{id:'draw-only-in-simulation',actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'useWater',target:'reachable-water',value:'drink',quantityLiters:0.25}]}});
 assert.deepEqual(state.householdContext.inventory,before.householdContext.inventory);
 assert.notDeepEqual(state.receipt.snapshot.resources,before.receipt.snapshot.resources);
 const brief=researchBriefFromPlan({id:'public-plan',taskID:'task',dependencyIDs:[],hazardIDs:['water-outage'],category:'grocery',purpose:'Private need must not reach browser',mandatoryCapabilities:['Private member details'],unknowns:[],travelMode:'assistance',maximumDistanceKm:15,expansionLimit:1,requiredEvidence:['Published service'],cloudReturnPolicy:'local_only'},{city:'Denver',administrativeArea:'Colorado',countryCode:'US'},true);
 for(const secret of ['inventory','backupPower','restricted-water','Private'])assert(!JSON.stringify(brief).includes(secret));
 const report={synthetic:true,liveModelCalls:0,mode:'actual Core/FeatureRunner/fallback adapter with synthetic HTTP response',passed:true,primaryCalls,secondaryCalls,context,proposal,publicBrief:brief,recordedInventoryUnchanged:true,hostOwnedTaskDestinationPreserved:true,simulationResourcesBefore:before.receipt.snapshot.resources,simulationResourcesAfter:state.receipt.snapshot.resources,native:'pending',humanReview:'pending'};
 const path=process.env.DRYRUN_RECORDED_CONTEXT_OUTPUT??'../../artifacts/ai/recorded-resource-context/result.json';await mkdir(path.slice(0,path.lastIndexOf('/')),{recursive:true});await writeFile(path,JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({passed:true,liveModelCalls:0,primaryCalls,secondaryCalls,recordedInventoryUnchanged:true,privateResourceFactsPreserved:true,publicBriefMinimized:true,artifact:path}));
}finally{host.close();}
