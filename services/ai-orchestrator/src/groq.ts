import {randomUUID} from 'node:crypto';
import {defaultGroqExtractorModel} from './provider-capabilities.js';
import {providerSchema} from './provider.js';
import {ProviderFailure,QuotaCircuit,resetDuration,retryDelay} from './provider-failure.js';
export {ProviderFailure,QuotaCircuit,resetDuration,retryDelay} from './provider-failure.js';
export type {FailureKind} from './provider-failure.js';
/** One shared logical-operation allowance: provider switching/extraction never resets it. */
export class ProviderOperation {
 readonly id=randomUUID();generation=0;calls=0;reservedUSD=0;transientRetries=0;outputRepairs=0;readonly deadline:number;
 constructor(readonly signal:AbortSignal,readonly maximumCalls=4,readonly maximumUSD=0.10,timeoutMs=90000,private onReserve?:()=>void){this.deadline=Date.now()+timeoutMs;}
 check(generation=this.generation){this.signal.throwIfAborted();if(Date.now()>=this.deadline)throw new ProviderFailure('timeout','operation');if(generation!==this.generation)throw new Error('stale_provider_attempt');}
 reserve(usd:number){this.check();if(this.calls>=this.maximumCalls||this.reservedUSD+usd>this.maximumUSD)throw new Error('operation_budget');this.onReserve?.();this.calls++;this.reservedUSD+=usd;}
 tryOutputRepair(){this.check();if(this.outputRepairs>=1||this.calls>=this.maximumCalls)return false;this.outputRepairs++;return true;}
 switch(){this.check();if(this.generation!==0)throw new Error('provider_switch_budget');return ++this.generation;}
}
export type GroqSource={id:string;url:string;title:string;content:string;inspection:'search'|'opened'};
export type GroqResearch={answer:string;sources:GroqSource[];searchSteps:number;inspectionSteps:number;usage:unknown};
function safeURL(raw:string){try{const u=new URL(raw);return u.protocol==='https:'&&!u.username&&!u.password?raw:undefined;}catch{return;}}
/** Parse trusted response-envelope tool evidence, NEVER URLs from assistant prose alone. */
export function parseGroqResearch(raw:unknown):GroqResearch {
 const response=raw as any,message=response?.choices?.[0]?.message;
 if(!message||typeof message.content!=='string'||message.content.length>60000)throw new ProviderFailure('invalid_output','groq');
 const sources=new Map<string,GroqSource>();let searchSteps=0,inspectionSteps=0;
 for(const tool of message.executed_tools??[]){
  const search=tool.type==='browser_search'||tool.name==='browser.search';const opened=tool.name==='browser.open'||tool.type==='browser.open';
  if(!search&&!opened)continue;if(search)searchSteps++;else inspectionSteps++;
  for(const item of [...(Array.isArray(tool.search_results?.results)?tool.search_results.results:[]),...(Array.isArray(tool.browser_results)?tool.browser_results:[])]){
   const url=typeof item.url==='string'&&safeURL(item.url);if(!url)continue;
   const content=typeof item.content==='string'?item.content.slice(0,40000):'';
   const old=sources.get(url);if(old&&old.content.length>=content.length){if(opened)old.inspection='opened';continue;}
   sources.set(url,{id:old?.id??`source-${sources.size+1}`,url,title:typeof item.title==='string'?item.title.slice(0,500):'',content,inspection:opened||old?.inspection==='opened'?'opened':'search'});
  }
  // Some responses omit search_results but retain provider-executed URL/line snippets.
  // Parse ONLY that trusted tool-output field, never the final model answer or unresolved markers.
  if(typeof tool.output==='string'){
   const url=tool.output.match(/^L\d+: URL:\s*(?:\nL\d+:\s*)?(https:\/\/[^\s]+)\s*$/m)?.[1];
   if(url&&safeURL(url)&&!url.startsWith('https://exa.ai/search?')&&!sources.has(url))sources.set(url,{id:`source-${sources.size+1}`,url,title:'Provider browser page',content:tool.output.slice(0,40000),inspection:opened?'opened':'search'});
  }
 }
 // No optional envelope evidence? Honest unresolved status; do not infer retrieval from tool_choice.
 // Missing optional tool metadata leaves an attributed answer unresolved. It is
 // neither retrieval proof nor grounds to discard the answer. No sources are
 // reconstructed from assistant-authored links or numeric citation markers.
 return {answer:message.content,sources:[...sources.values()].slice(0,60),searchSteps,inspectionSteps,usage:response.usage};
}
export type GroqMessage={role:'system'|'user'|'assistant'|'tool';content:string|null;tool_calls?:{id:string;type:'function';function:{name:string;arguments:string}}[];tool_call_id?:string};
export type GroqRequestKind='search'|'functions'|'structured'|'text';
export class GroqClient {
 readonly model:string;private circuit=new QuotaCircuit();private tokenWindow?:{remaining:number;resetAt:number};private configurationFailure?:ProviderFailure;
 constructor(private key:string,model=process.env.DRYRUN_GROQ_MODEL??'openai/gpt-oss-120b',private transport:typeof fetch=fetch,private observeSyntheticResponse?:(raw:unknown,kind:GroqRequestKind)=>void){if(!key)throw new ProviderFailure('configuration','groq');if(!['openai/gpt-oss-120b','openai/gpt-oss-20b'].includes(model))throw new ProviderFailure('unsupported','groq');this.model=model;}
 async request(messages:GroqMessage[],operation:ProviderOperation,options:{search?:boolean;schema?:Record<string,unknown>;functions?:{type:'function';function:{name:string;description?:string;parameters?:Record<string,unknown>}}[];toolMode?:'required'|'auto'|'none';signal?:AbortSignal;reasoningEffort?:'low'|'medium'|'high';maximumOutputTokens?:number}={}):Promise<unknown>{
  if((options.search||options.functions?.length)&&options.schema)throw new ProviderFailure('unsupported','groq');
  const generation=operation.generation;operation.check(generation);
  const kind:GroqRequestKind=options.search?'search':options.functions?.length?'functions':options.schema?'structured':'text';
  if(this.configurationFailure)throw this.configurationFailure;
  const bytes=Buffer.byteLength(JSON.stringify(messages));if(bytes>220000)throw new Error('request_budget');
  const known=this.tokenWindow,estimatedTokens=Math.ceil((bytes+JSON.stringify(options.schema??{}).length+JSON.stringify(options.functions??[]).length)/4)+(options.maximumOutputTokens??(options.search?3500:options.functions?.length?1200:2200));
  if(known&&known.remaining<estimatedTokens&&known.resetAt>Date.now()){
   const delay=known.resetAt-Date.now();
   if(delay<=60000&&operation.deadline-Date.now()>delay+8000){await boundedDelay(delay+100,AbortSignal.any([operation.signal,...(options.signal?[options.signal]:[])]));operation.check(generation);}
  }
  // Conservative configured reservation includes unreported internal browsing; not an invoice.
  if(!this.circuit.enter())throw new ProviderFailure('rate_limit','groq',undefined,this.circuit.retryAfterMs(),'model_cooldown');const quotaGeneration=this.circuit.generation;try{operation.reserve(options.search?0.04:0.02);}catch(error){this.circuit.release(quotaGeneration);throw error;}
  const signal=AbortSignal.any([operation.signal,...(options.signal?[options.signal]:[]),AbortSignal.timeout(Math.max(1,operation.deadline-Date.now()))]);
  const body={model:this.model,messages,stream:false,reasoning_effort:options.reasoningEffort??'low',include_reasoning:false,max_completion_tokens:options.maximumOutputTokens??(options.search?3500:options.functions?.length?1200:2200),...(options.search?{tools:[{type:'browser_search'}],tool_choice:'required'}:options.functions?.length?{tools:options.functions,tool_choice:options.toolMode??'auto',parallel_tool_calls:false}:{tool_choice:'none'}),...(options.schema?{response_format:{type:'json_schema',json_schema:{name:'dryrun_result',strict:true,schema:strictGroqSchema(options.schema)}}}:{})};
  try {
   // Native fetch has no automatic retries. Abort fences result acceptance even if transport ignores it.
   const pending=this.transport('https://api.groq.com/openai/v1/chat/completions',{method:'POST',headers:{Authorization:`Bearer ${this.key}`,'Content-Type':'application/json'},body:JSON.stringify(body),signal});
   const response=await abortable(pending,signal);const remaining=response.headers.get('x-ratelimit-remaining-tokens'),reset=resetDuration(response.headers.get('x-ratelimit-reset-tokens'));if(remaining!==null&&Number.isFinite(Number(remaining))&&reset!==undefined)this.tokenWindow={remaining:Number(remaining),resetAt:Date.now()+reset};operation.check(generation);signal.throwIfAborted();
   if(!response.ok){const status=response.status;const detail=await response.json().catch(()=>({})) as any;const knownCodes=['json_validate_failed','output_parse_failed','tool_use_failed','rate_limit_exceeded','insufficient_quota','model_not_found','invalid_api_key','model_decommissioned'];const diagnostic=knownCodes.includes(detail?.error?.code)?String(detail.error.code):undefined;this.observeSyntheticResponse?.({error:{status,code:diagnostic,type:typeof detail?.error?.type==='string'?detail.error.type:undefined,message:typeof detail?.error?.message==='string'?detail.error.message.replace(/org_[a-zA-Z0-9]+/g,'[redacted-org]').slice(0,400):undefined,failedToolNames:typeof detail?.error?.failed_generation==='string'?[...detail.error.failed_generation.matchAll(/<function=([a-zA-Z0-9_]+)/g)].map(m=>m[1]):[]}},kind);const exhausted=status===429&&/per day|quota.*exhaust|insufficient_quota/i.test(String(detail?.error?.message??''));const delay=retryDelay(response.headers);
    // Synthetic development only: status, code and a redacted message, never the request.
    if(status===429)this.circuit.failure(delay);else this.circuit.release(quotaGeneration);
    if(status===429&&!exhausted&&delay!==undefined&&delay<=60000&&operation.transientRetries===0&&operation.deadline-Date.now()>delay+15000){
     operation.transientRetries++;await boundedDelay(delay+1500,signal);
     operation.check(generation);return this.request(messages,operation,options);
    }
    // A supported request can still produce provider-rejected model JSON.
    // Classify the documented machine code, never infer capability from 400 alone.
    // The caller owns its one bounded repair; the adapter does not retry output.
    const invalidGeneratedOutput=status===400&&['json_validate_failed','output_parse_failed'].includes(diagnostic??'');
    const failure=new ProviderFailure(invalidGeneratedOutput?'invalid_output':status===429?(exhausted?'quota_exhausted':'rate_limit'):status===401||status===403?'configuration':status===400||status===404||status===413?'unsupported':'unavailable','groq',status,retryDelay(response.headers),diagnostic);
    // This adapter has immutable credential/model configuration. Retrying an
    // authorization failure cannot repair it; construct a corrected adapter.
    if(status===401||status===403)this.configurationFailure=failure;
    throw failure;}
   const raw=await abortable(response.json(),signal);operation.check(generation);signal.throwIfAborted();
   if((raw as any)?.choices?.[0]?.message?.refusal)throw new ProviderFailure('refusal','groq');
   this.circuit.success(quotaGeneration);this.observeSyntheticResponse?.(withoutReasoning(raw),kind);return raw;
  }catch(error){if(!(error instanceof ProviderFailure&&['rate_limit','quota_exhausted'].includes(error.kind)))this.circuit.release(quotaGeneration);const parentAbort=operation.signal.aborted?operation.signal:options.signal?.aborted?options.signal:undefined;if(parentAbort)throw new ProviderFailure(parentAbort.reason?.name==='TimeoutError'?'timeout':'cancelled','groq');if(signal.aborted)throw new ProviderFailure('timeout','groq');throw error;}
 }
}
/** Same credential/model means the same upstream quota pool. Reuse the client
 * across private direction, browser search and tools-disabled extraction so a
 * reported cooldown/token window cannot be bypassed by changing feature roles.
 * Different models retain independent eligibility. No global secret registry. */
export function configuredGroqClients(key:string,options:{model?:string;extractorModel?:string;transport?:typeof fetch;observeResponse?:(raw:unknown,kind:GroqRequestKind)=>void}={}) {
 const client=new GroqClient(key,options.model,options.transport,options.observeResponse);
 const model=options.extractorModel??defaultGroqExtractorModel;
 const extractor=client.model===model?client:new GroqClient(key,model,options.transport,options.observeResponse);
 return {client,extractor};
}

async function abortable<T>(promise:Promise<T>,signal:AbortSignal):Promise<T>{
 signal.throwIfAborted();return new Promise((resolve,reject)=>{const abort=()=>{signal.removeEventListener('abort',abort);reject(new ProviderFailure('cancelled','groq'));};signal.addEventListener('abort',abort,{once:true});promise.then(v=>{signal.removeEventListener('abort',abort);resolve(v);},e=>{signal.removeEventListener('abort',abort);reject(e);});});
}

/** Groq strict output requires every object property required; optional host fields use transport null. */
export function strictGroqSchema(schema:Record<string,unknown>):Record<string,unknown>{
 const clean=providerSchema(schema);
 function walk(s:any):any {
  if(s.type==='object'||s.properties){const required=new Set(s.required??[]);return {...s,additionalProperties:false,required:Object.keys(s.properties??{}),properties:Object.fromEntries(Object.entries(s.properties??{}).map(([key,value])=>[key,required.has(key)?walk(value):{anyOf:flat([walk(value),{type:'null'}])}]))};}
  if(s.items)return {...s,items:walk(s.items)};
  if(s.anyOf)return {...s,anyOf:flat(s.anyOf.map(walk))};return s;
 }
 // Groq strict mode rejects an anyOf variant that is itself a bare anyOf (an optional union): lift its variants.
 function flat(variants:any[]):any[] {
  // An optional nullable field would otherwise carry two identical null branches, which Groq also rejects.
  const seen=new Set<string>();
  return variants.flatMap(v=>v.anyOf&&Object.keys(v).length===1?flat(v.anyOf):[v]).filter(v=>{const key=JSON.stringify(v);if(seen.has(key))return false;seen.add(key);return true;});
 }
 return walk(clean);
}
export function hostStructuredValue(value:any,schema:any):any {
 const variants=schema.anyOf??schema.oneOf;
 if(variants){const chosen=variants.find((s:any)=>s.properties&&Object.entries(s.properties).some(([key,p]:[string,any])=>p.const!==undefined&&value?.[key]===p.const||p.enum?.includes(value?.[key])));if(chosen)return hostStructuredValue(value,chosen);for(const variant of variants)value=hostStructuredValue(value,variant);return value;}
 if(Array.isArray(value)&&schema.items)return value.map(v=>hostStructuredValue(v,schema.items));
 if(value&&typeof value==='object'&&!Array.isArray(value)&&schema.properties){const result={...value};for(const [key,s] of Object.entries(schema.properties)){if(result[key]===null&&!schema.required?.includes(key))delete result[key];else if(key in result)result[key]=hostStructuredValue(result[key],s);}return result;}
 return value;
}

export function withoutReasoning(value:any):any {if(Array.isArray(value))return value.map(withoutReasoning);if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).filter(([key])=>!['reasoning','reasoning_content','system_fingerprint','x_groq','id'].includes(key)).map(([key,v])=>[key,withoutReasoning(v)]));return value;}

async function boundedDelay(ms:number,signal:AbortSignal){
 let timer:ReturnType<typeof setTimeout>|undefined;
 try{await abortable(new Promise<void>(resolve=>{timer=setTimeout(resolve,ms);}),signal);}finally{if(timer)clearTimeout(timer);}
}
