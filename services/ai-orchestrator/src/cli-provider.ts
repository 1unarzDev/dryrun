import {spawn} from 'node:child_process';
import {mkdtemp,readFile,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import type {AgentProvider,History,ProviderReply} from './provider.js';
import {ProviderFailure} from './provider-failure.js';
import {providerSchema} from './provider.js';
import {hostStructuredValue,strictGroqSchema} from './groq.js';

/**
 * Beacon through the owner's own subscription CLIs on this Mac (development and the filmed demo only):
 * `claude -p` (Claude Pro/Max login) or `codex exec` (ChatGPT login). Schema-constrained JSON, no tools: it serves the
 * tool-free feature roles (preparation, debrief). The rehearsal director needs function calls validated on the phone,
 * which these CLIs do not expose, so it stays on Gemini. Requests stay synthetic-only, as for every provider.
 * A subscription is for the owner's own use; a deployed product needs an API key instead.
 */
export type CliKind='claude'|'codex';

export class SubscriptionCliProvider implements AgentProvider {
 constructor(readonly kind:CliKind,private model=process.env.DRYRUN_CLI_MODEL??(kind==='claude'?'sonnet':undefined),private timeoutMs=Number(process.env.DRYRUN_CLI_TIMEOUT_MS??90000)){}

 async turn(input:Parameters<AgentProvider['turn']>[0]):Promise<ProviderReply>{
  // Historical local-subscription path is not a service auth profile. The LB
  // integration uses isolated codex-runtime.ts; never silently read owner login.
  if(process.env.DRYRUN_ALLOW_OWNER_SUBSCRIPTION_CLI!=='1'||process.env.NODE_ENV==='production')throw new ProviderFailure('unsupported',this.kind);
  if(input.tools.length&&input.toolMode!=='none')throw new ProviderFailure('unsupported',this.kind);
  if(!input.outputSchema)throw new ProviderFailure('unsupported',this.kind);
  input.signal.throwIfAborted();
  const prompt=transcript(input.history);
  // An empty working directory: no project instructions, settings or files are visible to the CLI.
  const dir=await mkdtemp(join(tmpdir(),'dryrun-beacon-'));
  try{
   const text=this.kind==='claude'?await this.claude(dir,input.instruction,prompt,input.outputSchema,input.signal):await this.codex(dir,input.instruction,prompt,input.outputSchema,input.signal);
   return {steps:[...input.history,{type:'model_output',content:[{type:'text',text}]} as unknown as History[number]],text,calls:[],usage:{provider:this.kind}};
  }finally{await rm(dir,{recursive:true,force:true});}
 }

 private async claude(cwd:string,instruction:string,prompt:string,schema:Record<string,unknown>,signal:AbortSignal){
  // The provider subset (no $schema/$ref keywords); full Zod bounds and references are still checked afterwards.
  const args=['-p','--output-format','json','--json-schema',JSON.stringify(providerSchema(schema)),'--tools','','--no-session-persistence','--strict-mcp-config','--system-prompt',instruction];
  if(this.model)args.push('--model',this.model);
  const out=await run('claude',args,prompt,cwd,signal,this.timeoutMs,this.kind);
  let parsed:any;try{parsed=JSON.parse(out);}catch{throw new ProviderFailure('invalid_output','claude');}
  if(parsed.is_error||parsed.subtype!=='success'){
   const status=typeof parsed.api_error_status==='number'?parsed.api_error_status:undefined;
   throw new ProviderFailure(status===429?'rate_limit':'unavailable','claude',status);
  }
  if(parsed.structured_output===undefined)throw new ProviderFailure('invalid_output','claude');
  return JSON.stringify(parsed.structured_output);
 }

 private async codex(cwd:string,instruction:string,prompt:string,schema:Record<string,unknown>,signal:AbortSignal){
  const schemaFile=join(cwd,'schema.json'),answerFile=join(cwd,'answer.json');
  // OpenAI structured outputs need every property required (optional ones nullable), as for Groq; nulls are mapped back.
  const clean=providerSchema(schema);
  await writeFile(schemaFile,JSON.stringify(strictGroqSchema(schema)));
  const args=['exec','--skip-git-repo-check','--ephemeral','-s','read-only','-C',cwd,'--output-schema',schemaFile,'-o',answerFile];
  if(this.model)args.push('-m',this.model);
  args.push('-');
  await run('codex',args,`${instruction}\n\n${prompt}`,cwd,signal,this.timeoutMs,this.kind);
  const text=(await readFile(answerFile,'utf8').catch(()=>'')).trim();
  let value:unknown;try{value=JSON.parse(text);}catch{throw new ProviderFailure('invalid_output','codex');}
  return JSON.stringify(hostStructuredValue(value,clean));
 }
}

/** The feature runner's history as plain text: the context JSON, then any earlier answer and the host's repair note. */
function transcript(history:History):string{
 return history.map(step=>{
  const s=step as any,parts=(s.content??[]).filter((c:any)=>c?.type==='text').map((c:any)=>c.text).join('\n');
  return s.type==='model_output'?`Your previous answer:\n${parts}`:parts;
 }).filter(Boolean).join('\n\n');
}

function run(command:string,args:string[],stdin:string,cwd:string,signal:AbortSignal,timeoutMs:number,kind:CliKind):Promise<string>{
 return new Promise((resolve,reject)=>{
  const child=spawn(command,args,{cwd,stdio:['pipe','pipe','pipe'],env:{...process.env,NO_COLOR:'1'}});
  let out='',settled=false;
  const finish=(error?:Error,value?:string)=>{if(settled)return;settled=true;clearTimeout(timer);signal.removeEventListener('abort',abort);if(error){child.kill('SIGTERM');reject(error);}else resolve(value??'');};
  const abort=()=>finish(new ProviderFailure('cancelled',kind));
  const timer=setTimeout(()=>finish(new ProviderFailure('timeout',kind)),timeoutMs);
  signal.addEventListener('abort',abort,{once:true});
  child.stdout.on('data',d=>{out+=d;});
  child.stderr.on('data',()=>{});// CLI diagnostics may echo the prompt; never logged.
  child.on('error',()=>finish(new ProviderFailure('configuration',kind)));
  child.on('close',code=>code===0||out?finish(undefined,out):finish(new ProviderFailure('unavailable',kind)));
  child.stdin.end(stdin);
 });
}

/** Tool-free, image-free schema turns go to the subscription CLI; everything else keeps the configured provider. */
export class SubscriptionCliRouter implements AgentProvider {
 constructor(private cli:SubscriptionCliProvider,private fallback:AgentProvider){}
 scope(options:Parameters<NonNullable<AgentProvider['scope']>>[0]):AgentProvider{
  return new SubscriptionCliRouter(this.cli,this.fallback.scope?.(options)??this.fallback);
 }
 async disposeOperation(history:History){await this.fallback.disposeOperation?.(history);}
 turn(input:Parameters<AgentProvider['turn']>[0]):Promise<ProviderReply>{
  const hasImage=input.history.some(step=>((step as any).content??[]).some((c:any)=>c?.type==='image'));
  const toolFree=!input.tools.length||input.toolMode==='none';
  return toolFree&&!hasImage&&input.outputSchema?this.cli.turn(input):this.fallback.turn(input);
 }
}
