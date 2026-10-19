import {describe,it,expect} from 'vitest';
import {Gateway,fixtureAuthorize} from '../src/gateway.js';
import {directorContext} from '../src/contracts.js';
import type {AgentProvider,History} from '../src/provider.js';
const binding={sessionID:'s',revision:1,eventSequence:1,contextDigest:'abc',householdRevision:1,homeRevision:1};
const snapshot={simMinute:0,resources:{'res.water.stored':{amount:5,unit:'gal'}},services:{},unmetRequirements:[],unknowns:[]};
const request={contractVersion:'dryrun.ai/1',requestID:'r',role:'director',synthetic:true,context:{binding,snapshot,profiles:[]}};
class Provider implements AgentProvider { histories:History[]=[];async turn(input:Parameters<AgentProvider['turn']>[0]){this.histories.push(structuredClone(input.history));const call={type:'function_call' as const,id:'call-1',name:'evaluateCandidateAction',arguments:{command:{kind:'advance',minute:20}}};return this.histories.length===1?{steps:[{type:'thought' as const,signature:'opaque-test-signature'},call],text:'',calls:[call],usage:{}}:{steps:[],text:JSON.stringify({commands:[{kind:'advance',minute:20}],purpose:'Examine actual depletion',evidenceIDs:[]}),calls:[],usage:{}};}}
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
