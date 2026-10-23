// eslint-disable @typescript-eslint/no-explicit-any
import {describe,it,expect} from 'vitest';
import {FeatureRunner} from '../src/features.js';
import {practicePlanRequest,validatePracticePlan,type PracticePlanRequest} from '../src/practice-plan.js';

// Fictional household; candidates are what Core would send.
const context:PracticePlanRequest['context']={contractVersion:'dryrun.practice-plan/1',locale:'en',attemptIndex:2,
 order:['initialResponse','adaptation','communication','continuity'],household:['One adult','Uses a powered communication device'],previousCandidateIDs:[],
 candidates:[
  {id:'initialResponse.home-fire',competency:'initialResponse',hazard:'home-fire',situation:'The smoke alarm sounds at night.',options:[{id:'choose.get-out',action:'Get everyone out now',outcome:'credited'},{id:'choose.fight-fire',action:'Try to put the fire out',outcome:'notCredited'},{id:'choose.find-pet',action:'Look for the pet first',outcome:'notCredited'}]},
  {id:'adaptation.home-fire.a',competency:'adaptation',hazard:'home-fire',situation:'Fire blocks the usual way out.',options:[{id:'move.a.living',action:'Go through the living room',outcome:'credited'},{id:'door.a.d1',action:'Close the bedroom door',outcome:'notAssessed'}]},
  {id:'communication.tornado',competency:'communication',hazard:'tornado',situation:'A tornado watch is issued.',options:[{id:'contact.c1',action:'Call the out-of-area contact',outcome:'credited'},{id:'water.all',action:'Use stored water freely',outcome:'notAssessed'}]},
  {id:'continuity.freeze-power-loss',competency:'continuity',hazard:'freeze-power-loss',situation:'Power is out in a freeze.',options:[{id:'power.d.b',action:'Run the device on the battery station',outcome:'credited'},{id:'power.d.none',action:'Leave the device unpowered',outcome:'notCredited'}]},
 ]};
const good={situations:context.candidates.map((c:any)=>({competency:c.competency,candidateID:c.id,prompt:'What do you do now?',options:c.options.slice(0,2).map((o:any)=>({id:o.id,label:o.action,feedback:'This keeps the plan simple to follow.'}))}))};

describe('practicePlan: one call plans the whole set',()=>{
 it('accepts a complete plan from the candidates and makes exactly one provider call',async()=>{
  let calls=0;let instruction='';let schema:unknown;
  const runner=new FeatureRunner({providerID:'codex',async turn(input){calls++;instruction=input.instruction;schema=input.outputSchema;expect(input.tools).toEqual([]);return {steps:[],calls:[],text:JSON.stringify(good),usage:{}}}});
  const request=practicePlanRequest.parse({contractVersion:'dryrun.ai/1',requestID:'r1',synthetic:true,context});
  const result=await runner.practicePlan(request,AbortSignal.timeout(5000),'owner');
  expect(calls).toBe(1);expect(result.plan.situations).toHaveLength(4);expect(result.servedBy).toBe('codex');
  expect(instruction).toContain('practicePlan');expect(schema).toBeTruthy();
 });
 it('repairs once, then fails so the phone uses its deterministic plan',async()=>{
  let calls=0;
  const runner=new FeatureRunner({async turn(){calls++;return {steps:[],calls:[],text:JSON.stringify({situations:good.situations.map(s=>({...s,candidateID:'invented-'+s.competency}))}),usage:{}}}});
  const request=practicePlanRequest.parse({contractVersion:'dryrun.ai/1',requestID:'r2',synthetic:true,context});
  await expect(runner.practicePlan(request,AbortSignal.timeout(5000))).rejects.toThrow('practice_unknown_candidate');
  expect(calls).toBe(2);
 });
 it.each([
  ['practice_order',(p:any)=>{p.situations.reverse();}],
  ['practice_duplicate_candidate',(p:any)=>{p.situations[1].candidateID=p.situations[0].candidateID;p.situations[1].competency='adaptation';}],
  ['practice_unknown_option',(p:any)=>{p.situations[0].options[1].id='choose.invented';}],
  ['practice_missing_credited',(p:any)=>{p.situations[0].options=(context.candidates as any)[0].options.slice(1,3).map((o:any)=>({id:o.id,label:'x',feedback:'y'}));}],
  ['internal_id',(p:any)=>{p.situations[2].prompt='Call contact-c1 now?';}],
  ['unsupported_assurance',(p:any)=>{p.situations[3].options[0].feedback='Everyone will be safe.';}],
 ])('rejects %s',(code,edit)=>{
  const p=structuredClone(good);edit(p);expect(()=>validatePracticePlan(p,context)).toThrow(code);
 });
 it('rejects non-synthetic, non-English or oversized requests',()=>{
  expect(()=>practicePlanRequest.parse({contractVersion:'dryrun.ai/1',requestID:'r',synthetic:false,context})).toThrow();
  expect(()=>practicePlanRequest.parse({contractVersion:'dryrun.ai/1',requestID:'r',synthetic:true,context:{...context,locale:'es'}})).toThrow();
  expect(()=>validatePracticePlan({situations:good.situations.slice(0,3)},context)).toThrow();
 });
});
