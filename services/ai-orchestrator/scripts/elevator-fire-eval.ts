import assert from 'node:assert/strict';
import {readFile,writeFile,access} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {z} from 'zod';
import {Host} from './host.js';
import {GeminiProvider} from '../src/provider.js';
import {outputStyle} from '../src/output-quality.js';
const live=process.env.DRYRUN_LIVE_ELEVATOR==='1';
const path=process.env.DRYRUN_ELEVATOR_OUTPUT??(live?'../../fixtures/ai/elevator-fire-live-'+Date.now()+'.json':'../../fixtures/ai/elevator-fire-host.json');
if(live){try{await access(path);throw new Error('output_already_exists');}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}}
const host=new Host(),provider=live?new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??''):undefined;
const sourcePaths=['scripts/elevator-fire-eval.ts','src/output-quality.ts','../../packages/DryRunCore/Sources/DryRunCore/Spatial/EgressPlanner.swift','../../packages/DryRunCore/Sources/DryRunCore/Spatial/HousingPlanning.swift','../../fixtures/homes/home-sample-apartment-complex.json'];
const sourceHashes=Object.fromEntries(await Promise.all(sourcePaths.map(async p=>[p,createHash('sha256').update(await readFile(p)).digest('hex')])));
const cases:any[]=[],replies:any[]=[];
try{
 const seed=await host.request({op:'initialize',scenarioID:'home-fire'});
 const home=JSON.parse(await readFile('../../fixtures/homes/home-sample-apartment-complex.json','utf8'));
 // Synthetic hypothetical elevators have recorded endpoints at common-area landings. They are always excluded,
 // not new native fixture geometry or an assertion about any actual apartment building.
 const stairs=home.connectors;
 const elevators=stairs.map((c:any,i:number)=>({...c,id:'synthetic-elevator-'+i,kind:'elevator'}));
 for(const variant of ['stairs-and-elevators','elevators-only']){
  const input=structuredClone(seed.session.initial);
  input.home={...structuredClone(home),connectors:variant==='elevators-only'?elevators:[...stairs,...elevators]};
  input.household.housing.homeType='apartment';input.household.housing.floorCount=3;
  input.household.people=[{...input.household.people[0],needs:[],sleepingSpaceID:'sp-bed1',helperPersonID:undefined}];
  let state=await host.request({op:'initialize',input});
  state=await host.request({op:'commit',session:state.session,commit:{id:'synthetic-kitchen-fire',actor:'director',baseRevision:0,commands:[{kind:'startIncident',target:'evt.home-fire.fire-origin',value:'sp-kitchen',hazard:'homeFire',minute:0},{kind:'advance',minute:1}]}});
  const route=state.receipt.routes[0];assert.ok(route);
  assert.equal(Boolean(route.primary),variant==='stairs-and-elevators');
  for(const path of [route.primary,route.alternative].filter(Boolean))assert.ok(path.connectorSequence.every((id:string)=>!id.startsWith('synthetic-elevator')));
  for(const elevator of elevators)assert.ok(route.exclusions.some((e:any)=>e.elementID===elevator.id&&e.reason==='elevatorNotUsedForEgress'));
  const replay=await host.request({op:'query',session:state.session});assert.deepEqual(replay.receipt,state.receipt);assert.deepEqual(state.session.initial,JSON.parse(JSON.stringify(input)));
  const context={household:state.householdContext,homeScene:state.homeScene,committedFire:{minute:state.receipt.snapshot.simMinute,affectedSpaceIDs:state.receipt.snapshot.spatialState?.affectedSpaceIDs},hostRoute:route,instruction:'Explain this exact host result for a fictional apartment fire. Never use an elevator; no supported route stays unresolved. Review building-specific assistance rather than inventing a stair, carry technique or window descent. Feasibility is only under recorded assumptions.'};
  let interpretation:unknown;
  if(provider){
   const schema=z.object({hasSupportedRoute:z.boolean(),elevatorsExcluded:z.literal(true),reason:z.string().min(30).max(600),missingReview:z.string().min(15).max(400)}).strict();
   const reply=await provider.turn({history:[{type:'user_input',content:[{type:'text',text:JSON.stringify(context)}]}],instruction:'DryRun synthetic apartment fire route interpretation. Return structured JSON only. '+outputStyle,tools:[],outputSchema:z.toJSONSchema(schema),signal:AbortSignal.timeout(60000)});
   replies.push({variant,text:reply.text,usage:reply.usage});assert.equal(reply.calls.length,0);
   interpretation=schema.parse(JSON.parse(reply.text));assert.equal((interpretation as z.infer<typeof schema>).hasSupportedRoute,Boolean(route.primary));
  }
  cases.push({variant,source:state.session,context,receipt:state.receipt,interpretation,replayExact:true,sourceUnchanged:true});
 }
 await writeFile(path,JSON.stringify({version:'dryrun.elevator-fire-evaluation/1',synthetic:true,liveModel:live,sourceHashes,calls:provider?.budget.calls??0,budgetAccountedUSD:provider?.budget.spentUSD??0,replies,cases,limitations:['Synthetic graph and exercise; no real building verification','Elevator exclusion is host-owned; model interpretation is not safety certification','Native banner, graphics and posted-procedure/assistance review remain wired-iPhone checks']},null,2)+'\n',live?{flag:'wx'}:undefined);
 console.log(JSON.stringify({passed:true,cases:cases.length,liveModel:live,calls:provider?.budget.calls??0,budgetAccountedUSD:provider?.budget.spentUSD??0}));
}catch(error){await writeFile(path.replace(/\.json$/,'')+'-failure.json',JSON.stringify({synthetic:true,liveModel:live,sourceHashes,cases,replies,calls:provider?.budget.calls??0,failure:error instanceof Error?error.message:'failed'},null,2)+'\n',{flag:'wx'});throw error;}finally{host.close();}
