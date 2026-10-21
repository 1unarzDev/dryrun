import {groqDirectorInstruction,groqDirectorSchema} from './groq-director.js';
import {GroqClient,ProviderFailure,ProviderOperation,QuotaCircuit,hostStructuredValue,type GroqMessage} from './groq.js';
import type {AgentProvider,History,ProviderReply,ProviderScope} from './provider.js';
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
/** Use scope once per logical operation, including continuations and bounded output repair. */
export class GeminiPrimaryFallback implements AgentProvider {
 readonly providerID='gemini' as const;
 private circuits=new Map<string,QuotaCircuit>();
 constructor(private primary:AgentProvider,private groq:GroqClient,private primaryAttemptMs=45000){}
 turn(input:Turn){return this.primary.turn(input);} // Unscoped callers are Gemini-only by default.
 scope(options:ProviderScope):AgentProvider {
  const operation=new ProviderOperation(options.signal,options.maximumCalls??6,0.20,90000);
  const fallback=new GroqPrivateProvider(this.groq,operation);
  const scope=options.capability;let selected:'gemini'|'groq'='gemini';
  if(!options.providers.includes('gemini')){if(!options.providers.includes('groq')||scope==='image')throw new ProviderFailure('unsupported','operation');operation.switch();selected='groq';}
  const circuits=this.circuits,thisPrimary=this.primary,attemptMs=this.primaryAttemptMs;
  return {
   async disposeOperation(history){await thisPrimary.disposeOperation?.(history);},
   get attemptGeneration(){return operation.generation;},get attemptID(){return `${operation.id}:${operation.generation}`;},
   async turn(input){
    operation.check();input.signal.throwIfAborted();
    const circuitKey=scope+':'+(input.modelRole??'default');let circuit=circuits.get(circuitKey);if(!circuit){circuit=new QuotaCircuit();circuits.set(circuitKey,circuit);}
    if(selected==='gemini'){
     const eligible=circuit.enter(),quotaGeneration=circuit.generation;
     try{
      if(!eligible)throw new Error('provider_rate_limited');
      const generation=operation.generation;operation.reserve(0.012);
      const result=await primaryAttempt(AbortSignal.any([input.signal,operation.signal]),options.providers.includes('groq')&&scope!=='image'?Math.min(attemptMs,Math.max(1,(operation.deadline-Date.now())/2)):operation.deadline-Date.now(),signal=>thisPrimary.turn({...input,signal}));operation.check(generation);circuit.success(quotaGeneration);return result;
     }catch(error){
      const reason=error instanceof Error?error.message:'';
      if(eligible){if(reason==='provider_rate_limited')circuit.failure(error instanceof ProviderFailure?error.retryAfterMs:undefined);else circuit.release(quotaGeneration);}
      operation.check();
      if(input.signal.aborted)throw new ProviderFailure('cancelled','gemini');
      if(!options.providers.includes('groq')||scope==='image'||!['provider_rate_limited','provider_overloaded','provider_model_unavailable','provider_unavailable','provider_timeout_or_cancelled'].includes(reason))throw error;
      operation.switch();selected='groq';
     }
    }
    return fallback.turn(input);
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
