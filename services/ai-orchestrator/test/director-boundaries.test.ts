import {it,expect} from 'vitest';
import {requireAppliedDueEvents,requireCompletedFireActions,requireDepartureDebrief} from '../src/director-boundaries.js';
it('distinguishes a due water main break from a committed interruption at the same minute',()=>{
 expect(()=>requireAppliedDueEvents([{kind:'schedule',minute:0},{kind:'requestDecision'}],0)).toThrow('unapplied_due_event');
 expect(()=>requireAppliedDueEvents([{kind:'schedule',minute:0},{kind:'advance',minute:0},{kind:'requestDecision'}],0)).not.toThrow();
});
it('preserves future incident composition and checks command ordering instead of merely finding an advance',()=>{
 expect(()=>requireAppliedDueEvents([{kind:'advance',minute:10},{kind:'schedule',minute:10},{kind:'requestDecision'}],0)).toThrow('unapplied_due_event');
 expect(()=>requireAppliedDueEvents([{kind:'schedule',minute:20},{kind:'advance',minute:10},{kind:'requestDecision'}],0)).not.toThrow();
 expect(()=>requireAppliedDueEvents([{kind:'schedule',minute:10},{kind:'schedule',minute:20},{kind:'advance',minute:10},{kind:'requestDecision'}],0)).not.toThrow();
});

it('requires fire escape and outside accounting before finish while leaving other hazard endings alone',()=>{
 const base={hazard:'homeFire',accountedPersonIDs:[],feasibleCommands:[{kind:'escape',target:'p'}]};
 expect(()=>requireCompletedFireActions([{kind:'finish'}],base)).toThrow('unfinished_fire_escape');
 const outside={...base,feasibleCommands:[{kind:'accountOutside',target:'p'}]};
 expect(()=>requireCompletedFireActions([{kind:'finish'}],outside)).toThrow('unfinished_fire_accounting');
 expect(()=>requireCompletedFireActions([{kind:'requestDecision'}],outside)).not.toThrow();
 expect(()=>requireCompletedFireActions([{kind:'finish'}],{...outside,accountedPersonIDs:['p']})).not.toThrow();
 expect(()=>requireCompletedFireActions([{kind:'finish'}],{...outside,hazard:'tornado'})).not.toThrow();
});

it('ends the home flood boundary after actual departure while preserving historical and other hazard continuations',()=>{
 const experience={mechanicsVersion:'dryrun.hazard-mechanics/4',hazard:'flashFlood',relocated:true};
 expect(()=>requireDepartureDebrief([{kind:'finish'}],experience)).not.toThrow();
 for(const commands of [[{kind:'requestDecision'}],[{kind:'advance'},{kind:'finish'}],[{kind:'startIncident'},{kind:'requestDecision'}]])expect(()=>requireDepartureDebrief(commands,experience)).toThrow('departed_flood_requires_debrief');
 expect(()=>requireDepartureDebrief([{kind:'requestDecision'}],{...experience,relocated:false})).not.toThrow();
 expect(()=>requireDepartureDebrief([{kind:'requestDecision'}],{...experience,mechanicsVersion:'dryrun.hazard-mechanics/3'})).not.toThrow();
});

it.each(['freezePowerLoss','heatGridStrain'])('ends actual %s departures for mechanics4/5 without altering historical policy',hazard=>{
 for(const version of [4,5]){
  const experience={mechanicsVersion:`dryrun.hazard-mechanics/${version}`,hazard,relocated:true};
  expect(()=>requireDepartureDebrief([{kind:'finish'}],experience)).not.toThrow();
  for(const commands of [[{kind:'requestDecision'}],[{kind:'advance'},{kind:'finish'}],[{kind:'schedule'},{kind:'finish'}]])expect(()=>requireDepartureDebrief(commands,experience)).toThrow('departed_thermal_requires_debrief');
  expect(()=>requireDepartureDebrief([{kind:'requestDecision'}],{...experience,relocated:false})).not.toThrow();
 }
 expect(()=>requireDepartureDebrief([{kind:'requestDecision'}],{mechanicsVersion:'dryrun.hazard-mechanics/3',hazard,relocated:true})).not.toThrow();
});
