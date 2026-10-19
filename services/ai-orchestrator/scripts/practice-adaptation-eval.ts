import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {practiceSource} from '../src/practice-contracts.js';
// A deliberately small synthetic verified graph; not a claim about any real home's safety.
const host=new Host();
try {
 const sample=await host.request({op:'initialize',sample:'oak',scenarioID:'home-fire'});
 const input=structuredClone(sample.session.initial),home=input.home;
 const floor=home.floors[0],space=home.spaces[0],portal=home.portals[0];
 const room=(id:string,kind:string,x0:number,x1:number)=>({...space,id,label:id,kind,floorID:floor.id,polygon:[{x:x0,y:0},{x:x1,y:0},{x:x1,y:4},{x:x0,y:4}]});
 const side=(id?:string)=>id?{space:{_0:id}}:{exterior:{}};
 const door=(id:string,x:number,a:string,b?:string)=>({...portal,id,note:'Synthetic verified doorway',a:{x,y:1},b:{x,y:2},sideA:side(a),sideB:side(b),floorID:floor.id});
 home.id='synthetic-two-branches';home.source='manual';home.isFictional=true;
 home.floors=[{...floor,exteriorGrade:'ground'}];home.spaces=[room('start','bedroom',4,8),room('kitchen','kitchen',8,10),room('living','livingRoom',0,4)];
 home.portals=[door('to-kitchen',8,'start','kitchen'),door('kitchen-exit',10,'kitchen'),door('to-living',4,'start','living'),door('living-exit',0,'living')];
 home.walls=[];home.obstacles=[];home.connectors=[];home.annotations=[];delete home.meetingPoint;
 input.household.people=input.household.people.slice(0,1);input.household.people[0].sleepingSpaceID='start';delete input.spatialOptions;
 let state=await host.request({op:'initialize',input});
 const commit=async(id:string,commands:unknown[])=>host.request({op:'commit',session:state.session,commit:{id,actor:'director',baseRevision:state.receipt.revision,commands}});
 state=await commit('alarm',[{kind:'schedule',target:'evt.home-fire.alarm',minute:0},{kind:'advance',minute:0}]);
 const usual=state.receipt;assert.equal(usual.routes[0].primary.exitPortalID,'kitchen-exit');
 state=await commit('block',[{kind:'schedule',target:'evt.home-fire.fire-origin',minute:1},{kind:'advance',minute:1}]);
 const alternate=state.receipt;assert.equal(alternate.routes[0].primary.exitPortalID,'living-exit');
 state=await host.request({op:'practiceBegin',session:state.session,attemptID:'check',variantID:'practice-check-a/0'});
 assert.equal(practiceSource.parse(state.aiState.practiceAttempts[0].source).evaluatorVersion,'dryrun.practice-anchors/2');
 state=await host.request({op:'practiceSubmit',session:state.session,aiState:state.aiState,attemptID:'check',competencyID:'initialResponse',commit:{id:'unsupported-first',actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'unsupported'}]}});
 const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8')),branches=[];
 for(const destination of ['living','kitchen']) {
  const action={id:'move-'+destination,actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'moveTo',target:input.household.people[0].id,value:destination}]};
  const result=await host.request({op:'practiceSubmit',session:state.session,aiState:state.aiState,attemptID:'check',competencyID:'adaptation',commit:action});
  const observed=result.aiState.practiceAttempts[0].observations.at(-1);assert.equal(observed.credit,destination==='living'?1:0);
  const assessment=await host.request({op:'assess',session:result.session,aiState:JSON.parse(JSON.stringify(result.aiState)),rubric});
  assert.equal(assessment.scorecard.practice,destination==='living'?25:0);assert.equal(assessment.scorecard.practiceAssessed,1);
  assert.equal(assessment.scorecard.practiceEvaluatorVersion,'dryrun.practice-anchors/2');
  const replay=await host.request({op:'query',session:JSON.parse(JSON.stringify(result.session))});assert.deepEqual(replay.receipt,result.receipt);
  assert.deepEqual(result.session.initial,input);
  branches.push({destination,action,observation:observed,receipt:result.receipt,scorecard:assessment.scorecard,replayExact:true});
 }
 await writeFile('../../fixtures/ai/practice-adaptation-v2.json',JSON.stringify({synthetic:true,modelCalls:0,evaluatorVersion:'dryrun.practice-anchors/2',usual,alternate,source:state.aiState.practiceAttempts[0].source,branches},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',evaluatorVersion:'dryrun.practice-anchors/2',alternateMovement:1,blockedMovement:0,practiceAssessed:1,replayExact:true,modelCalls:0}));
}finally{host.close();}
