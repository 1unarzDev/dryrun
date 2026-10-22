import {describe,it,expect} from 'vitest';
import {Gateway,directorPrompt,fixtureAuthorize,validateCommands} from '../src/gateway.js';
import {directorContext} from '../src/contracts.js';
import type {AgentProvider,History} from '../src/provider.js';
const binding={sessionID:'s',revision:1,eventSequence:1,contextDigest:'abc',householdRevision:1,homeRevision:1};
const snapshot={simMinute:0,resources:{'res.water.stored':{amount:5,unit:'gal'}},services:{},unmetRequirements:[],unknowns:[]};
const request={contractVersion:'dryrun.ai/1',requestID:'r',role:'director',synthetic:true,context:{binding,snapshot,profiles:[]}};
class Provider implements AgentProvider { histories:History[]=[];async turn(input:Parameters<AgentProvider['turn']>[0]){this.histories.push(structuredClone(input.history));const call={type:'function_call' as const,id:'call-1',name:'evaluateCandidateAction',arguments:{command:{kind:'advance',minute:20}}};return this.histories.length===1?{steps:[{type:'thought' as const,signature:'opaque-test-signature'},call],text:'',calls:[call],usage:{}}:{steps:[],text:JSON.stringify({commands:[{kind:'advance',minute:20}],purpose:'Examine actual depletion',evidenceIDs:[]}),calls:[],usage:{}};}}
// Synthetic host success used only in gateway protocol tests; actual Core validation has a separate integrated evaluation.
async function acceptSuggestions(gateway:Gateway,result:any,owner='owner'){
 for(let round=0;round<3&&result.status==='needs_client_tools';round++){
  expect(result.calls[0].name).toBe('validateSuggestedActions');
  result=await gateway.resume(owner,{token:result.token,binding,callID:result.calls[0].id,result:{binding,snapshot,contextDigest:binding.contextDigest,suggestionValidation:result.calls[0].arguments.suggestedActions.map((a:any)=>({id:a.id,feasible:true}))}});
 }
 return result;
}
describe('private gateway',()=>{
 it('preserves opaque protocol parts; binds one-time continuation to owner/revision/call',async()=>{const provider=new Provider();const gateway=new Gateway(provider);const start:any=await gateway.start('a',request);expect(start.status).toBe('needs_client_tools');const continuation={token:start.token,binding,callID:'call-1',result:{binding,snapshot,contextDigest:'preview'}};
 await expect(gateway.resume('b',continuation)).rejects.toThrow('invalid_continuation');await expect(gateway.resume('a',{...continuation,callID:'other'})).rejects.toThrow('stale_continuation');expect((await gateway.resume('a',continuation) as any).status).toBe('completed');expect(provider.histories[1]?.some(s=>s.type==='thought'&&s.signature==='opaque-test-signature')).toBe(true);await expect(gateway.resume('a',continuation)).rejects.toThrow('invalid_continuation');await expect(gateway.start('a',request)).rejects.toThrow('replay');});
 it('expires/cancels and rejects unauthorized tool attempts without exposing data',async()=>{let now=0;const gateway=new Gateway(new Provider(),()=>now);const start:any=await gateway.start('a',request);now=100000;await expect(gateway.resume('a',{token:start.token,binding,callID:'call-1',result:{binding,snapshot,contextDigest:'p'}})).rejects.toThrow('invalid_continuation');const other:any=await gateway.start('a',{...request,requestID:'cancel'});gateway.cancel('a',other.token);await expect(gateway.resume('a',{token:other.token,binding,callID:'call-1',result:{binding,snapshot,contextDigest:'p'}})).rejects.toThrow();});
 it('strict minimizers reject names/addresses/listings and model mutation commands',()=>{expect(()=>directorContext.parse({...request.context,phone:'private'})).toThrow();expect(()=>fixtureAuthorize('Bearer '+ 'x'.repeat(24),'x'.repeat(24),true)).toThrow();expect(()=>fixtureAuthorize('Bearer invalid','x'.repeat(24),false)).toThrow();});
 it('forbidden tool and malformed final fail closed with one repair',async()=>{const bad:AgentProvider={async turn(){return {steps:[],text:'secret-looking untrusted text',calls:[],usage:{}};}};const gateway=new Gateway(bad);const result:any=await gateway.start('a',request);expect(result.status).toBe('unavailable');expect(gateway.metrics.calls).toBe(2);expect(JSON.stringify(result)).not.toContain('secret-looking');});
});

it('cancels an in-flight request by ID and never accepts its late reply',async()=>{
 let started!:()=>void;const ready=new Promise<void>(resolve=>{started=resolve});
 const provider:AgentProvider={async turn(input){started();await new Promise<void>(resolve=>input.signal.addEventListener('abort',()=>resolve(),{once:true}));return {steps:[],text:'{}',calls:[],usage:{}};}};
 const gateway=new Gateway(provider);const pending=gateway.start('owner',request);await ready;
 gateway.cancel('owner',request.requestID);expect((await pending as any).status).toBe('unavailable');
});

it('rejects startup without a secret and exhausts budgets before another provider call',async()=>{
 const {GeminiProvider,SpendBudget}=await import('../src/provider.js');expect(()=>new GeminiProvider('')).toThrow('missing_provider_secret');
 const budget=new SpendBudget(0.01);expect(()=>budget.reserve()).toThrow('spend_budget');
 const gateway=new Gateway(new Provider(),()=>0,0);expect((await gateway.start('a',request) as any).status).toBe('unavailable');expect(gateway.metrics.calls).toBe(0);
});

it.each(['inspectScene','queryRoutes','evaluateResources','inspectDependencies','runCounterfactual'])('binds %s results to their tool and still requires an action preview',async(name)=>{
 let turns=0;
 const provider:AgentProvider={async turn(){turns++;const call={type:'function_call' as const,id:'inspect',name,arguments:name==='runCounterfactual'?{profileIDs:['p']}:{}};return turns===1?{steps:[call],text:'',calls:[call],usage:{}}:{steps:[],text:JSON.stringify({commands:[{kind:'requestDecision'}],purpose:'Wait',evidenceIDs:[]}),calls:[],usage:{}};}};
 const gateway=new Gateway(provider);const start:any=await gateway.start('a',{...request,context:{...request.context,profiles:[{id:'p',rule:'reviewed',minute:0}]}});
 expect(start.status).toBe('needs_client_tools');
 const continuation={token:start.token,binding,callID:'inspect',result:{binding,snapshot,contextDigest:'abc'}};
 await expect(gateway.resume('a',continuation)).rejects.toThrow('invalid_tool_result');
 const observation=name==='inspectScene'?{kind:name}:name==='queryRoutes'?{kind:name,routes:[]}:name==='inspectDependencies'?{kind:name,dependencies:[]}:name==='runCounterfactual'?{kind:name,scope:'initial_household_with_selected_profiles',failed:false,criterionID:'water',dependencyIDs:[],baseline:snapshot}:{kind:name};
 // A wrong tool result cannot consume the valid continuation.
 await expect(gateway.resume('a',{...continuation,result:{...continuation.result,observation:{kind:'queryRoutes',routes:[],address:'private'}}})).rejects.toThrow();
 expect((await gateway.resume('a',{...continuation,result:{...continuation.result,observation}}) as any).status).toBe('unavailable');
 expect(turns).toBe(3); // one bounded repair, no inspection-only final proposal
});

it('rejects counterfactual profiles outside the supplied reviewed catalog',async()=>{
 const provider:AgentProvider={async turn(){const call={type:'function_call' as const,id:'x',name:'runCounterfactual',arguments:{profileIDs:['invented']}};return {steps:[call],text:'',calls:[call],usage:{}};}};
 expect((await new Gateway(provider).start('a',request) as any).status).toBe('unavailable');
});

it('limits optional investigations and disables tools after the required preview',async()=>{
 const offered:{names:string[];mode:string|undefined}[]=[];
 const provider:AgentProvider={async turn(input){
  offered.push({names:input.tools.flatMap(t=>t.type==='function'&&t.name?[t.name]:[]),mode:input.toolMode});
  if(offered.length<=3){const preview=offered.length===3;const call={type:'function_call' as const,id:'call-'+offered.length,name:preview?'evaluateCandidateAction':'evaluateResources',arguments:preview?{command:{kind:'advance',minute:20}}:{}};return {steps:[call],text:'',calls:[call],usage:{}};}
  return {steps:[],text:JSON.stringify({commands:[{kind:'advance',minute:20}],purpose:'Use computed consequences',evidenceIDs:[]}),calls:[],usage:{}};
 }};
 const gateway=new Gateway(provider);let result:any=await gateway.start('a',request);
 while(result.status==='needs_client_tools'){
  const call=result.calls[0];const observation=call.name==='evaluateResources'?{kind:call.name}:undefined;
  if(observation)await expect(gateway.resume('a',{token:result.token,binding,callID:call.id,result:{binding,snapshot,contextDigest:'wrong',observation}})).rejects.toThrow('invalid_tool_result');
  result=await gateway.resume('a',{token:result.token,binding,callID:call.id,result:{binding,snapshot,contextDigest:observation?'abc':'preview',...(observation?{observation}:{})}});
 }
 expect(result.status).toBe('completed');expect(offered[2]).toEqual({names:['evaluateCandidateAction'],mode:'any'});expect(offered[3]?.mode).toBe('none');expect(gateway.metrics.calls).toBe(4);
});

const spatialPolicy={version:'dryrun.director-policy/1' as const,permittedHazardFamilies:['homeFire' as const],maximumActiveIncidents:1,schedulingHorizonMinutes:30,eventBudget:4,maximumPendingEvents:2,allowedStageTransitions:[{from:'notStarted',to:'ignition'}]};
const spatialContext=directorContext.parse({...request.context,directorPolicy:spatialPolicy,directorState:{activeIncidentCount:0,scheduledEventCount:0},profiles:[{id:'ignition',rule:'rule.fire.ignition',minute:0,hazard:'homeFire',spatial:true,canStart:true,roomRequired:true}]});
it.each([
 {kind:'startIncident',target:'ignition',value:'invented',hazard:'homeFire',minute:0},
 {kind:'startIncident',target:'ignition',value:'room',hazard:'flashFlood',minute:0},
 {kind:'startIncident',target:'ignition',hazard:'homeFire',minute:0},
 {kind:'schedule',target:'ignition',minute:31},
 {kind:'advanceIncident',target:'ignition',value:'new-origin',hazard:'homeFire',minute:0},
])('rejects unsupported incident context: %j',command=>{expect(()=>validateCommands([command],spatialContext)).toThrow();});
it.each([{}, {command:{kind:'advance',minute:20},commands:[{kind:'advance',minute:20}]}])('rejects ambiguous/empty batch previews before issuing client work',async arguments_=>{
 const provider:AgentProvider={async turn(){const call={type:'function_call' as const,id:'x',name:'evaluateCandidateAction',arguments:arguments_};return {steps:[call],calls:[call],text:'',usage:{}};}};
 expect((await new Gateway(provider).start('a',request) as any).status).toBe('unavailable');
});

it('pairs a malformed tool call with an error result and repairs it once within the existing budget',async()=>{
 let turns=0;let correctedHistory:History=[];
 const provider:AgentProvider={async turn(input){turns++;
  if(turns===2)correctedHistory=structuredClone(input.history);
  if(turns<=2){const call={type:'function_call' as const,id:turns===1?'invalid':'valid',name:'evaluateCandidateAction',arguments:turns===1?{commands:[1,2,3]}:{commands:[{kind:'advance',minute:20}]}};return {steps:[call],calls:[call],text:'',usage:{}};}
  return {steps:[],calls:[],text:JSON.stringify({commands:[{kind:'advance',minute:20}],purpose:'Use the validated host preview',evidenceIDs:[]}),usage:{}};
 }};
 const gateway=new Gateway(provider);const response:any=await gateway.start('a',request);
 expect(response.status).toBe('needs_client_tools');expect(response.calls[0].id).toBe('valid');
 expect(correctedHistory.some(s=>s.type==='function_result'&&s.call_id==='invalid')).toBe(true);
 const final:any=await gateway.resume('a',{token:response.token,binding,callID:'valid',result:{binding,snapshot,contextDigest:'preview'}});
 expect(final.status).toBe('completed');expect(gateway.metrics.calls).toBe(3);
});

it('does not call the provider while the host is waiting for a submitted user action',async()=>{
 const provider=new Provider();const gateway=new Gateway(provider);
 const result:any=await gateway.start('a',{...request,context:{...request.context,directorState:{activeIncidentCount:0,scheduledEventCount:0,awaitingUserAction:true}}});
 expect(result.status).toBe('needs_user_action');expect(provider.histories).toHaveLength(0);expect(gateway.metrics.calls).toBe(0);
 expect(()=>validateCommands([{kind:'requestDecision'},{kind:'finish'}],directorContext.parse(request.context))).toThrow('decision_must_be_last');
});

it('rejects already applied profiles and keeps non-spatial incidents out of spatial commands',()=>{
 const context=directorContext.parse({...request.context,snapshot:{...snapshot,firedEventIDs:['outage']},profiles:[{id:'outage',rule:'rule.external.set',minute:0,spatial:false}]});
 expect(()=>validateCommands([{kind:'schedule',target:'outage',minute:20}],context)).toThrow('duplicate_profile');
 expect(()=>validateCommands([{kind:'startIncident',target:'outage',hazard:'waterOutage',minute:20}],context)).toThrow();
 expect(()=>validateCommands([{kind:'advance',minute:20}],context)).not.toThrow();
});


it('binds recent action ordering and latest action to the current host revision',()=>{
 const action={contractVersion:'dryrun.committed-action-context/1',id:'actual-followup',kind:'useStoredWater',value:'essential',commitRevision:1,commandIndex:0};
 const context={...request.context,lastAction:action,recentActions:[action]};
 expect(directorContext.safeParse(context).success).toBe(true);
 expect(directorContext.safeParse({...context,lastAction:{...action,value:'all'}}).success).toBe(false);
 expect(directorContext.safeParse({...context,recentActions:[{...action,commitRevision:2}]}).success).toBe(false);
 expect(directorContext.safeParse({...context,recentActions:[action,action]}).success).toBe(false);
 expect(directorContext.safeParse({...context,recentActions:[{id:'unbound',kind:'unsupported'}]}).success).toBe(false);
 expect(directorContext.safeParse({...context,lastAction:{...action,phone:'private'}}).success).toBe(false);
});

it('accepts exact supplied committed-event evidence but rejects an invented event',async()=>{
 for(const eventID of ['evt.water-outage.res.food-depleted','invented-food-event']){
  let calls=0;
  const provider:AgentProvider={async turn(){
   if(++calls===1){const call={type:'function_call' as const,id:'food-preview',name:'evaluateCandidateAction',arguments:{command:{kind:'advance',minute:20}}};return {steps:[call],calls:[call],text:'',usage:{}};}
   return {steps:[],calls:[],text:JSON.stringify({commands:[{kind:'advance',minute:20},{kind:'requestDecision'}],purpose:'Review the recorded exercise food coverage.',evidenceIDs:[eventID]}),usage:{}};
  }};
  const context={...request.context,snapshot:{...snapshot,firedEventIDs:['evt.water-outage.res.food-depleted'],resources:{...snapshot.resources,'res.food.days':{amount:0,unit:'day'}}}};
  const gateway=new Gateway(provider),start:any=await gateway.start('food-evidence',{...request,context});
  const result:any=await gateway.resume('food-evidence',{token:start.token,binding,callID:'food-preview',result:{binding,snapshot:context.snapshot,contextDigest:'food-preview'}});
  expect(result.status).toBe(eventID==='invented-food-event'?'unavailable':'completed');
 }
});

it('returns bounded rejected counterfactual observations without treating them as previews',async()=>{
 let calls=0;
 const provider:AgentProvider={async turn(input){calls++;
  if(calls===1){const call={type:'function_call' as const,id:'rejected',name:'runCounterfactual',arguments:{profileIDs:['p']}};return {steps:[call],calls:[call],text:'',usage:{}};}
  const result=input.history.find(s=>s.type==='function_result');expect(result).toBeDefined();
  // No candidate preview followed the unavailable comparison; the final output must fail closed.
  return {steps:[],calls:[],text:JSON.stringify({commands:[{kind:'requestDecision'}],purpose:'Cannot run this comparison.',evidenceIDs:[]}),usage:{}};
 }};
 const gateway=new Gateway(provider);
 const started:any=await gateway.start('owner',{...request,requestID:'rejected-counterfactual',context:{...request.context,profiles:[{id:'p',rule:'r',minute:0}]}});
 const continued:any=await gateway.resume('owner',{token:started.token,binding,callID:'rejected',result:{binding,snapshot,contextDigest:binding.contextDigest,observation:{kind:'runCounterfactual',status:'unavailable',reason:'host_rejected_counterfactual'}}});
 expect(continued.status).toBe('unavailable');expect(calls).toBeLessThanOrEqual(4);
});

it('repairs geometry IDs used as stock IDs before dispatching a hypothetical supply action',async()=>{
 let calls=0;const provider:AgentProvider={async turn(input){calls++;
  if(calls===2)expect(JSON.stringify(input.history)).toContain('invalid_inventory_item');
  const call={type:'function_call' as const,id:'supply-'+calls,name:'runCounterfactual',arguments:{profileIDs:['p'],retestPlan:{version:'dryrun.stress-retest/1',commands:[{kind:'takeSupply',target:calls===1?'an-supplies':'water',value:'person'}]}}};
  return {steps:[call],calls:[call],text:'',usage:{}};
 }};
 const gateway=new Gateway(provider);
 const result:any=await gateway.start('owner',{...request,requestID:'inventory-reference',context:{...request.context,initialInventoryItemIDs:['water'],profiles:[{id:'p',rule:'r',minute:0}]}});
 expect(result.status).toBe('needs_client_tools');expect(calls).toBe(2);
 expect(result.calls[0].arguments.retestPlan.commands[0].target).toBe('water');
 gateway.cancel('owner',result.token);
});

it.each([['water','completed'],['invented-stock','unavailable']])('accepts only supplied initial stock evidence: %s',async(evidence,status)=>{
 let calls=0;const provider:AgentProvider={async turn(){calls++;
  if(calls===1){const call={type:'function_call' as const,id:'p',name:'evaluateCandidateAction',arguments:{command:{kind:'advance',minute:20}}};return {steps:[call],calls:[call],text:'',usage:{}};}
  return {steps:[],calls:[],usage:{},text:JSON.stringify({commands:[{kind:'advance',minute:20}],purpose:'Inspect current consequences.',evidenceIDs:[evidence]})};
 }};
 const gateway=new Gateway(provider);
 const started:any=await gateway.start('owner',{...request,requestID:'stock-evidence',context:{...request.context,initialInventoryItemIDs:['water']}});
 const result:any=await gateway.resume('owner',{token:started.token,binding,callID:'p',result:{binding,snapshot,contextDigest:'preview'}});
 expect(result.status).toBe(status);
});

it('rejects backward advances before host work and repairs a rejected candidate without treating it as a pass',async()=>{
 expect(()=>validateCommands([{kind:'advance',minute:30},{kind:'advance',minute:15}],directorContext.parse(request.context))).toThrow('invalid_time');
 let turns=0;
 const provider:AgentProvider={async turn(input){
  turns++;
  if(turns<=2){const call={type:'function_call' as const,id:'preview-'+turns,name:'evaluateCandidateAction',arguments:{command:{kind:'advance',minute:20}}};return {text:'',steps:[call],calls:[call],usage:{}};}
  expect(JSON.stringify(input.history)).toContain('invalidCommand');
  return {text:JSON.stringify({commands:[{kind:'advance',minute:20}],purpose:'Use the corrected actual preview.',evidenceIDs:['req.preview-only']}),steps:[],calls:[],usage:{}};
 }};
 const gateway=new Gateway(provider);let response:any=await gateway.start('reject-test',request);
 response=await gateway.resume('reject-test',{token:response.token,binding,callID:'preview-1',result:{binding,snapshot,contextDigest:'abc',rejection:{kind:'evaluateCandidateAction',reason:'invalidCommand'}}});
 expect(response.status).toBe('needs_client_tools');
 response=await gateway.resume('reject-test',{token:response.token,binding,callID:'preview-2',result:{binding,snapshot:{...snapshot,unmetRequirements:['req.preview-only']},contextDigest:'valid-preview'}});
 expect(response.status).toBe('completed');expect(turns).toBe(3);
});
it('requires the final state change to match its host preview',async()=>{
 let turns=0;
 const provider:AgentProvider={async turn(){
  if(++turns===1){const call={type:'function_call' as const,id:'bound-preview',name:'evaluateCandidateAction',arguments:{command:{kind:'advance',minute:20}}};return {text:'',calls:[call],steps:[call],usage:{}};}
  return {text:JSON.stringify({commands:[{kind:'advance',minute:30}],purpose:'Different state from the preview.',evidenceIDs:[]}),calls:[],steps:[],usage:{}};
 }};
 const gateway=new Gateway(provider),start:any=await gateway.start('preview-binding',request);
 const result:any=await gateway.resume('preview-binding',{token:start.token,binding,callID:'bound-preview',result:{binding,snapshot,contextDigest:'preview'}});
 expect(result.status).toBe('unavailable');expect(gateway.metrics.outcomes).toContain('invalid_output');
});

it('repairs an omitted advance using the exact accepted preview without committing a new forecast',async()=>{
 let turns=0;
 const provider:AgentProvider={async turn(input){
  turns++;
  if(turns===1){const call={type:'function_call' as const,id:'preview-advance',name:'evaluateCandidateAction',arguments:{commands:[{kind:'advance',minute:20},{kind:'requestDecision'}]}};return {text:'',calls:[call],steps:[call],usage:{}};}
  expect(input.instruction).toContain('"minute":20');
  if(turns===3){expect(JSON.stringify(input.history)).toContain('exact validated preview commands');expect(input.toolMode).toBe('none');}
  return {text:JSON.stringify({commands:turns===2?[{kind:'requestDecision'}]:[{kind:'advance',minute:20},{kind:'requestDecision'}],purpose:'Decide using the actual previewed state.',evidenceIDs:[]}),calls:[],steps:[],usage:{}};
 }};
 const gateway=new Gateway(provider),start:any=await gateway.start('omitted-advance',request);
 const result:any=await gateway.resume('omitted-advance',{token:start.token,binding,callID:'preview-advance',result:{binding,snapshot,contextDigest:'forecast'}});
 expect(result.status).toBe('completed');expect(turns).toBe(3);
 expect(result.proposal.commands[0]).toEqual({kind:'advance',minute:20});
});

it.each(['ct-recorded','heatContinuity','invented-contact'])('validates evidence against exact host affordances and gaps: %s',async(evidence)=>{
 let turns=0;
 const provider:AgentProvider={async turn(){
  if(++turns===1){const call={type:'function_call' as const,id:'current-decision',name:'evaluateCandidateAction',arguments:{command:{kind:'requestDecision'}}};return {text:'',calls:[call],steps:[call],usage:{}};}
  return {text:JSON.stringify({commands:[{kind:'requestDecision'}],purpose:'Review the actual recorded contact or unresolved gap.',evidenceIDs:[evidence]}),calls:[],steps:[],usage:{}};
 }};
 const experience={mechanicsVersion:'dryrun.hazard-mechanics/1',hazard:'freezePowerLoss',scene:'cold-continuity-energy',objective:'Maintain heat continuity',supportedActions:['identifyGap'],feasibleCommands:[{kind:'contact',target:'ct-recorded'}],outsidePersonIDs:[],accountedPersonIDs:[],shelteredPersonIDs:[],destinationIDs:[],occupantRoomIDs:{},relocated:false,openGapIDs:['heatContinuity'],identifiedGapIDs:[],debrief:[]};
 const gateway=new Gateway(provider),start:any=await gateway.start('host-evidence',{...request,context:{...request.context,experience}});
 const result:any=await gateway.resume('host-evidence',{token:start.token,binding,callID:'current-decision',result:{binding,snapshot,contextDigest:'same-state'}});
 expect(result.status).toBe(evidence==='invented-contact'?'unavailable':'completed');
});
it('repairs a retained relocation assurance while preserving its contextual alternative and exact forecast',async()=>{
 let turns=0;
 const provider:AgentProvider={async turn(input){turns++;
  if(turns===1){const call={type:'function_call' as const,id:'p',name:'evaluateCandidateAction',arguments:{command:{kind:'advance',minute:20}}};return {steps:[call],text:'',calls:[call],usage:{}};}
  if(turns===3)expect(JSON.stringify(input.history.at(-1))).toContain('unsupported_safety_assurance');
  return {steps:[],calls:[],usage:{},text:JSON.stringify({commands:[{kind:'advance',minute:20}],purpose:'Compare the recorded cooling alternative with the current home arrangement.',evidenceIDs:[],suggestedActions:[{id:'alternate',label:'Use the recorded cooled alternative',fact:'A destination arrangement is recorded for this exercise.',implication:turns===2?'Moving there provides a stable environment, ensuring comfort and equipment reliability.':'The exercise can compare that arrangement; actual cooling and equipment suitability still require checking.',commands:[{kind:'cooledAlternative',target:'recorded-alternative'}]}]})};
 }};
 const gateway=new Gateway(provider);const started:any=await gateway.start('owner',request);
 let result:any=await gateway.resume('owner',{token:started.token,binding,callID:'p',result:{binding,snapshot,contextDigest:'preview'}});
 result=await acceptSuggestions(gateway,result);
 expect(result.status).toBe('completed');expect(turns).toBe(3);
 expect(result.proposal.commands).toEqual([{kind:'advance',minute:20}]);
 expect(result.proposal.suggestedActions[0].commands).toEqual([{kind:'cooledAlternative',target:'recorded-alternative'}]);
});
it('keeps essential-device disconnection out of recommendations instead of disguising it as a gap check',async()=>{
 const experience={mechanicsVersion:'dryrun.hazard-mechanics/3',hazard:'freezePowerLoss',scene:'cold-continuity-energy',objective:'Review the actual continuity gap',supportedActions:['allocatePower','identifyGap'],feasibleCommands:[{kind:'allocatePower',target:'eq',value:'none'},{kind:'identifyGap',target:'equipment.eq.backup'}],outsidePersonIDs:[],accountedPersonIDs:[],shelteredPersonIDs:[],destinationIDs:[],occupantRoomIDs:{},relocated:false,openGapIDs:['equipment.eq.backup'],identifiedGapIDs:[],debrief:[]};
 const household={revision:1,people:[],pets:[],equipment:[{id:'eq',essential:true,powerRequired:true,documentation:'unknown'}],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[]};
 let turn=0;const provider:AgentProvider={async turn(input){turn++;
  if(turn===1){const call={type:'function_call' as const,id:'p',name:'evaluateCandidateAction',arguments:{command:{kind:'requestDecision'}}};return {steps:[call],calls:[call],text:'',usage:{}};}
  if(turn===3)expect(JSON.stringify(input.history.at(-1))).toContain('unsupported_essential_disconnect');
  return {steps:[],calls:[],usage:{},text:JSON.stringify({commands:[{kind:'requestDecision'}],purpose:'Review the recorded equipment backup unknown.',evidenceIDs:[],suggestedActions:[{id:'gap',label:'Recognize the equipment backup gap',fact:'Compatible backup power is unrecorded.',implication:'The documentation needs checking; this action supplies no power.',commands:turn===2?[{kind:'allocatePower',target:'eq',value:'none'}]:[{kind:'identifyGap',target:'equipment.eq.backup'}]}]})};
 }};
 const gateway=new Gateway(provider);const start:any=await gateway.start('owner',{...request,context:{...request.context,household,experience}});
 let result:any=await gateway.resume('owner',{token:start.token,binding,callID:'p',result:{binding,snapshot,contextDigest:'preview'}});
 result=await acceptSuggestions(gateway,result);
 expect(result.status).toBe('completed');expect(turn).toBe(3);
 expect(result.proposal.suggestedActions[0].commands).toEqual([{kind:'identifyGap',target:'equipment.eq.backup'}]);
});
it('requires remaining outside accounting before the director finishes a fire exercise',async()=>{
 const experience={mechanicsVersion:'dryrun.hazard-mechanics/3',hazard:'homeFire',scene:'smoke-egress-accounting',objective:'Exit and account outside',supportedActions:['escape','accountOutside'],feasibleCommands:[{kind:'accountOutside',target:'p'}],outsidePersonIDs:['p'],accountedPersonIDs:[],shelteredPersonIDs:[],destinationIDs:[],occupantRoomIDs:{p:'exterior'},relocated:false,openGapIDs:[],identifiedGapIDs:[],debrief:[]};
 let turn=0;const provider:AgentProvider={async turn(input){turn++;
  if(turn===1||turn===2){if(turn===2){expect(JSON.stringify(input.history.at(-1))).toContain('unfinished_fire_accounting');expect(input.instruction).not.toContain('FINALIZATION:');}const call={type:'function_call' as const,id:'p',name:'evaluateCandidateAction',arguments:{command:{kind:turn===1?'finish':'requestDecision'}}};return {steps:[call],calls:[call],text:'',usage:{}};}

  return {steps:[],calls:[],usage:{},text:JSON.stringify({commands:[{kind:'requestDecision'}],purpose:'Escape is recorded; outside accounting remains.',evidenceIDs:[],suggestedActions:[{id:'account',label:'Account for the escaped person',fact:'The person is outside but not accounted for.',implication:'Check the outside roster without reentering.',commands:[{kind:'accountOutside',target:'p'}]}]})};
 }};
 const gateway=new Gateway(provider);const start:any=await gateway.start('owner',{...request,context:{...request.context,experience}});
 let result:any=await gateway.resume('owner',{token:start.token,binding,callID:'p',result:{binding,snapshot,contextDigest:'preview'}});
 result=await acceptSuggestions(gateway,result);
 expect(result.status).toBe('completed');expect(turn).toBe(3);expect(result.proposal.commands).toEqual([{kind:'requestDecision'}]);
});
it('rejects a second starting incident in the same proposal before host dispatch',()=>{
 const context=directorContext.parse({...request.context,directorPolicy:{version:'dryrun.director-policy/1',permittedHazardFamilies:['tornado'],maximumActiveIncidents:1,schedulingHorizonMinutes:4320,eventBudget:20,maximumPendingEvents:8,allowedStageTransitions:[]},profiles:[{id:'watch',rule:'reviewed',minute:0,spatial:true,hazard:'tornado',canStart:true,roomRequired:false},{id:'warning',rule:'reviewed',minute:1,spatial:true,hazard:'tornado',canStart:true,roomRequired:false}]});
 expect(()=>validateCommands([{kind:'startIncident',target:'watch',hazard:'tornado',minute:0},{kind:'startIncident',target:'warning',hazard:'tornado',minute:1},{kind:'advance',minute:1}],context)).toThrow('invalid_incident');
 expect(()=>validateCommands([{kind:'startIncident',target:'warning',hazard:'tornado',minute:1},{kind:'advance',minute:1}],context)).not.toThrow();
});
it('repairs a flood escalation that removes early departure before the first household decision',async()=>{
 const experience={mechanicsVersion:'dryrun.hazard-mechanics/3',hazard:'flashFlood',scene:'rising-water-access',objective:'Decide before access is lost',supportedActions:['leaveEarly','identifyGap'],feasibleCommands:[{kind:'leaveEarly',target:'destination'},{kind:'identifyGap',target:'higherRefuge'}],outsidePersonIDs:[],accountedPersonIDs:[],shelteredPersonIDs:[],destinationIDs:['destination'],occupantRoomIDs:{},relocated:false,openGapIDs:['higherRefuge'],identifiedGapIDs:[],debrief:[]};
 const degraded={...experience,feasibleCommands:[{kind:'identifyGap',target:'higherRefuge'}]};
 let turn=0;
 const provider:AgentProvider={async turn(input){turn++;
  if(turn===1||turn===2){if(turn===2){expect(JSON.stringify(input.history.at(-1))).toContain('missed_flood_departure_decision');expect(JSON.stringify(input.outputSchema)).toContain('leaveEarly');expect(input.instruction).not.toContain('FINALIZATION:');}const call={type:'function_call' as const,id:'preview-'+turn,name:'evaluateCandidateAction',arguments:{command:turn===1?{kind:'advance',minute:100}:{kind:'requestDecision'}}};return {steps:[call],calls:[call],text:'',usage:{}};}
  return {steps:[],calls:[],usage:{},text:JSON.stringify({commands:turn===2?[{kind:'advance',minute:100},{kind:'requestDecision'}]:[{kind:'requestDecision'}],purpose:turn===2?'Access is lost; review higher refuge.':'Choose early departure before the access-loss boundary.',evidenceIDs:[],suggestedActions:[{id:'early',label:'Use the recorded destination',fact:'Transport and destination are recorded.',implication:'Compare departure while modeled access remains available.',commands:[{kind:'leaveEarly',target:'destination'}]}]})};
 }};
 const gateway=new Gateway(provider),start:any=await gateway.start('owner',{...request,context:{...request.context,experience}});
 const repair:any=await gateway.resume('owner',{token:start.token,binding,callID:'preview-1',result:{binding,snapshot:{...snapshot,simMinute:100},contextDigest:'preview',preview:{routes:[],experience:degraded}}});
 expect(repair.status).toBe('needs_client_tools');expect(repair.calls[0].arguments.command.kind).toBe('requestDecision');
 let result:any=await gateway.resume('owner',{token:repair.token,binding,callID:'preview-2',result:{binding,snapshot,contextDigest:'preview',preview:{routes:[],experience}}});
 result=await acceptSuggestions(gateway,result);
 expect(result.status).toBe('completed');expect(turn).toBe(3);expect(result.proposal.commands).toEqual([{kind:'requestDecision'}]);
});

it('labels evaluation metadata with the actual instruction version delivered to the provider',async()=>{
 let delivered='';
 const provider:AgentProvider={async turn(input){
  delivered=input.instruction;
  const call={type:'function_call' as const,id:'metadata-preview',name:'evaluateCandidateAction',arguments:{command:{kind:'requestDecision'}}};
  return {steps:[call],calls:[call],text:'',usage:{}};
 }};
 const gateway=new Gateway(provider),result:any=await gateway.start('metadata',request);
 expect(result.status).toBe('needs_client_tools');
 expect(directorPrompt.version).toBe('director/'+delivered.match(/RehearsalDirector prompt\/(\d+)/)?.[1]);
 gateway.cancel('metadata',request.requestID);
});

it('retains the rejected tool reason separately from a subsequent typed Groq quota failure',async()=>{
 const {ProviderFailure}=await import('../src/provider-failure.js');
 let turns=0;
 const context=directorContext.parse({...request.context,directorPolicy:{version:'dryrun.director-policy/1',permittedHazardFamilies:['tornado'],maximumActiveIncidents:1,schedulingHorizonMinutes:4320,eventBudget:20,maximumPendingEvents:8,allowedStageTransitions:[]},profiles:[{id:'warning',rule:'reviewed',minute:0,spatial:true,hazard:'tornado',canStart:true,roomRequired:false}]});
 const provider:AgentProvider={async turn(input){
  if(++turns===1){const call={type:'function_call' as const,id:'unobserved-incident',name:'evaluateCandidateAction',arguments:{commands:[{kind:'startIncident',target:'warning',hazard:'tornado',minute:0},{kind:'requestDecision'}]}};return {steps:[call],calls:[call],text:'',usage:{}};}
  expect(JSON.stringify(input.history.at(-1))).toContain('unapplied_preview');
  throw new ProviderFailure('quota_exhausted','groq',429,3356000,'rate_limit_exceeded');
 }};
 const gateway=new Gateway(provider),result:any=await gateway.start('synthetic',{...request,context});
 expect(result.status).toBe('unavailable');expect(result.calls).toBeUndefined();expect(turns).toBe(2);
 expect(gateway.metrics.validationFailures).toEqual(['tool_arguments:unapplied_preview']);
 expect(gateway.metrics.outcomes).toEqual(['groq_quota_exhausted']);
});

it('binds mandatory whole-suggestion validation to the pending proposal and consumes it only once',async()=>{
 let turns=0;
 const provider:AgentProvider={async turn(){
  if(++turns===1){const call={type:'function_call' as const,id:'p',name:'evaluateCandidateAction',arguments:{command:{kind:'requestDecision'}}};return {steps:[call],calls:[call],text:'',usage:{}};}
  return {steps:[],calls:[],usage:{},text:JSON.stringify({commands:[{kind:'requestDecision'}],purpose:'Observe the actual chosen exercise action.',evidenceIDs:[],suggestedActions:[{id:'a',label:'Recognize the gap',fact:'A gap is unrecorded.',implication:'This acknowledges only the gap.',commands:[{kind:'identifyGap',target:'gap'}]}]})};
 }};
 const gateway=new Gateway(provider),start:any=await gateway.start('owner',request);
 const pending:any=await gateway.resume('owner',{token:start.token,binding,callID:'p',result:{binding,snapshot,contextDigest:'preview'}});
 expect(pending.calls[0].name).toBe('validateSuggestedActions');expect(turns).toBe(2);
 const callback={token:pending.token,binding,callID:pending.calls[0].id,result:{binding,snapshot,contextDigest:binding.contextDigest,suggestionValidation:[{id:'a',feasible:true}]}};
 await expect(gateway.resume('owner',{...callback,result:{...callback.result,suggestionValidation:[{id:'different',feasible:true}]}})).rejects.toThrow('invalid_tool_result');
 await expect(gateway.resume('other',callback)).rejects.toThrow('invalid_continuation');
 expect((await gateway.resume('owner',callback) as any).status).toBe('completed');
 await expect(gateway.resume('owner',callback)).rejects.toThrow('invalid_continuation');expect(turns).toBe(2);
});

it('rejects redundant same-minute advance padding before host preview',()=>{
 expect(()=>validateCommands([{kind:'advance',minute:20},{kind:'advance',minute:20}],directorContext.parse(request.context))).toThrow('redundant_advance');
 expect(()=>validateCommands([{kind:'advance',minute:20},{kind:'advance',minute:21}],directorContext.parse(request.context))).not.toThrow();
});

it.each(['bk-recorded','bk-invented'])('accepts a supplied backup-power subject as evidence without accepting invented IDs: %s',async(id)=>{
 const unknown={origin:'unknown',status:'unknown',sourceIDs:[],inputIDs:[]};
 const household={revision:1,people:[],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[],backupPower:[{id:'bk-recorded',kind:'portableBatteryStation',usableEnergyWh:unknown,continuousOutputW:unknown,setupConfirmed:unknown,islandingConfirmed:unknown,safeOutdoorPlacementConfirmed:unknown,assumedEfficiency:0.85}]};
 let turns=0;
 const provider:AgentProvider={async turn(){
  if(++turns===1){const call={type:'function_call' as const,id:'p',name:'evaluateCandidateAction',arguments:{command:{kind:'requestDecision'}}};return {steps:[call],calls:[call],text:'',usage:{}};}
  return {steps:[],calls:[],usage:{},text:JSON.stringify({commands:[{kind:'requestDecision'}],purpose:'Review the recorded backup specifications; they remain unknown.',evidenceIDs:[id]})};
 }};
 const gateway=new Gateway(provider),start:any=await gateway.start('backup-evidence',{...request,context:{...request.context,household}});
 const result:any=await gateway.resume('backup-evidence',{token:start.token,binding,callID:'p',result:{binding,snapshot,contextDigest:'preview'}});
 expect(result.status).toBe(id==='bk-recorded'?'completed':'unavailable');
 expect(gateway.metrics.validationFailures.includes('invalid_evidence')).toBe(id==='bk-invented');
});

it('scopes final effect fields to the accepted preview while keeping bespoke suggestion reasoning',async()=>{
 let turns=0;let finalSchema:any;
 const provider:AgentProvider={async turn(input){
  if(++turns===1){const call={type:'function_call' as const,id:'exact-preview',name:'evaluateCandidateAction',arguments:{commands:[{kind:'advance',minute:20},{kind:'requestDecision'}]}};return {steps:[call],calls:[call],text:'',usage:{}};}
  finalSchema=input.outputSchema;
  return {steps:[],calls:[],usage:{},text:JSON.stringify({commands:[{kind:'advance',minute:20},{kind:'requestDecision'}],purpose:'Review the actual remaining water balance at this boundary.',evidenceIDs:[]})};
 }};
 const gateway=new Gateway(provider),start:any=await gateway.start('owner',request);
 const result:any=await gateway.resume('owner',{token:start.token,binding,callID:'exact-preview',result:{binding,snapshot:{...snapshot,simMinute:20},contextDigest:'preview'}});
 expect(result.status).toBe('completed');
 const effects=finalSchema.properties.commands.items.anyOf;
 expect(effects.find((s:any)=>s.properties.kind.const==='advance').properties.minute).toMatchObject({const:20});
 expect(effects.map((s:any)=>s.properties.kind.const)).toEqual(['advance','requestDecision','finish']);
 expect(finalSchema.properties.suggestedActions).toBeDefined();
 expect(finalSchema.properties.purpose.type).toBe('string');
});

it('still rejects omitted or changed preview effects instead of silently committing the preview',async()=>{
 let turns=0;
 const provider:AgentProvider={async turn(){
  if(++turns===1){const call={type:'function_call' as const,id:'preview-before-omission',name:'evaluateCandidateAction',arguments:{commands:[{kind:'advance',minute:20},{kind:'requestDecision'}]}};return {steps:[call],calls:[call],text:'',usage:{}};}
  return {steps:[],calls:[],usage:{},text:JSON.stringify({commands:[{kind:'requestDecision'}],purpose:'Review a boundary whose effects were omitted.',evidenceIDs:[]})};
 }};
 const gateway=new Gateway(provider),start:any=await gateway.start('owner',request);
 const result:any=await gateway.resume('owner',{token:start.token,binding,callID:'preview-before-omission',result:{binding,snapshot:{...snapshot,simMinute:20},contextDigest:'preview'}});
 expect(result.status).toBe('unavailable');expect(result.proposal).toBeUndefined();expect(turns).toBe(3);
 expect(gateway.metrics.validationFailures).toEqual(['preview_mismatch','preview_mismatch']);
 expect(gateway.metrics.calls).toBe(3);
});
