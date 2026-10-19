import { GoogleGenAI, type Interactions } from '@google/genai';
export type History = Interactions.Step[];
export type ProviderReply = { steps: History; text: string; calls: Interactions.FunctionCallStep[]; usage: unknown };
export interface AgentProvider { turn(input:{history:History;instruction:string;tools:Interactions.Tool[];toolMode?:'any'|'none'|'auto';modelRole?:'home'|'adjudication';outputSchema?:Record<string,unknown>;signal:AbortSignal}):Promise<ProviderReply> }
export class SpendBudget {
 spentUSD=0;calls=0;
 constructor(readonly limitUSD=Number(process.env.DRYRUN_MAX_USD??0.25)){}
 reserve(upperBoundUSD=0.012){if(!Number.isFinite(this.limitUSD)||this.limitUSD<=0||this.spentUSD+upperBoundUSD>this.limitUSD||this.calls>=80)throw new Error('spend_budget');this.calls++;this.spentUSD+=upperBoundUSD;}
 charge(usage:unknown,model:string,reservedUSD=0){if(!usage||typeof usage!=='object')return;const read=(key:string)=>key in usage&&typeof Reflect.get(usage,key)==='number'?Number(Reflect.get(usage,key)):0;const input=read('total_input_tokens'),output=read('total_output_tokens')+read('total_thought_tokens');const strong=model==='gemini-3.8-flash';this.spentUSD-=reservedUSD;this.spentUSD+=(input*(strong?0.75:0.25)+output*(strong?3.75:1.5))/1000000;}
}
export class GeminiProvider implements AgentProvider {
 private ai:GoogleGenAI;
 private queue:Promise<void>=Promise.resolve();private lastCall=0;
 constructor(key:string,readonly model='gemini-3.1-flash-lite',readonly budget=new SpendBudget(),private roleModels:Partial<Record<'home'|'adjudication',string>>={}){if(!key)throw new Error('missing_provider_secret');if([model,...Object.values(roleModels)].some(id=>!['gemini-3.1-flash-lite','gemini-3.8-flash'].includes(id)))throw new Error('unsupported_model');this.ai=new GoogleGenAI({apiKey:key});}
 async turn(input:{history:History;instruction:string;tools:Interactions.Tool[];toolMode?:'any'|'none'|'auto';modelRole?:'home'|'adjudication';outputSchema?:Record<string,unknown>;signal:AbortSignal}):Promise<ProviderReply>{
 let release!:()=>void;const previous=this.queue;
 const slot=new Promise<void>(resolve=>{release=resolve});
 // Even when this waiter is cancelled, successors still wait for the earlier active call.
 this.queue=previous.then(()=>slot,()=>slot);
 try {
 await waitWithSignal(previous,input.signal);
 const model=(input.modelRole&&this.roleModels[input.modelRole])||this.model;
 const spacing=Number(process.env.DRYRUN_CALL_SPACING_MS??5000);
 const delay=Math.max(0,spacing-(Date.now()-this.lastCall));
 if(delay){let timer:ReturnType<typeof setTimeout>|undefined;try {await waitWithSignal(new Promise<void>(resolve=>{timer=setTimeout(resolve,delay)}),input.signal);}finally{if(timer)clearTimeout(timer)}}
 input.signal.throwIfAborted();
 const requestBytes=Buffer.byteLength(JSON.stringify(input.history)+input.instruction+JSON.stringify(input.outputSchema??{}));
 if(requestBytes>6500000)throw new Error('request_budget');
 // UTF-8 bytes are a conservative text-token bound; image requests reserve an additional fixed allowance.
 const tokenBound=Buffer.byteLength(JSON.stringify(input.history, (key,value)=>key==='data'&&typeof value==='string'?'[image: 8000 token allowance]':value)+input.instruction+JSON.stringify(input.outputSchema??{}))+input.history.filter(s=>s.type==='user_input').reduce((n,s)=>n+(Array.isArray(s.content)?s.content.filter(c=>c.type==='image').length*8000:0),0);
 const upperBoundUSD=(tokenBound*(model==='gemini-3.8-flash'?0.75:0.25)+2400*(model==='gemini-3.8-flash'?3.75:1.5))/1000000;
 this.budget.reserve(upperBoundUSD);this.lastCall=Date.now();
 const response=await this.ai.interactions.create({model,store:false,input:input.history,system_instruction:input.instruction,tools:input.tools,
 response_format:input.outputSchema&&(!input.tools.length||input.history.some(s=>s.type==='function_result'))?{type:'text',mime_type:'application/json',schema:providerSchema(input.outputSchema)}:undefined,generation_config:{max_output_tokens:2400,temperature:0.2,tool_choice:input.tools.length?(input.toolMode??(!input.history.some(s=>s.type==='function_result')?'any':'none')):undefined}},{signal:input.signal});
 this.budget.charge(response.usage,model,upperBoundUSD);
 input.signal.throwIfAborted();
 const steps=response.steps??[];return {steps,text:response.output_text??'',calls:steps.filter(s=>s.type==='function_call'),usage:response.usage};
 }catch(error){const status=typeof error==='object'&&error&&'status'in error?error.status:undefined;if(process.env.DRYRUN_DIAGNOSTICS==='1')console.error('provider error',status,String(error instanceof Error?error.message:error).slice(0,400));throw new Error(status===429?'provider_rate_limited':input.signal.aborted?'provider_timeout_or_cancelled':'provider_unavailable');}finally{release();}
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
function waitWithSignal(promise:Promise<void>,signal:AbortSignal):Promise<void>{
 if(signal.aborted)return Promise.reject(new Error('provider_cancelled'));
 return new Promise<void>((resolve,reject)=>{
  const aborted=()=>{signal.removeEventListener('abort',aborted);reject(new Error('provider_cancelled'));};
  signal.addEventListener('abort',aborted,{once:true});
  promise.then(()=>{signal.removeEventListener('abort',aborted);resolve();},error=>{signal.removeEventListener('abort',aborted);reject(error);});
 });
}
