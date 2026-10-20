import {it,expect} from 'vitest';
import {directorContext} from '../src/contracts.js';
import {directorProviderSchemas} from '../src/director-provider-schema.js';
const base={binding:{sessionID:'s',revision:0,eventSequence:0,contextDigest:'d',householdRevision:1,homeRevision:1},snapshot:{simMinute:0,resources:{},services:{},unmetRequirements:[],unknowns:[]},directorPolicy:{version:'dryrun.director-policy/1',permittedHazardFamilies:['freezePowerLoss'],maximumActiveIncidents:1,schedulingHorizonMinutes:4320,eventBudget:20,maximumPendingEvents:8,allowedStageTransitions:[]},profiles:[{id:'grid-loss',rule:'setExternal',minute:180,spatial:false}]};
it('does not offer spatial operations for an external grid-loss profile',()=>{
 const schemas=directorProviderSchemas(directorContext.parse(base));
 for(const schema of [schemas.preview,schemas.output]){
  const text=JSON.stringify(schema);
  expect(text).toContain('grid-loss');expect(text).toContain('schedule');expect(text).toContain('requestDecision');
  expect(text).not.toContain('advanceIncident');expect(text).not.toContain('startIncident');
 }
 // Free-form model facts/implications and composed user suggestions remain available.
 expect(JSON.stringify(schemas.output)).toContain('suggestedActions');
 expect(JSON.stringify(schemas.output)).toContain('implication');
});
it('does not reoffer an already applied or pending event as a new schedule',()=>{
 for(const context of [{...base,snapshot:{...base.snapshot,firedEventIDs:['grid-loss']}},{...base,pending:[{kind:'schedule',target:'grid-loss',minute:180}]}]){
  const schema=JSON.stringify(directorProviderSchemas(directorContext.parse(context)).preview);
  expect(schema).not.toContain('grid-loss');expect(schema).toContain('advance');
 }
});
it('bounds concept-check targets to unrecognized actual preview gaps while preserving bespoke composed actions',()=>{
 const experience={mechanicsVersion:'dryrun.hazard-mechanics/1',hazard:'waterOutage',scene:'service-advisory-water-use',objective:'Use recorded water for a specific activity',supportedActions:['identifyGap','useWater'],feasibleCommands:[{kind:'useWater',target:'recordedStored',value:'drink',quantityLiters:0.25}],outsidePersonIDs:[],accountedPersonIDs:[],shelteredPersonIDs:[],destinationIDs:[],occupantRoomIDs:{},relocated:false,openGapIDs:['waterQualityOrService'],identifiedGapIDs:[],debrief:[]};
 const context=directorContext.parse({...base,experience});
 const before=JSON.stringify(directorProviderSchemas(context).output);
 expect(before).toContain('identifyGap');expect(before).toContain('waterQualityOrService');
 const after=JSON.stringify(directorProviderSchemas(context,{...context.experience!,identifiedGapIDs:['waterQualityOrService']}).output);
 expect(after).not.toContain('identifyGap');expect(after).not.toContain('pets.waterNeeds');
 expect(after).toContain('useWater');expect(after).toContain('quantityLiters');expect(after).toContain('implication');expect(after).not.toContain('takeSupply');expect(after).not.toContain('accountOutside');
});

it('offers finish-only director effects for an already committed mechanics4 flood departure',()=>{
 const experience={mechanicsVersion:'dryrun.hazard-mechanics/4',hazard:'flashFlood',scene:'rising-water-access',objective:'Debrief actual departure',supportedActions:['leaveEarly','reachHigherRefuge'],feasibleCommands:[],outsidePersonIDs:[],accountedPersonIDs:[],shelteredPersonIDs:[],destinationIDs:['destination'],occupantRoomIDs:{},relocated:true,openGapIDs:[],identifiedGapIDs:[],debrief:[]};
 const schemas=directorProviderSchemas(directorContext.parse({...base,experience}));
 const text=JSON.stringify(schemas.preview);expect(text).toContain('finish');expect(text).not.toContain('schedule');expect(text).not.toContain('requestDecision');
 const finalized=JSON.stringify(directorProviderSchemas(directorContext.parse({...base,experience}),undefined,[{kind:'finish'}]).output);
 expect(finalized).not.toContain('requestDecision');
});

it('omits finish from the provider effect schema while actual fire accounting is outstanding',()=>{
 const experience={mechanicsVersion:'dryrun.hazard-mechanics/4',hazard:'homeFire',scene:'smoke-egress-accounting',objective:'Account outside',supportedActions:['escape','accountOutside'],feasibleCommands:[{kind:'accountOutside',target:'p'}],outsidePersonIDs:['p'],accountedPersonIDs:[],shelteredPersonIDs:[],destinationIDs:[],occupantRoomIDs:{},relocated:false,openGapIDs:[],identifiedGapIDs:[],debrief:[]};
 const context=directorContext.parse({...base,experience});
 const pending=JSON.stringify(directorProviderSchemas(context).preview);
 expect(pending).not.toContain('finish');expect(pending).toContain('requestDecision');
 const accounted=JSON.stringify(directorProviderSchemas({...context,experience:{...context.experience!,accountedPersonIDs:['p']}}).preview);
 expect(accounted).toContain('finish');
});
