import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
const host=new Host(),cases:any[]=[];
try {
 const common=JSON.parse(await readFile('../../fixtures/ai/six-hazard-mechanics.json','utf8'));
 for(const [scenarioID,kind] of [['flash-flood','leaveEarly'],['freeze-power-loss','heatedAlternative'],['heat-grid-strain','cooledAlternative']]){
  const base=await host.request({op:'initialize',scenarioID});
  let state=await host.request({op:'initialize',input:{...base.session.initial,household:common.household,home:common.home}});
  const profile=state.directorProfiles.find((p:any)=>p.rule==='rule.external.set'||p.id.includes('warning'));assert(profile);
  state=await host.request({op:'commit',session:state.session,commit:{id:'retained-home-event',actor:'director',baseRevision:state.receipt.revision,commands:[{kind:'schedule',target:profile.id,minute:180}]}});
  const destination=state.receipt.experience.feasibleCommands.find((c:any)=>c.kind===kind);assert(destination);
  const departed=await host.request({op:'commit',session:state.session,commit:{id:'actual-departure',actor:'user',baseRevision:state.receipt.revision,commands:[destination]}});
  assert(departed.receipt.experience.relocated);assert(departed.receipt.pending.length);
  const finished=await host.request({op:'fallback',session:departed.session});
  assert(finished.receipt.finished);assert.deepEqual(finished.session.commits.at(-1).commands,[{kind:'finish'}]);
  for(const key of ['snapshot','inventory','experience','pending','routes'])assert.deepEqual(finished.receipt[key],departed.receipt[key],key);
  assert.deepEqual(finished.session.initial,departed.session.initial);
  const restored=await host.request({op:'query',session:JSON.parse(JSON.stringify(finished.session))});assert.deepEqual(restored.receipt,finished.receipt);
  await assert.rejects(host.request({op:'fallback',session:finished.session}),/finished/);
  cases.push({scenarioID,departure:destination,departed,finished});
 }
 for(const scenarioID of ['home-fire','tornado']){
  const base=await host.request({op:'initialize',scenarioID});
  let state=await host.request({op:'initialize',input:{...base.session.initial,household:common.household,home:common.home}});
  for(const person of common.household.people){
   const action=state.receipt.experience.feasibleCommands.find((c:any)=>c.target===person.id&&c.kind===(scenarioID==='home-fire'?'escape':'reachShelter'));assert(action);
   state=await host.request({op:'commit',session:state.session,commit:{id:'actual-arrival-'+person.id,actor:'user',baseRevision:state.receipt.revision,commands:[action]}});
  }
  if(scenarioID==='home-fire'){
   const unfinished=await host.request({op:'fallback',session:state.session});assert(!unfinished.receipt.finished,'escape does not account for people');
   for(const person of common.household.people)state=await host.request({op:'commit',session:state.session,commit:{id:'actual-roster-'+person.id,actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'accountOutside',target:person.id}]}});
  }
  const finished=await host.request({op:'fallback',session:state.session});assert(finished.receipt.finished);
  for(const key of ['snapshot','inventory','experience','pending','routes'])assert.deepEqual(finished.receipt[key],state.receipt[key],key);
  assert.deepEqual(finished.session.initial,state.session.initial);
  const restored=await host.request({op:'query',session:JSON.parse(JSON.stringify(finished.session))});assert.deepEqual(restored.receipt,finished.receipt);
  cases.push({scenarioID,objective:scenarioID==='home-fire'?'all escaped and separately accounted':'all recorded shelter arrivals',beforeFinish:state,finished});
 }
 await writeFile('../../fixtures/ai/departure-fallback.json',JSON.stringify({synthetic:true,liveModelCalls:0,mode:'actual Core host local continuation',cases,native:'pending',humanReview:'pending'},null,2)+'\n');
 console.log(JSON.stringify({passed:true,hazards:5,actualDepartureRequired:true,fireRosterSeparate:true,tornadoEveryArrivalRequired:true,retainedPendingNotApplied:true,timeAndResourcesUnchanged:true,replay:'exact',liveModelCalls:0,native:'pending'}));
}finally{host.close();}
