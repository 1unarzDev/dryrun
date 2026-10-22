import {groqDirectorInstruction,groqDirectorSchema} from './groq-director.js';
import {GroqClient,ProviderFailure,ProviderOperation,QuotaCircuit,hostStructuredValue,type GroqMessage} from './groq.js';
import type {AgentProvider,History,ProviderReply,ProviderScope} from './provider.js';
import {CodexFailure} from './codex-errors.js';
import {primaryAttempt} from './provider-failure.js';
type Turn=Parameters<AgentProvider['turn']>[0];
/** Explicit projection discards provider thought signatures, hidden reasoning and raw continuation blobs. */
export function privateMessages(history:History):GroqMessage[]{
 const result:GroqMessage[]=[];
 for(const step of history){
  if(step.type==='user_input'){
   if(typeof step.content==='string'){result.push({role:'user',content:compactPrivateText(step.content)});continue;}
   if((step.content??[]).some(c=>c.type==='image'))throw new ProviderFailure('unsupported','groq');
   result.push({role:'user',content:(step.content??[]).filter(c=>c.type==='text').map(c=>c.type==='text'?compactPrivateText(c.text):'').join('\n')});
  }else if(step.type==='function_call')result.push({role:'assistant',content:null,tool_calls:[{id:step.id,type:'function',function:{name:step.name,arguments:JSON.stringify(step.arguments)}}]});
  else if(step.type==='function_result')result.push({role:'tool',tool_call_id:step.call_id,content:compactPrivateText(JSON.stringify(step.result))});
  // Prior provider narration is untrusted and not necessary for reconstructing authoritative state.
 }
 return result;
}
export class GroqPrivateProvider implements AgentProvider {
 readonly providerID='groq' as const;
 constructor(private client:GroqClient,private operation:ProviderOperation){}
 async turn(input:Turn):Promise<ProviderReply>{
  input.signal.throwIfAborted();
  const functions=input.toolMode==='none'?[]:input.tools.map(t=>{if(t.type!=='function'||!t.name)throw new ProviderFailure('unsupported','groq');return {type:'function' as const,function:{name:t.name,description:t.description,parameters:t.parameters}};});
  const raw:any=await this.client.request([{role:'system',content:groqDirectorInstruction(input.instruction)},...privateMessages(input.history)],this.operation,{reasoningEffort:'medium',maximumOutputTokens:input.instruction.startsWith('DryRun RehearsalDirector')?(functions.length?2200:3000):3000,signal:input.signal,functions,schema:functions.length?undefined:input.outputSchema?groqDirectorSchema(input.outputSchema,input.history):undefined,toolMode:input.toolMode==='any'?'required':input.toolMode});
  const message=raw?.choices?.[0]?.message;if(!message)throw new ProviderFailure('invalid_output','groq');
  const calls=(message.tool_calls??[]).map((call:any)=>({type:'function_call' as const,id:call.id,name:call.function.name,arguments:JSON.parse(call.function.arguments)}));
  let text=typeof message.content==='string'?message.content:'';if(!functions.length&&input.outputSchema&&text)text=JSON.stringify(hostStructuredValue(JSON.parse(text),input.outputSchema));
  return {steps:calls,text,calls,usage:{provider:'groq',model:this.client.model,operationID:this.operation.id,generation:this.operation.generation,reported:raw.usage}};
 }
}
/** Codex as the capability-aware primary of the one orchestration layer. `images`/`research` are the attested
 * runtime capabilities; a scope needing one Codex lacks starts at Gemini instead. */
export type CodexRoute={provider:AgentProvider;images:boolean;research:boolean;turnMs?:number;fallbackReserveMs?:number};
type RouteID='codex'|'gemini'|'groq';
/** Allowlisted per-hop machine metadata for harness capture: provider, outcome, failure kind/status/code. Never text. */
export type ProviderAttemptEvent={operationID:string;generation:number;provider:RouteID;result:'served'|'failed';kind?:string;status?:number;diagnostic?:string};
function attemptFailure(error:unknown):Pick<ProviderAttemptEvent,'kind'|'status'|'diagnostic'>{
 const machine=(v:unknown)=>typeof v==='string'&&/^[a-zA-Z][a-zA-Z0-9_]{0,47}$/.test(v)?v:undefined;
 if(error instanceof CodexFailure)return {kind:error.kind};
 if(error instanceof ProviderFailure)return {kind:error.kind,status:error.status,diagnostic:machine(error.diagnostic)};
 return {kind:error instanceof Error?machine(error.message)??'error':'error'};
}
/** Codex failure kinds that mean "this provider cannot serve now", not "the operation itself is invalid". A model
 * that exhausts its own tool budget (execution_budget) or a cancelled caller never moves to another provider. */
const codexFallbackKinds=new Set(['throttled','unavailable','deadline','unsupported_capability','invalid_schema','invalid_request']);
export function codexFallbackEligible(error:unknown){return error instanceof CodexFailure?codexFallbackKinds.has(error.kind):error instanceof Error&&error.message==='request_budget';}
/** Use scope once per logical operation, including continuations and bounded output repair.
 * The single provider-routing layer: Codex (when configured and consented) -> Gemini -> Groq, each step only on a
 * provider-availability failure, forward-only, sharing one call/spend/deadline allowance. The host's deterministic
 * or offline path stays with the caller once every consented provider has failed. No layer below retries. */
export class GeminiPrimaryFallback implements AgentProvider {
 readonly providerID:'codex'|'gemini';
 readonly defaultConsent:readonly ('codex'|'gemini')[];
 private circuits=new Map<string,QuotaCircuit>();
 private codexCircuit=new QuotaCircuit();
 /** Optional harness observer (reviewer capture); production leaves it unset. */
 observe?:(event:ProviderAttemptEvent)=>void;
 constructor(private primary:AgentProvider,private groq?:GroqClient,private primaryAttemptMs=45000,private codex?:CodexRoute){
  this.providerID=codex?'codex':'gemini';
  // An omitted consent list keeps the deployment's configured chain; Groq always needs explicit consent.
  this.defaultConsent=codex?['codex','gemini']:['gemini'];
 }
 turn(input:Turn){return this.primary.turn(input);} // Unscoped callers are Gemini-only by default.
 scope(options:ProviderScope):AgentProvider {
  const operation=new ProviderOperation(options.signal,options.maximumCalls??6,0.20,options.timeoutMs??90000);
  operation.maximumSwitches=2;
  const scope=options.capability;
  const groqClient=this.groq,groqAllowed=!!groqClient&&options.providers.includes('groq')&&scope!=='image';
  const codexRoute=this.codex,codexAllowed=!!codexRoute&&options.providers.includes('codex')&&(scope!=='image'||codexRoute.images);
  const chain:RouteID[]=[...(codexAllowed?['codex' as const]:[]),...(options.providers.includes('gemini')?['gemini' as const]:[]),...(groqAllowed?['groq' as const]:[])];
  if(!chain.length)throw new ProviderFailure('unsupported','operation',undefined,undefined,'provider_consent_required');
  const fallback=groqClient?new GroqPrivateProvider(groqClient,operation):undefined;
  let selected:RouteID=chain[0]!;
  // Existing contract: a Groq-only consent is the fallback generation of a Gemini-primary operation.
  if(selected==='groq')operation.switch();
  const codexAbort=new AbortController();
  const codexScoped=codexAllowed&&codexRoute?(codexRoute.provider.scope?codexRoute.provider.scope({...options,signal:AbortSignal.any([options.signal,codexAbort.signal])}):codexRoute.provider):undefined;
  const circuits=this.circuits,codexCircuit=this.codexCircuit,thisPrimary=this.primary,attemptMs=this.primaryAttemptMs;
  const report=(provider:RouteID,result:'served'|'failed',error?:unknown)=>{try{this.observe?.({operationID:operation.id,generation:operation.generation,provider,result,...(error===undefined?{}:attemptFailure(error))});}catch{/* observer never affects routing */}};
  const turnMs=codexRoute?.turnMs??45000,reserveMs=codexRoute?.fallbackReserveMs??25000;
  const after=(current:RouteID,history:History):RouteID|undefined=>{
   const rest=chain.slice(chain.indexOf(current)+1);
   // Gemini rejects another model's function calls without its own thought signatures; Groq's projection does not.
   if(current==='codex'&&history.some(step=>step.type==='function_call')&&rest.includes('groq'))return 'groq';
   return rest[0];
  };
  return {
   async disposeOperation(history){codexAbort.abort();await codexScoped?.disposeOperation?.(history);await thisPrimary.disposeOperation?.(history);},
   get attemptGeneration(){return operation.generation;},get attemptID(){return `${operation.id}:${operation.generation}`;},get attemptProvider(){return selected;},
   async turn(input){
    operation.check();input.signal.throwIfAborted();
    if(selected==='codex'&&codexScoped){
     const next=after('codex',input.history);
     const eligible=codexCircuit.enter(),quotaGeneration=codexCircuit.generation;
     try{
      if(!eligible)throw new CodexFailure('throttled');
      // With a fallback, Codex may use the operation's time only up to a reserve the fallback needs.
      const bound=next?Math.min(turnMs,operation.deadline-Date.now()-reserveMs):operation.deadline-Date.now();
      if(bound<1000)throw new CodexFailure('deadline');
      const generation=operation.generation;operation.reserve(0);
      let timedOut=false;const timer=setTimeout(()=>{timedOut=true;codexAbort.abort();},bound);
      try{
       const result=await codexScoped.turn(input);operation.check(generation);codexCircuit.success(quotaGeneration);report('codex','served');return result;
      }catch(error){if(timedOut&&!input.signal.aborted)throw new CodexFailure('deadline');throw error;}
      finally{clearTimeout(timer);}
     }catch(error){
      report('codex','failed',error);
      if(eligible){if(error instanceof CodexFailure&&error.kind==='throttled')codexCircuit.failure();else codexCircuit.release(quotaGeneration);}
      operation.check();
      if(input.signal.aborted)throw new CodexFailure('cancelled');
      if(!next||!codexFallbackEligible(error))throw error;
      // The abandoned Codex session is closed before any other provider sees the operation.
      codexAbort.abort();await codexScoped.disposeOperation?.(input.history);
      operation.switch();selected=next;
     }
    }
    if(selected==='gemini'){
     const circuitKey=scope+':'+(input.modelRole??'default');let circuit=circuits.get(circuitKey);if(!circuit){circuit=new QuotaCircuit();circuits.set(circuitKey,circuit);}
     const eligible=circuit.enter(),quotaGeneration=circuit.generation;
     try{
      if(!eligible)throw new Error('provider_rate_limited');
      const generation=operation.generation;operation.reserve(0.012);
      const result=await primaryAttempt(AbortSignal.any([input.signal,operation.signal]),groqAllowed?Math.min(attemptMs,Math.max(1,(operation.deadline-Date.now())/2)):operation.deadline-Date.now(),signal=>thisPrimary.turn({...input,signal}));operation.check(generation);circuit.success(quotaGeneration);report('gemini','served');return result;
     }catch(error){
      report('gemini','failed',error);
      const reason=error instanceof Error?error.message:'';
      if(eligible){if(reason==='provider_rate_limited')circuit.failure(error instanceof ProviderFailure?error.retryAfterMs:undefined);else circuit.release(quotaGeneration);}
      operation.check();
      if(input.signal.aborted)throw new ProviderFailure('cancelled','gemini');
      if(!groqAllowed||!['provider_rate_limited','provider_overloaded','provider_model_unavailable','provider_unavailable','provider_timeout_or_cancelled'].includes(reason))throw error;
      operation.switch();selected='groq';
     }
    }
    if(selected!=='groq'||!fallback)throw new ProviderFailure('unsupported','operation',undefined,undefined,'provider_consent_required');
    try{const result=await fallback.turn(input);report('groq','served');return result;}catch(error){report('groq','failed',error);throw error;}
   }
  };
 }
}

/** Omit raw polygons/transforms from text roles: host tools still compute routes and effects.
 * Preserve room/opening IDs, topology, exposure/verification, housing, route dependencies and ALL private care facts. */
export function compactPrivateText(text:string):string {
 try{const parsed=JSON.parse(text);function walk(value:any,key='',scene=false):any {
  if(Array.isArray(value)){
   if(scene&&key==='planningRoutes'){
    // Several household members often share an identical baseline route. Retain
    // every member link and every route fact once, rather than repeating its
    // safety scope/exclusions for each person in a token-limited request.
    const groups=new Map<string,any>();
    for(const route of value){if(!route||typeof route!=='object'||typeof route.personID!=='string')return value.map(v=>walk(v,key,scene));const {personID,...facts}=walk(route,key,scene);const fingerprint=JSON.stringify(facts),prior=groups.get(fingerprint);if(prior)prior.personIDs.push(personID);else groups.set(fingerprint,{...facts,personIDs:[personID]});}
    return [...groups.values()].map(({personIDs,...facts})=>personIDs.length===1?{...facts,personID:personIDs[0]}:{...facts,personIDs});
   }
   return value.map(v=>walk(v,key,scene));
  }
  if(value&&typeof value==='object'){
   if(key==='homeScene'||value.version==='dryrun.home-scene/2')return Object.fromEntries(Object.entries(value).filter(([k])=>!['walls','obstacles','coordinateConvention','sceneBounds'].includes(k)).map(([k,v])=>[k,walk(v,k,true)]));
   return Object.fromEntries(Object.entries(value).filter(([k])=>!(scene&&((['sourceIDs','inputIDs'].includes(k)&&Array.isArray(value[k])&&value[k].length===0)||['polygon','footprint','transform','position','bounds','center','start','end','normal','rotationRadians','translation','a','b'].includes(k)))).map(([k,v])=>[k,walk(v,k,scene)]));
  }return value;
 }return JSON.stringify(walk(parsed));}catch{return text;}
}
