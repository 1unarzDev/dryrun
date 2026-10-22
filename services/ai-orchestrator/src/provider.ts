import { GoogleGenAI, type Interactions } from '@google/genai';
import {ProviderFailure,QuotaCircuit,geminiFailure} from './provider-failure.js';
export type History = Interactions.Step[];
export type ProviderReply = { steps: History; text: string; calls: Interactions.FunctionCallStep[]; usage: unknown };
export type ProviderID='gemini'|'groq'|'codex';
/** timeoutMs is the caller's whole-operation bound, so one router can leave time for a fallback inside it. */
export type ProviderScope={signal:AbortSignal;providers:readonly string[];capability:'privateText'|'applicationTools'|'image';maximumCalls?:number;timeoutMs?:number};
/** defaultConsent: providers an omitted consent list may use (the deployment's configured chain, never Groq).
 * attemptProvider: which provider served the latest turn of a scoped operation (machine metadata only). */
export interface AgentProvider { readonly providerID?:ProviderID;failover?(history:History):Promise<boolean>;readonly defaultConsent?:readonly ProviderID[];readonly attemptProvider?:ProviderID;disposeOperation?(history:History):void|Promise<void>;scope?(options:ProviderScope):AgentProvider;readonly attemptGeneration?:number;readonly attemptID?:string;turn(input:{history:History;instruction:string;tools:Interactions.Tool[];toolMode?:'any'|'none'|'auto';modelRole?:'home'|'adjudication'|'research';outputSchema?:Record<string,unknown>;signal:AbortSignal}):Promise<ProviderReply> }
/** Allowlisted serving-provider ID for wire responses (servedBy): the provider that served the final turn, or 'host'
 * when the host answered without a model call. Anything else is not reported. */
export type ServedBy='codex'|'gemini'|'groq'|'host';
export function servedProviderID(provider:AgentProvider):Exclude<ServedBy,'host'>|undefined{const id=provider.attemptProvider??provider.providerID;return id==='codex'||id==='gemini'||id==='groq'?id:undefined;}
/** Omitted consent uses the explicitly configured deployment provider; explicit lists never expand. */
export function configuredProviderConsent(provider:AgentProvider,requested?:readonly string[]){return requested??provider.defaultConsent??[provider.providerID??'gemini'];}
export function scopeProvider(provider:AgentProvider,options:ProviderScope):AgentProvider {
 if(provider.scope)return provider.scope(options);
 if(provider.providerID&&!options.providers.includes(provider.providerID))throw new ProviderFailure('unsupported',provider.providerID,undefined,undefined,'provider_consent_required');
 return provider;
}
const modernModels=['gemini-3.1-flash-lite','gemini-3.8-flash'];
/** Legacy research is opt-in: Google restricts 2.5 availability to previously active users. */
const researchModels=[...modernModels,'gemini-2.5-flash'];
function tokenRates(model:string){return model==='gemini-3.8-flash'?{input:0.75,output:3.75}:model==='gemini-2.5-flash'?{input:0.30,output:2.50}:{input:0.25,output:1.5};}
export class SpendBudget {
 spentUSD=0;calls=0;
 private windowStarted:number;private epoch=0;private now:()=>number;private windowMs:number;
 constructor(readonly limitUSD=Number(process.env.DRYRUN_MAX_USD??0.25),options:{now?:()=>number;windowMs?:number}={}){this.now=options.now??Date.now;this.windowMs=options.windowMs??600_000;this.windowStarted=this.now();}
 reserve(upperBoundUSD=0.012){if(this.now()-this.windowStarted>=this.windowMs){this.windowStarted=this.now();this.epoch++;this.spentUSD=0;this.calls=0;}if(!Number.isFinite(this.limitUSD)||this.limitUSD<=0||this.spentUSD+upperBoundUSD>this.limitUSD||this.calls>=80)throw new Error('spend_budget');this.calls++;this.spentUSD+=upperBoundUSD;return this.epoch;}
 charge(usage:unknown,model:string,reservedUSD=0,reservationEpoch=this.epoch){if(reservationEpoch!==this.epoch||!usage||typeof usage!=='object')return;const read=(key:string)=>key in usage&&typeof Reflect.get(usage,key)==='number'?Number(Reflect.get(usage,key)):0;const input=read('total_input_tokens'),output=read('total_output_tokens')+read('total_thought_tokens');const rates=tokenRates(model);this.spentUSD-=reservedUSD;this.spentUSD+=(input*rates.input+output*rates.output)/1000000;}
}
export class GeminiProvider implements AgentProvider {
 readonly providerID='gemini' as const;
 private ai:GoogleGenAI;
 private queue:Promise<void>=Promise.resolve();private lastCall=0;
 private circuits=new Map<string,QuotaCircuit>();
 constructor(key:string,readonly model='gemini-3.1-flash-lite',readonly budget=new SpendBudget(),private roleModels:Partial<Record<'home'|'adjudication'|'research',string>>={}){if(!key)throw new Error('missing_provider_secret');if(!modernModels.includes(model)||Object.entries(roleModels).some(([role,id])=>!(role==='research'?researchModels:modernModels).includes(id)))throw new Error('unsupported_model');this.ai=new GoogleGenAI({apiKey:key});}
 async turn(input:{history:History;instruction:string;tools:Interactions.Tool[];toolMode?:'any'|'none'|'auto';modelRole?:'home'|'adjudication'|'research';outputSchema?:Record<string,unknown>;signal:AbortSignal}):Promise<ProviderReply>{
 let release!:()=>void;const previous=this.queue;
 const slot=new Promise<void>(resolve=>{release=resolve});
 // Even when this waiter is cancelled, successors still wait for the earlier active call.
 this.queue=previous.then(()=>slot,()=>slot);
 const model=(input.modelRole&&this.roleModels[input.modelRole])||this.model;
 let circuit=this.circuits.get(model);if(!circuit){circuit=new QuotaCircuit();this.circuits.set(model,circuit);}
 let entered=false;
 try {
 await waitWithSignal(previous,input.signal);
 if(!circuit.enter())throw new ProviderFailure('rate_limit','gemini',429,undefined,'CIRCUIT_OPEN','provider_rate_limited');entered=true;
 const spacing=Number(process.env.DRYRUN_CALL_SPACING_MS??5000);
 const delay=Math.max(0,spacing-(Date.now()-this.lastCall));
 if(delay){let timer:ReturnType<typeof setTimeout>|undefined;try {await waitWithSignal(new Promise<void>(resolve=>{timer=setTimeout(resolve,delay)}),input.signal);}finally{if(timer)clearTimeout(timer)}}
 input.signal.throwIfAborted();
 const requestBytes=Buffer.byteLength(JSON.stringify(input.history)+input.instruction+JSON.stringify(input.outputSchema??{}));
 if(requestBytes>6500000)throw new Error('request_budget');
 // UTF-8 bytes are a conservative text-token bound; image requests reserve an additional fixed allowance.
 const tokenBound=Buffer.byteLength(JSON.stringify(input.history, (key,value)=>key==='data'&&typeof value==='string'?'[image: 8000 token allowance]':value)+input.instruction+JSON.stringify(input.outputSchema??{}))+input.history.filter(s=>s.type==='user_input').reduce((n,s)=>n+(Array.isArray(s.content)?s.content.filter(c=>c.type==='image').length*8000:0),0);
 const rates=tokenRates(model);
 const upperBoundUSD=(tokenBound*rates.input+6000*rates.output)/1000000;
 const reservationEpoch=this.budget.reserve(upperBoundUSD);this.lastCall=Date.now();
 const request=this.ai.interactions.create({model,store:false,input:input.history,system_instruction:input.instruction,tools:input.tools,
 response_format:input.outputSchema&&(!input.tools.length||input.history.some(s=>s.type==='function_result'))?{type:'text',mime_type:'application/json',schema:providerSchema(input.outputSchema)}:undefined,generation_config:{max_output_tokens:6000,thinking_level:model==='gemini-2.5-flash'?undefined:'high',tool_choice:input.tools.length?(input.toolMode??(!input.history.some(s=>s.type==='function_result')?'any':'none')):undefined}},{signal:input.signal,retries:{strategy:'none'}});
 // Enforce our deadline even if an SDK/network path does not promptly honor abort.
 // Keep the reservation for an unknown outcome; reconcile exactly once if usage arrives later.
 const accounted=request.then(response=>{this.budget.charge(response.usage,model,upperBoundUSD,reservationEpoch);return response;});
 const response=await waitWithSignal(accounted,input.signal);
 input.signal.throwIfAborted();
 circuit.success();
 const steps=response.steps??[];return {steps,text:response.output_text??'',calls:steps.filter(s=>s.type==='function_call'),usage:response.usage};
 }catch(error){
 const failure=error instanceof ProviderFailure?error:geminiFailure(error,input.signal);
 if(entered){if(['rate_limit','quota_exhausted'].includes(failure.kind))circuit.failure(failure.retryAfterMs);else circuit.release();}
 if(error instanceof Error&&['spend_budget','request_budget'].includes(error.message))throw error;
 throw failure;
 }finally{release();}
 }
}

/** Provider schema subset. Full bounds/reference checks remain in host-side Zod schemas. */
export function providerSchema(value:Record<string,unknown>):Record<string,unknown>{
 const result:Record<string,unknown>={};
 for(const [key,v] of Object.entries(value)){
  if(['type','enum','required','additionalProperties','description'].includes(key))result[key]=v;
  else if(key==='const')result.enum=[v];
  else if(key==='properties'&&v&&typeof v==='object')result.properties=Object.fromEntries(Object.entries(v).map(([k,x])=>[k,providerSchema(x as Record<string,unknown>)]));
  else if(key==='items'&&v&&typeof v==='object')result.items=providerSchema(v as Record<string,unknown>);
  else if(key==='prefixItems')result.items={type:'number'};
  else if((key==='anyOf'||key==='oneOf')&&Array.isArray(v))result.anyOf=v.map(x=>providerSchema(x));
 }
 return result;
}


/** Abort only this wait; the underlying call retains its own signal and queue position. */
function waitWithSignal<T>(promise:Promise<T>,signal:AbortSignal):Promise<T>{
 if(signal.aborted)return Promise.reject(new Error('provider_cancelled'));
 return new Promise<T>((resolve,reject)=>{
  const aborted=()=>{signal.removeEventListener('abort',aborted);reject(new Error('provider_cancelled'));};
  signal.addEventListener('abort',aborted,{once:true});
  promise.then(value=>{signal.removeEventListener('abort',aborted);resolve(value);},error=>{signal.removeEventListener('abort',aborted);reject(error);});
 });
}
