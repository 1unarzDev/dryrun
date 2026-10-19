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
