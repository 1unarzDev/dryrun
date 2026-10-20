import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
const host=new Host();const rows:any[]=[];
const ev=(value:any)=>({value,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]});
const command=(kind:string,target?:string,value?:string,quantityLiters?:number)=>({kind,...target?{target}:{},...value?{value}:{},...quantityLiters?{quantityLiters}:{}});
async function act(state:any,commands:any[],actor='user'){try{return await host.request({op:'commit',session:state.session,commit:{id:`branch-${state.receipt.revision}`,actor,baseRevision:state.receipt.revision,commands}});}catch(error){throw new Error(String(error)+' '+JSON.stringify(commands));}}
async function incident(state:any,id:string){return act(state,[{kind:'schedule',target:id,minute:0},{kind:'advance',minute:0}],'director');}
async function pair(state:any,a:any[],b:any[],label:string,advance?:number){
 let left=await act(state,a),right=await act(state,b);
 if(advance){left=await act(left,[{kind:'advance',minute:advance}],'director');right=await act(right,[{kind:'advance',minute:advance}],'director');}
 assert.notDeepEqual({experience:left.receipt.experience,resources:left.receipt.snapshot.resources,services:left.receipt.snapshot.services,routes:left.receipt.routes},{experience:right.receipt.experience,resources:right.receipt.snapshot.resources,services:right.receipt.snapshot.services,routes:right.receipt.routes},label+' must change computed consequences');
 for(const branch of [left,right]){const replay=await host.request({op:'query',session:JSON.parse(JSON.stringify(branch.session))});assert.equal(replay.receipt.contextDigest,branch.receipt.contextDigest);}
 return {label,initial:state,alternatives:[{commands:a,result:left},{commands:b,result:right}],offlineReplay:'passed'};
}
try{
 await mkdir('../../artifacts/ai/six-hazard',{recursive:true});
 const base=await host.request({op:'initialize',scenarioID:'home-fire'}),household=base.session.initial.household,home=base.session.initial.home;
 household.equipment[0].compatibleBackupIDs=['bk-station'];household.equipment[0].powerWatts=ev(100);household.equipment[0].documentedBackupRuntimeHours=ev(4);household.backupPower[0].setupConfirmed=ev(true);
 household.housing.waterSource='municipal';household.supplies.storedWaterGallons=ev(12);
 household.preparedness={items:{warmth:{available:ev(true),location:"Synthetic closet",notes:""}}};
 household.transport={vehicles:[{id:'car',seats:8,wheelchairAccessible:ev(true),isElectric:false}],alternatives:[],destinations:[{id:'alternative',kind:'friendOrFamilyHome',label:'Synthetic agreed alternative',conditionsConfirmed:ev(true),acceptsPets:ev(true),stepFreeAccess:ev(true)}]};
 household.people.forEach((p:any)=>p.sleepingSpaceID='sp-bed1');
 const [p1,p2]=household.people.map((p:any)=>p.id);
 for(const id of ['home-fire','tornado','flash-flood','freeze-power-loss','heat-grid-strain','water-outage']){
  const row:any={hazard:id,synthetic:true};
  try{
   const original=await host.request({op:'initialize',scenarioID:id});
   const initial={...original.session.initial,household,home};
   let state=await host.request({op:'initialize',input:initial});
   const decisions:any[]=[];let variantInput=structuredClone(initial),probe:any;
   if(id==='home-fire'){
    state=await incident(state,'evt.home-fire.alarm');
    const exitChoices=state.receipt.experience.feasibleCommands.filter((c:any)=>c.kind==='escape'&&c.target===p1);
    assert(exitChoices.length>=2,'the common recorded home must support two actual exit choices');
    const [front,back]=exitChoices;
    decisions.push(await pair(state,[front],[back],'Choose different supported exits from the same occupied starting room'));
    state=await act(state,[front]);
    decisions.push(await pair(state,[command('accountOutside',p1)],[command('escape',p2,back.value)],'Outside accounting versus another occupant completing their own escape; no reentry'));
    variantInput.home.portals.find((p:any)=>p.id===front.value).operable=ev(false);probe=front;
    const blocked=await host.request({op:'initialize',input:variantInput});
    await assert.rejects(act(blocked,[front]),/invalidCommand/);
    const alternate=await act(blocked,[back]);
    assert(alternate.receipt.experience.outsidePersonIDs.includes(p1));
    row.blockedExitAdaptation={rejected:front,accepted:back,result:alternate};
   }else if(id==='tornado'){
    const shelter=state.receipt.experience.shelterRoomID;
    decisions.push(await pair(state,[command('reachShelter',p1,shelter)],[command('reachShelter',p2,shelter)],'Which occupant reaches shelter first'));
    state=await act(state,[command('reachShelter',p1,shelter)]);
    // The recorded helper either arrives alone or approaches and accompanies the mobility-limited member.
    const dependent=household.people.find((p:any)=>p.helperPersonID===p2 && p.needs.includes('limitedMobility'));
    assert(dependent,'representative fixture needs the recorded assistance arrangement');
    decisions.push(await pair(state,[command('reachShelter',p2,shelter)],[command('accompanyShelter',dependent.id,p2)],'Helper arrives alone versus computed accompaniment of mobility-limited member'));
    variantInput.household.housing.homeType='manufacturedHome';probe=command('reachShelter',p1,shelter);
   }else if(id==='flash-flood'){
    decisions.push(await pair(state,[command('leaveEarly','alternative')],[command('identifyGap','higherRefuge')],'Early departure versus recognizing absent higher refuge'));
    state=await incident(state,'evt.flash-flood.warning');
    decisions.push(await pair(state,[command('identifyGap','departureAccess')],[command('identifyGap','higherRefuge')],'Recognize the actual trapped-case dependency'));
    variantInput.household.transport.vehicles=[];probe=command('leaveEarly','alternative');
   }else if(id==='freeze-power-loss'){
    const outage=state.directorProfiles.find((p:any)=>p.rule==='setExternal'&&p.id.includes('outage'))??state.directorProfiles.find((p:any)=>p.id.includes('grid'));
    const profile=original.profiles.find((p:any)=>p.rule==='setExternal'&&p.id.includes('grid'));
    const event={id:'evt.freeze-power-loss.grid-loss'};
    state=await incident(state,event?.id??'evt.freeze-power-loss.grid-outage');
    const equipment=household.equipment[0],source=equipment.compatibleBackupIDs[0];
    decisions.push(await pair(state,[command('allocatePower',equipment.id,source)],[command('allocatePower',equipment.id,'none')],'Essential device backup allocation',60));
    decisions.push(await pair(state,[command('warmLayers')],[command('heatedAlternative','alternative')],'Warmth preparation versus recorded heated alternative',180));
    variantInput.household.preparedness.items.warmth.available=ev(false);probe=command('warmLayers');
   }else if(id==='heat-grid-strain'){
    assert.equal(state.receipt.snapshot.services['svc.grid'],'operational');
    const shade=state.receipt.experience.feasibleCommands.find((c:any)=>c.kind==='reduceSolarGain');
    decisions.push(await pair(state,[shade],[command('cooledAlternative','alternative')],'Cooling preparation with electricity still available'));
    const outage=state.directorProfiles.find((p:any)=>p.id.includes('outage'));
    state=await incident(state,outage.id);
    decisions.push(await pair(state,[shade],[command('cooledAlternative','alternative')],'Adapt after actual cooling loss',180));
    variantInput.household.transport.vehicles=[];probe=command('cooledAlternative','alternative');
   }else{
    decisions.push(await pair(state,[command('useWater','recordedStored','drink',0.25)],[command('useWater','recordedStored','hygiene',1)],'Activity and conserved quantity'));
    initial.variants=['boil-water'];state=await host.request({op:'initialize',input:initial});state=await incident(state,'evt.water-outage.boil-advisory');
    decisions.push(await pair(state,[command('useWater','tap','hygiene',0.25)],[command('useWater','recordedStored','drink',0.25)],'Flowing advisory water versus stored drinking supply'));
    variantInput.household.supplies.storedWaterGallons=ev(0);probe=command('useWater','recordedStored','drink',0.25);
   }
   const variant=await host.request({op:'initialize',input:variantInput});
   await assert.rejects(act(variant,[probe]),/invalidCommand/);
   row.status='passed';row.decisions=decisions;row.variant={input:variantInput,rejectedCommand:probe};
  }catch(error){row.status='failed';row.error=error instanceof Error?error.message:'unknown';process.exitCode=1;}
  rows.push(row);console.log(JSON.stringify({hazard:id,status:row.status,error:row.error}));
  await writeFile('../../artifacts/ai/six-hazard/branch-report.json',JSON.stringify({mode:'Linux deterministic host',synthetic:true,modelCalls:0,rows,native:'pending',humanReview:'pending',limits:'Computed branch comparisons; not independent human adjudication or proof of native experience quality.'},null,2)+'\n');
 }
 if(rows.every(row=>row.status==='passed')){
  const branches=rows.flatMap(row=>row.decisions.flatMap((decision:any)=>decision.alternatives.map((branch:any)=>{
   const {household:branchHousehold,home:branchHome,...initial}=branch.result.session.initial;
   assert.deepEqual(branchHousehold,household);assert.deepEqual(branchHome,home);
   return {hazard:row.hazard,decision:decision.label,session:{...branch.result.session,initial},expected:{contextDigest:branch.result.receipt.contextDigest,experience:branch.result.receipt.experience,snapshot:branch.result.receipt.snapshot}};
  })));
  await writeFile('../../fixtures/ai/six-hazard-mechanics.json',JSON.stringify({version:'dryrun.six-hazard-replay/1',synthetic:true,mode:'recorded deterministic host, no model calls',household,home,branches,native:'pending',humanReview:'pending'},null,2)+'\n');
 }
}finally{host.close();}
