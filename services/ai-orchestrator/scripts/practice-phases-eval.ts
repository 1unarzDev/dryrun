import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {practicePhasePlan,practiceObservation} from '../src/practice-contracts.js';
const host=new Host();
const nonDevice=process.env.DRYRUN_PRACTICE_NONDEVICE==='1';
const reverse=process.env.DRYRUN_PRACTICE_REVERSE==='1';
const variantID='practice-check-'+(reverse?'b':'a')+'/'+(nonDevice?2:1);
try {
 const policy=JSON.parse(await readFile('../../content/ai/practice-check-phases-v'+(nonDevice?2:1)+'.json','utf8'));
 const order:string[]=policy.variants.find((variant:any)=>variant.id===variantID).order;
 const sample=await host.request({op:'initialize',scenarioID:'home-fire'});
 const initial=structuredClone(sample.session.initial),home=initial.home,floor=home.floors[0],space=home.spaces[0],portal=home.portals[0];
 const room=(id:string,kind:string,x0:number,x1:number)=>({...space,id,label:id,kind,floorID:floor.id,polygon:[{x:x0,y:0},{x:x1,y:0},{x:x1,y:4},{x:x0,y:4}]});
 const side=(id?:string)=>id?{space:{_0:id}}:{exterior:{}};
 const door=(id:string,x:number,a:string,b?:string)=>({...portal,id,note:'Synthetic verified doorway',a:{x,y:1},b:{x,y:2},sideA:side(a),sideB:side(b),floorID:floor.id});
 home.id='synthetic-practice-phases';home.source='manual';home.isFictional=true;
 home.floors=[{...floor,exteriorGrade:'ground'}];home.spaces=[room('start','bedroom',4,8),room('kitchen','kitchen',8,10),room('living','livingRoom',0,4)];
 home.portals=[door('to-kitchen',8,'start','kitchen'),door('kitchen-exit',10,'kitchen'),door('to-living',4,'start','living'),door('living-exit',0,'living')];
 home.walls=[];home.obstacles=[];home.connectors=[];home.annotations=[];delete home.meetingPoint;
 initial.household.people=initial.household.people.slice(0,1);const person=initial.household.people[0].id;
 initial.household.people[0].sleepingSpaceID='start';delete initial.spatialOptions;
 const confirmed=(value:unknown)=>({value,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]});
 initial.household.equipment=[{...initial.household.equipment[0],id:'device',purpose:'communicationDevice',label:'Synthetic communication device',personID:person,isEssential:true,compatibleBackupIDs:['battery'],documentedBackupRuntimeHours:confirmed(4),powerWatts:confirmed(10),needsRefrigeration:false}];
 initial.household.backupPower=[{...initial.household.backupPower[0],id:'battery',kind:'portableBatteryStation',label:'Synthetic battery',usableEnergyWh:confirmed(100),continuousOutputW:confirmed(100),setupConfirmed:confirmed(true),assumedEfficiency:0.85}];
 if(nonDevice){initial.household.equipment=[];initial.household.backupPower=[];initial.household.supplies.limitedBudget=true;}
 initial.household.contacts=[{id:'contact',role:'outOfAreaContact',alias:'Synthetic contact',phone:'555-0100'}];
 const sources:any[]=[];
 for(const [competency,scenarioID,events] of [
  ['initialResponse',nonDevice?'home-fire':'water-outage',nonDevice?['evt.home-fire.alarm']:['evt.water-outage.well-pump-failure']],
  ['adaptation','home-fire',['evt.home-fire.alarm','evt.home-fire.fire-origin']],
  ['communication','water-outage',['evt.water-outage.well-pump-failure']],
  ['continuity',nonDevice?'water-outage':'freeze-power-loss',nonDevice?['evt.water-outage.well-pump-failure']:['evt.freeze-power-loss.grid-loss']],
 ] as const){
  const definition=await host.request({op:'initialize',scenarioID});
  const input={...structuredClone(initial),scenarioID,scenarioVersion:definition.session.initial.scenarioVersion};
  let state=await host.request({op:'initialize',input});state.session.id='phase-'+competency;
  for(const [n,event] of events.entries())state=await host.request({op:'commit',session:state.session,commit:{id:'setup-'+competency+'-'+n,actor:'director',baseRevision:state.receipt.revision,commands:[{kind:'schedule',target:event,minute:n},{kind:'advance',minute:n}]}});
  sources.push(state.session);
 }
 sources.sort((a,b)=>order.indexOf(a.id.replace('phase-',''))-order.indexOf(b.id.replace('phase-','')));
 const seed=JSON.parse(await readFile('../../fixtures/ai/practice-capture.json','utf8')).begun;
 seed.sessions=sources;seed.practiceAttempts=[];seed.scorecards=[];
 const begun=await host.request({op:'practiceCheckBegin',session:sources[0],aiState:seed,attemptID:'four-situations',variantID,practiceSessionIDs:sources.map(s=>s.id)});
 const plan=practicePhasePlan.parse({variantID:begun.aiState.practiceAttempts[0].variantID,phaseSources:begun.aiState.practiceAttempts[0].phaseSources});
 assert.equal(plan.phaseSources.length,4);
 const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
 const commands=[nonDevice?{kind:'choose',target:'choice.home-fire.first-move',value:'get-out'}:{kind:'useStoredWater',value:'essential'},{kind:'moveTo',target:person,value:'living'},{kind:'contact',target:'contact'},nonDevice?{kind:'useStoredWater',value:'essential'}:{kind:'allocatePower',target:'device',value:'battery'}];
 const canonicalOrder=['initialResponse','adaptation','communication','continuity'];
 const wrongFirst=reverse?(nonDevice?{kind:'useStoredWater',value:'all'}:{kind:'allocatePower',target:'device',value:'none'}):(nonDevice?{kind:'choose',target:'choice.home-fire.first-move',value:'grab-belongings'}:{kind:'useStoredWater',value:'all'});
 const branches:any[]=[];
 for(const wrong of [false,true]){
  let local=structuredClone(begun.aiState);const checkpoints:any[]=[];
  for(const [index,competencyID] of order.entries()){
   const current=local.sessions.find((s:any)=>s.id===plan.phaseSources[index]!.sessionID);
   const commit={id:(wrong?'wrong-':'correct-')+competencyID,actor:'user',baseRevision:current.commits.length,commands:[wrong&&index===0?wrongFirst:commands[canonicalOrder.indexOf(competencyID)]]};
   let state=await host.request({op:'practiceSubmit',session:current,aiState:local,attemptID:'four-situations',competencyID,commit});
   const observed=practiceObservation.parse(state.aiState.practiceAttempts[0].observations.at(-1));
   assert.equal(observed.credit,wrong&&index===0?0:1);assert.equal(observed.feedbackRevealed,false);
   if(reverse&&index<3){
    const resumed=await host.request({op:'practiceCheckBegin',session:state.session,aiState:JSON.parse(JSON.stringify(state.aiState)),attemptID:'before-feedback-reroll',variantID:'practice-check-a/'+(nonDevice?2:1),practiceSessionIDs:[]});
    assert.deepEqual(resumed.aiState,state.aiState);
    assert.equal(resumed.aiState.practiceAttempts[0].observations.at(-1).feedbackRevealed,false);
   }
   state=await host.request({op:'practiceFeedback',session:state.session,aiState:JSON.parse(JSON.stringify(state.aiState)),attemptID:'four-situations',feedbackActionID:commit.id});
   local=state.aiState;
   const card=(await host.request({op:'assess',session:state.session,aiState:local,rubric})).scorecard;
   assert.equal(card.practice,(index+1-(wrong?1:0))*25);assert.equal(card.practiceAssessed,index+1);assert.equal(card.provisional,true);
   for(const session of local.sessions)assert.deepEqual(session.initial,sources.find(s=>s.id===session.id).initial);
   checkpoints.push({competencyID,commit,observation:observed,feedbackObservation:structuredClone(local.practiceAttempts[0].observations.at(-1)),receipt:state.receipt,scorecard:card});
   if(index===0){
    const resumed=await host.request({op:'practiceCheckBegin',session:state.session,aiState:JSON.parse(JSON.stringify(local)),attemptID:'reroll',variantID:'practice-check-'+(reverse?'a':'b')+'/'+(nonDevice?2:1),practiceSessionIDs:[]});
    assert.equal(resumed.aiState.practiceAttempts[0].id,'four-situations');assert.equal(resumed.aiState.practiceAttempts[0].variantID,variantID);
    assert.deepEqual(resumed.aiState.practiceAttempts[0].observations,local.practiceAttempts[0].observations);
   }
  }
  const last=checkpoints.at(-1)!;assert.equal(last.scorecard.practice,wrong?75:100);
  const corrupted=structuredClone(local);corrupted.practiceAttempts[0].observations[0].credit=wrong?1:0;
  await assert.rejects(host.request({op:'assess',session:local.sessions[0],aiState:corrupted,rubric}),/invalidCommand/);
  branches.push({wrongFirst:wrong,checkpoints,final:local,practice:last.scorecard.practice,practiceAssessed:4});
 }
 let resourceProof:any;
 if(nonDevice){
  const source=sources.find(s=>s.id==='phase-continuity'),projections:any[]=[];
  const original=(await host.request({op:'query',session:source})).receipt;
  for(const policy of ['essential','all']){
   const actionCommit={id:'proof-'+policy,actor:'user',baseRevision:source.commits.length,commands:[{kind:'useStoredWater',value:policy}]};
   const action=await host.request({op:'commit',session:source,commit:actionCommit});
   const forecastCommit={id:'forecast-'+policy,actor:'director',baseRevision:action.receipt.revision,commands:[{kind:'advance',minute:60}]};
   const forecast=await host.request({op:'preview',session:action.session,commit:forecastCommit});
   projections.push({policy,actionCommit,forecastCommit,receipt:forecast.receipt});
  }
  assert.equal(projections[0].receipt.snapshot.simMinute,projections[1].receipt.snapshot.simMinute);
  assert.ok(projections[0].receipt.snapshot.resources['res.water.stored'].amount>projections[1].receipt.snapshot.resources['res.water.stored'].amount);
  assert.deepEqual((await host.request({op:'query',session:source})).receipt,original);
  resourceProof={sourceID:source.id,original,projections};
 }
 await writeFile('../../fixtures/ai/practice-'+(nonDevice?'nondevice':'phases')+(reverse?'-reverse':'')+'.json',JSON.stringify({synthetic:true,liveModel:false,modelCalls:0,version:policy.version,...(nonDevice?{equipmentRequired:false,limitedBudget:true,resourceProof}:{}),sources,begun:begun.aiState,plan,branches},null,2)+'\n');
 console.log(JSON.stringify({passed:true,modelCalls:0,variantID,equipmentRequired:!nonDevice,competencies:4,correctPractice:100,wrongFirstPractice:75,resumedWithoutReroll:true,preFeedbackCapture:true,sourcePreserved:true,roundTrip:true,tamperingRejected:true,provisional:true}));
}finally{host.close();}
