import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {scene,featureContext} from '../src/features.js';
import {Host} from './host.js';
const host=new Host();
try{
 const seed=await host.request({op:'initialize',sample:'oak',scenarioID:'tornado'});
 const input=structuredClone(seed.session.initial);
 input.home.source='roomPlanScan';input.home.floors[0].exteriorGrade='ground';
 input.home.label='PRIVATE-HOME-CANARY';input.home.spaces[0].label='PRIVATE-ROOM-CANARY';
 input.home.portals[0].note='PRIVATE-OPENING-CANARY';
 input.home.portals[0].emergencyEscapePersonIDs=[input.household.people[0].id];
 const closet=input.home.spaces.find((r:any)=>r.id==='sp-closet');assert.ok(closet);
 const cases:any[]=[];
 for(const kind of ['confirmed','unknownGrade','geometryReview','unconfirmedMarker']){
  const source=structuredClone(input);source.home.revision+=cases.length;
  if(kind==='unknownGrade')source.home.floors[0].exteriorGrade='unknown';
  if(kind==='geometryReview')source.home.spaces.find((r:any)=>r.id===closet.id).geometryNeedsReview=true;
  if(kind==='unconfirmedMarker')source.home.annotations.find((a:any)=>a.kind==='tornadoShelterCandidate').verification='proposed';
  const state=await host.request({op:'initialize',input:source});
  const parsed=scene.parse(state.homeScene);assert.equal(parsed.schemaVersion,'dryrun.home-scene/2');
  if(parsed.schemaVersion!=='dryrun.home-scene/2')throw new Error('wrong_scene_version');
  const room=parsed.rooms.find(r=>r.id===closet.id)!;
  assert.equal(room.confirmedShelter,kind==='confirmed');
  assert.equal(room.interiorNoWindowsConfirmed.value,true);
  assert.equal(room.geometryNeedsReview,kind==='geometryReview');
  assert.deepEqual(parsed.portals[0]!.emergencyEscapePersonIDs,source.home.portals[0].emergencyEscapePersonIDs);
  assert.ok(!JSON.stringify(parsed).includes('PRIVATE-'));
  featureContext.parse({household:state.householdContext,tasks:[],gaps:[],allowedActionIDs:[],allowedCriterionIDs:[],scene:parsed});
  const routeRequest={personID:input.household.people[0].id,startSpaceID:input.household.people[0].sleepingSpaceID,mobility:{requiresStepFree:false,minimumClearWidthMeters:0.7},exclusions:{blockedSpaceIDs:[],blockedPortalIDs:[],blockedConnectorIDs:[]},purpose:'interiorShelter',destinationSpaceID:closet.id};
  const routed=await host.request({op:'query',session:state.session,tool:{kind:'queryRoutes',baseRevision:0,routeRequest}});
  assert.equal(Boolean(routed.tool.route.primary),kind==='confirmed');
  const inspected=await host.request({op:'query',session:state.session,tool:{kind:'inspectScene',baseRevision:0}});
  assert.deepEqual(inspected.tool.scene,parsed);assert.deepEqual(inspected.receipt,state.receipt);
  assert.deepEqual((await host.request({op:'query',session:state.session})).receipt,state.receipt);
  cases.push({kind,source:state.session,scene:parsed,routeRequest,route:routed.tool.route,receipt:state.receipt});
 }
 const historic=JSON.parse(await readFile('../../fixtures/ai/integrated-pipeline-policy.json','utf8')).outputs[0].context.scene;
 assert.equal(scene.parse(historic).schemaVersion,'dryrun.home-scene/1');
 const incomplete=structuredClone(cases[0].scene);delete incomplete.rooms[0].geometryNeedsReview;
 assert.equal(scene.safeParse(incomplete).success,false);
 const injected=structuredClone(cases[0].scene);injected.rooms[0].note='private text';
 assert.equal(scene.safeParse(injected).success,false);
 const unknownVersion={...cases[0].scene,schemaVersion:'dryrun.home-scene/99'};
 assert.equal(scene.safeParse(unknownVersion).success,false);
 await writeFile('../../fixtures/ai/home-scene-v2.json',JSON.stringify({synthetic:true,modelCalls:0,version:'dryrun.home-scene/2',historicalV1Accepted:true,sourcePreserved:true,cases},null,2)+'\n');
 console.log(JSON.stringify({passed:true,synthetic:true,modelCalls:0,cases:cases.length,hostSuitabilityAndRoutesAgree:true,noPrivateLabelsOrNotes:true,readOnly:true,historicalV1Accepted:true,strictVersionAndShape:true}));
}finally{host.close();}
