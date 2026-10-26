// Authored synthetic routing inputs only. No recorded provider answers/fixtures.
import {describe,it,expect} from 'vitest';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {GeminiPrimaryFallback,codexFallbackEligible,type CodexRoute} from '../src/provider-fallback.js';
import {GroqClient,ProviderFailure} from '../src/groq.js';
import {CodexFailure} from '../src/codex-errors.js';
import {CodexProvider,type CodexCapabilities} from '../src/codex-provider.js';
import {codexEndpoint,codexRuntimeVersion,type CodexConnection,type RpcMessage} from '../src/codex-runtime.js';
import {configuredProviderConsent,type AgentProvider,type History,type ProviderReply} from '../src/provider.js';
import {createAIRequestHandler,featureTimeoutMs} from '../src/http.js';
import {inputDigest,IntentInterpreter} from '../src/intents.js';
import {configuredProviders} from '../src/provider-routing.js';
import type {Gateway} from '../src/gateway.js';
import type {FeatureRunner} from '../src/features.js';

const reply=(text:string):ProviderReply=>({steps:[],text,calls:[],usage:{}});
const history=():History=>[{type:'user_input',content:[{type:'text',text:JSON.stringify({member:'person-a',storage:'synthetic cold storage'})}]}];
const turn=(h:History=history(),signal=AbortSignal.timeout(20000))=>({history:h,instruction:'Authored synthetic routing exercise',tools:[],signal});
/** Records calls per provider; behaviour is an authored script of throws/replies. */
function scripted(name:string,steps:(()=>Promise<ProviderReply>)[],log:string[]):AgentProvider&{disposed:number}{
 let i=0;const p={providerID:name as any,disposed:0,async turn(){log.push(name);const step=steps[Math.min(i++,steps.length-1)]!;return step();},disposeOperation(){p.disposed++;}};return p;
}
function codexRoute(provider:AgentProvider,extra:Partial<CodexRoute>={}):CodexRoute{return {provider,images:false,research:false,turnMs:20000,fallbackReserveMs:1000,...extra};}
const groqOK=(log:string[])=>new GroqClient('synthetic',undefined,async()=>{log.push('groq');return Response.json({choices:[{message:{content:'{"action":"groq"}'}}]});});
const all=['codex','gemini','groq'];

describe('Codex-primary capability-aware routing',()=>{
 it('serves every consented operation from Codex first without touching Gemini or Groq',async()=>{
  const log:string[]=[];const codex=scripted('codex',[async()=>reply('codex')],log);
  const router=new GeminiPrimaryFallback(scripted('gemini',[async()=>reply('gemini')],log),groqOK(log),45000,codexRoute(codex));
  const scoped=router.scope({signal:AbortSignal.timeout(20000),providers:all,capability:'privateText'});
  expect((await scoped.turn(turn())).text).toBe('codex');
  expect(log).toEqual(['codex']);expect(scoped.attemptProvider).toBe('codex');expect(scoped.attemptGeneration).toBe(0);
  expect(router.providerID).toBe('codex');
 });
 it('falls back Codex→Gemini→Groq once each on availability failures, advancing one generation per switch',async()=>{
  const log:string[]=[];
  const codex=scripted('codex',[async()=>{throw new CodexFailure('unavailable');}],log);
  const gemini=scripted('gemini',[async()=>{throw new Error('provider_overloaded');}],log);
  const router=new GeminiPrimaryFallback(gemini,groqOK(log),45000,codexRoute(codex));
  const scoped=router.scope({signal:AbortSignal.timeout(20000),providers:all,capability:'privateText'});
  const first=await scoped.turn(turn());
  expect(JSON.parse(first.text).action).toBe('groq');expect(log).toEqual(['codex','gemini','groq']);
  expect(scoped.attemptGeneration).toBe(2);expect(scoped.attemptProvider).toBe('groq');expect(codex.disposed).toBe(1);
  // Later turns of the same operation stay on the provider that served; nothing earlier is retried.
  await scoped.turn(turn());expect(log).toEqual(['codex','gemini','groq','groq']);
 });
 it('opens a Codex rate-limit circuit so the next operation goes straight to Gemini',async()=>{
  const log:string[]=[];const codex=scripted('codex',[async()=>{throw new CodexFailure('throttled');}],log);
  const router=new GeminiPrimaryFallback(scripted('gemini',[async()=>reply('gemini')],log),undefined,45000,codexRoute(codex));
  for(let i=0;i<2;i++)expect((await router.scope({signal:AbortSignal.timeout(20000),providers:all,capability:'privateText'}).turn(turn())).text).toBe('gemini');
  expect(log).toEqual(['codex','gemini','gemini']);
 });
 it('never routes outside the explicit consent list and derives a Codex+Gemini default when consent is omitted',async()=>{
  const log:string[]=[];const codex=scripted('codex',[async()=>{throw new CodexFailure('unavailable');}],log);
  const router=new GeminiPrimaryFallback(scripted('gemini',[async()=>{throw new Error('provider_rate_limited');}],log),groqOK(log),45000,codexRoute(codex));
  await expect(router.scope({signal:AbortSignal.timeout(20000),providers:['codex'],capability:'privateText'}).turn(turn())).rejects.toThrow('codex_unavailable');
  expect(log).toEqual(['codex']);log.length=0;
  // Gemini/Groq-only consent never invokes the configured Codex runtime.
  await router.scope({signal:AbortSignal.timeout(20000),providers:['gemini','groq'],capability:'privateText'}).turn(turn());
  expect(log).toEqual(['gemini','groq']);log.length=0;
  // A fresh router: the Gemini rate-limit circuit opened above would (correctly) skip Gemini for a minute.
  const fresh=new GeminiPrimaryFallback(scripted('gemini',[async()=>{throw new Error('provider_rate_limited');}],log),groqOK(log),45000,codexRoute(codex));
  const omitted=configuredProviderConsent(fresh,undefined);expect(omitted).toEqual(['codex','gemini']);
  await expect(fresh.scope({signal:AbortSignal.timeout(20000),providers:omitted,capability:'privateText'}).turn(turn())).rejects.toThrow('provider_rate_limited');
  expect(log).toEqual(['codex','gemini']);
  expect(()=>router.scope({signal:AbortSignal.timeout(20000),providers:[],capability:'privateText'})).toThrow();
 });
 it('starts image work at Gemini when Codex images are unattested, and never sends images to Groq',async()=>{
  const log:string[]=[];const codex=scripted('codex',[async()=>reply('codex')],log);
  const router=new GeminiPrimaryFallback(scripted('gemini',[async()=>reply('gemini')],log),groqOK(log),45000,codexRoute(codex));
  expect((await router.scope({signal:AbortSignal.timeout(20000),providers:all,capability:'image'}).turn(turn())).text).toBe('gemini');
  expect(log).toEqual(['gemini']);
  const attested=new GeminiPrimaryFallback(scripted('gemini',[async()=>reply('gemini')],log),groqOK(log),45000,codexRoute(codex,{images:true}));
  expect((await attested.scope({signal:AbortSignal.timeout(20000),providers:all,capability:'image'}).turn(turn())).text).toBe('codex');
 });
 it('does not switch providers for a model budget failure or a cancelled caller',async()=>{
  for(const failure of [new CodexFailure('execution_budget'),new Error('operation_budget')]){
   const log:string[]=[];const codex=scripted('codex',[async()=>{throw failure;}],log);
   const router=new GeminiPrimaryFallback(scripted('gemini',[async()=>reply('gemini')],log),groqOK(log),45000,codexRoute(codex));
   await expect(router.scope({signal:AbortSignal.timeout(20000),providers:all,capability:'privateText'}).turn(turn())).rejects.toThrow(failure.message);
   expect(log).toEqual(['codex']);
  }
  const log:string[]=[];const caller=new AbortController();
  const codex=scripted('codex',[async()=>{caller.abort();throw new CodexFailure('unavailable');}],log);
  const router=new GeminiPrimaryFallback(scripted('gemini',[async()=>reply('gemini')],log),groqOK(log),45000,codexRoute(codex));
  await expect(router.scope({signal:AbortSignal.timeout(20000),providers:all,capability:'privateText'}).turn(turn(history(),caller.signal))).rejects.toThrow();
  expect(log).toEqual(['codex']);
  expect(codexFallbackEligible(new CodexFailure('cancelled'))).toBe(false);expect(codexFallbackEligible(new Error('request_budget'))).toBe(true);
 });
 it('restarts a mid-operation Codex failure on the next consented provider (Gemini) without Codex tool history',async()=>{
  const log:string[]=[];let codexTurns=0;
  const call={type:'function_call' as const,id:'codex-call-1',name:'read_household_context',arguments:{sections:['family']}};
  const codex=scripted('codex',[async()=>{codexTurns++;return {steps:[call],text:'',calls:[call],usage:{}};},async()=>{throw new CodexFailure('throttled');}],log);
  const router=new GeminiPrimaryFallback(scripted('gemini',[async()=>reply('gemini')],log),groqOK(log),45000,codexRoute(codex));
  const scoped=router.scope({signal:AbortSignal.timeout(20000),providers:all,capability:'privateText'});
  const h=history();const first=await scoped.turn(turn(h));h.push(...first.steps,{type:'function_result',name:call.name,call_id:call.id,result:[{type:'text',text:'{"records":[]}'}]});
  await scoped.turn(turn(h));
  expect(codexTurns).toBe(1);expect(log).toEqual(['codex','codex','gemini']);expect(scoped.attemptGeneration).toBe(1);
 });
 it('bounds a stalled Codex turn, closes its session and leaves the reserve for Gemini',async()=>{
  const log:string[]=[];let aborted=false;
  const codex:AgentProvider={providerID:'codex',scope:options=>({providerID:'codex',async turn(input){log.push('codex');return new Promise((_r,reject)=>{const stop=()=>{aborted=true;reject(new CodexFailure('cancelled'));};AbortSignal.any([options.signal,input.signal]).addEventListener('abort',stop,{once:true});});}}),async turn(){throw new Error('unscoped');}};
  const router=new GeminiPrimaryFallback(scripted('gemini',[async()=>reply('gemini')],log),undefined,45000,codexRoute(codex,{turnMs:1200,fallbackReserveMs:1000}));
  const started=Date.now();
  const scoped=router.scope({signal:AbortSignal.timeout(20000),providers:all,capability:'privateText',timeoutMs:20000});
  expect((await scoped.turn(turn())).text).toBe('gemini');
  expect(aborted).toBe(true);expect(Date.now()-started).toBeLessThan(5000);expect(log).toEqual(['codex','gemini']);
  // Too little time left for Codex plus the reserve: go straight to the fallback.
  log.length=0;const short=router.scope({signal:AbortSignal.timeout(20000),providers:all,capability:'privateText',timeoutMs:1500});
  expect((await short.turn(turn())).text).toBe('gemini');expect(log).toEqual(['gemini']);
 });
 it('shares one call allowance across providers instead of granting each a fresh budget',async()=>{
  const log:string[]=[];const call={type:'function_call' as const,id:'c',name:'read_household_context',arguments:{}};
  const codex=scripted('codex',[async()=>({steps:[call],text:'',calls:[call],usage:{}})],log);
  const router=new GeminiPrimaryFallback(scripted('gemini',[async()=>reply('gemini')],log),groqOK(log),45000,codexRoute(codex));
  const scoped=router.scope({signal:AbortSignal.timeout(20000),providers:all,capability:'privateText',maximumCalls:2});
  await scoped.turn(turn());await scoped.turn(turn());
  await expect(scoped.turn(turn())).rejects.toThrow('operation_budget');expect(log).toEqual(['codex','codex']);
 });
});

describe('Real Codex adapter behind the router',()=>{
 const capabilities:CodexCapabilities={runtimeVersion:codexRuntimeVersion,endpoint:codexEndpoint,model:'synthetic-model',reviewReportID:'report-synthetic-only',streaming:true,tools:true,continuation:true,structuredOutput:true,lifecycle:true,images:false,research:false};
 class Connection implements CodexConnection {
  onMessage=(_m:RpcMessage)=>{};onFailure=()=>{};closed=false;
  async request(method:string){if(method==='thread/start')return {thread:{id:'thread-synthetic'}};if(method==='turn/start')queueMicrotask(()=>this.onMessage({method:'turn/completed',params:{threadId:'thread-synthetic',turn:{status:'failed',error:{codexErrorInfo:'usageLimitExceeded'}}}}));return {};}
  notify(){}respond(){}async close(){this.closed=true;}
 }
 it('turns an upstream Codex usage limit into a Gemini answer and closes the private runtime',async()=>{
  const connection=new Connection();const log:string[]=[];
  const codex=new CodexProvider('synthetic-key',capabilities,async()=>connection);
  const router=new GeminiPrimaryFallback(scripted('gemini',[async()=>reply('gemini')],log),undefined,45000,codexRoute(codex));
  const scoped=router.scope({signal:AbortSignal.timeout(20000),providers:all,capability:'privateText'});
  expect((await scoped.turn(turn())).text).toBe('gemini');expect(connection.closed).toBe(true);expect(scoped.attemptGeneration).toBe(1);
 });
});

describe('Rate-limit classification',()=>{
 const operation=async()=>{const {ProviderOperation}=await import('../src/groq.js');return new ProviderOperation(AbortSignal.timeout(20000),4,1,20000);};
 it('classifies a Groq tokens-per-minute overflow (413 rate_limit_exceeded) as a rate limit, not unsupported',async()=>{
  for(const status of [413,400,429]){
   const client=new GroqClient('synthetic',undefined,async()=>Response.json({error:{code:'rate_limit_exceeded',type:'tokens',message:'Request too large on tokens per minute (TPM)'}},{status}));
   const failure:any=await client.request([{role:'user',content:'synthetic'}],await operation()).catch(e=>e);
   expect(failure).toBeInstanceOf(ProviderFailure);expect(failure.kind).toBe('rate_limit');expect(failure.diagnostic).toBe('rate_limit_exceeded');
  }
  const daily=new GroqClient('synthetic',undefined,async()=>Response.json({error:{code:'rate_limit_exceeded',message:'Rate limit reached on tokens per day (TPD)'}},{status:429}));
  expect((await daily.request([{role:'user',content:'synthetic'}],await operation()).catch((e:any)=>e) as any).kind).toBe('quota_exhausted');
  const unsupported=new GroqClient('synthetic',undefined,async()=>Response.json({error:{code:'model_not_found'}},{status:404}));
  expect((await unsupported.request([{role:'user',content:'synthetic'}],await operation()).catch((e:any)=>e) as any).kind).toBe('unsupported');
 });
 it('surfaces the Groq 413 limit as provider_rate_limit on the wire, which the native client replays',async()=>{
  const groq=new GroqClient('synthetic',undefined,async()=>Response.json({error:{code:'rate_limit_exceeded',type:'tokens'}},{status:413}));
  const router=new GeminiPrimaryFallback({async turn(){throw new Error('provider_rate_limited');}},groq);
  const secret='synthetic-token-'.padEnd(32,'x');
  const server=createServer(createAIRequestHandler({gateway:{} as Gateway,features:{} as FeatureRunner,interpreter:new IntentInterpreter(router),authorize:h=>{if(h!=='Bearer '+secret)throw new Error('unauthorized');return 'owner';}}));
  server.listen(0,'127.0.0.1');await once(server,'listening');const address=server.address();if(!address||typeof address==='string')throw new Error('listen');
  try{
   const binding={sessionID:'s',revision:0,eventSequence:0,contextDigest:'x',householdRevision:0,homeRevision:0};
   const body={contractVersion:'dryrun.ai/1',requestID:'r-413',synthetic:true,providerConsent:['gemini','groq'],submission:{id:'input',text:'Use water.',inputDigest:inputDigest('Use water.'),binding},context:{people:[],rooms:[],portals:[],equipment:[],contacts:[],supplies:[],choices:[]}};
   const response=await fetch(`http://127.0.0.1:${address.port}/v1/intents`,{method:'POST',headers:{Authorization:'Bearer '+secret},body:JSON.stringify(body)});
   const decoded=await response.json() as {status:string;reason:string;diagnostic?:string;preservePriorResult?:boolean};
   expect(decoded.status).toBe('unavailable');expect(decoded.reason).toBe('provider_rate_limit');expect(decoded.diagnostic).toBe('rate_limit_exceeded');expect(decoded.preservePriorResult).toBe(true);
  }finally{server.closeAllConnections();server.close();}
 });
 it('bounds each feature role inside the native request timeout',()=>{
  expect(featureTimeoutMs('resources')).toBeLessThan(70000);expect(featureTimeoutMs('home')).toBeLessThan(70000);
  for(const role of ['preparation','debrief','drillSetup','stress'])expect(featureTimeoutMs(role)).toBeLessThan(95000);
 });
});

describe('Configured routing',()=>{
 const keys={GOOGLE_AI_STUDIO_KEY:'synthetic-gemini',GROQ_API_KEY:'synthetic-groq'};
 it('keeps the Gemini→Groq chain unless Codex is selected, and serves Gemini/Groq loudly if Codex cannot be configured',async()=>{
  const plain=await configuredProviders({...keys});expect(plain.codex).toBeUndefined();expect(plain.provider.providerID).toBe('gemini');
  const lines:string[]=[];
  const missing=await configuredProviders({...keys,DRYRUN_PROVIDER:'codex'},line=>lines.push(line));
  expect(missing.codex).toBeUndefined();expect(missing.provider.providerID).toBe('gemini');expect(lines).toEqual(['codex_unconfigured codex_capability_gate: serving Gemini/Groq only']);
  await expect(configuredProviders({...keys,DRYRUN_PROVIDER:'codex',NODE_ENV:'production'},()=>{})).rejects.toThrow('codex_experimental_not_production');
 });
});
