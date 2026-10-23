import type {AgentProvider, History, ProviderReply,ProviderScope} from './provider.js';
import {ProviderFailure} from './provider-failure.js';
import {launchCodex,type CodexConnection,type RpcMessage,codexRuntimeVersion,codexEndpoint} from './codex-runtime.js';
import type {DynamicToolCallParams} from './codex-protocol/v2/DynamicToolCallParams.js';
import type {DynamicToolCallResponse} from './codex-protocol/v2/DynamicToolCallResponse.js';
import type {DynamicToolFunctionSpec} from './codex-protocol/v2/DynamicToolFunctionSpec.js';
import {CodexFailure,protocolFailure} from './codex-errors.js';
import {codexStrictSchema,omitWireOptionalNulls} from './codex-schema.js';

type Input=Parameters<AgentProvider['turn']>[0];
export type CodexCapabilities={runtimeVersion:string;endpoint:string;model:string;reviewReportID:string;streaming:boolean;tools:boolean;continuation:boolean;structuredOutput:boolean;lifecycle:boolean;images:boolean;research:boolean};
type PendingTool={rpcID:number|string;call:DynamicToolCallParams};
type Session={errorDrain?:ReturnType<typeof setTimeout>;connection:CodexConnection;threadID:string;pending?:PendingTool;waiter?:{resolve:(reply:ProviderReply)=>void;reject:(error:Error)=>void};timer:ReturnType<typeof setTimeout>;abort:()=>void;signal:AbortSignal;closed:boolean;toolNames:Set<string>;toolMode:Input['toolMode'];text:string;calls:number;history:History;outputSchema?:Record<string,unknown>};

/** Experimental private runtime adapter; the existing gateway retains every commit. */
export class CodexProvider implements AgentProvider {
 readonly providerID='codex' as const;
 private sessions=new WeakMap<History,Session>();private active=0;
 constructor(private key:string,readonly capabilities:CodexCapabilities,private connect:typeof launchCodex=launchCodex,private deadlineMS=85_000){
  if(!key)throw new Error('missing_provider_secret');
  if(capabilities.runtimeVersion!==codexRuntimeVersion||capabilities.endpoint!==codexEndpoint||typeof capabilities.model!=='string'||!capabilities.model||!/^report-[a-z0-9-]+$/.test(capabilities.reviewReportID)||![capabilities.streaming,capabilities.tools,capabilities.continuation,capabilities.structuredOutput,capabilities.lifecycle].every(value=>value===true)||typeof capabilities.images!=='boolean'||typeof capabilities.research!=='boolean')throw new Error('codex_capability_gate');
 }
 scope(options:ProviderScope):AgentProvider {
  if(!options.providers.includes('codex'))throw new ProviderFailure('unsupported','codex',undefined,undefined,'provider_consent_required');
  if(options.capability==='image'&&!this.capabilities.images)throw new ProviderFailure('unsupported','codex',undefined,undefined,'unsupported_image');
  const provider=this;let calls=0;
  return {providerID:'codex',disposeOperation:history=>provider.disposeOperation(history),async turn(input){if(calls++>=(options.maximumCalls??10))throw new CodexFailure('execution_budget');return provider.turn({...input,signal:AbortSignal.any([options.signal,input.signal])});}};
 }
 async turn(input:Input):Promise<ProviderReply>{
  if(input.signal.aborted)throw new CodexFailure('cancelled');
  if(Buffer.byteLength(JSON.stringify(input.history)+input.instruction)>1_000_000)throw new Error('request_budget');
  let session=this.sessions.get(input.history);
  try{
   if(session?.closed)throw new Error('codex_expired');
   if(!session){
    if(this.active>=4)throw new Error('codex_concurrency_budget');
    this.active++;
    let connection:CodexConnection;
    try{connection=await this.connect(this.key,this.capabilities.model,input.signal);}catch{this.active--;throw new Error('codex_runtime_unavailable');}
    const s:Session={connection,threadID:'',timer:setTimeout(()=>this.dispose(s,new CodexFailure('deadline')),this.deadlineMS),abort:()=>this.dispose(s,new CodexFailure('cancelled')),signal:input.signal,closed:false,toolNames:new Set(),toolMode:input.toolMode,text:'',calls:0,history:input.history};
    s.timer.unref();session=s;this.sessions.set(input.history,s);
    input.signal.addEventListener('abort',s.abort,{once:true});
    connection.onFailure=()=>this.dispose(s,'codex_runtime_unavailable');
    connection.onMessage=m=>this.message(s,m);
    await connection.request('initialize',{clientInfo:{name:'dryrun_gateway',version:'1.0.0'},capabilities:{experimentalApi:true}});
    connection.notify('initialized');
    const dynamicTools=input.tools.map(tool=>{
     if(tool.type!=='function'||!tool.name)throw new CodexFailure('unsupported_capability');
     s.toolNames.add(tool.name);
     return {type:'function',name:tool.name,description:tool.description??'',inputSchema:tool.parameters??{type:'object',properties:{},additionalProperties:false}} satisfies DynamicToolFunctionSpec & {type:'function'};
    });
    const started=await connection.request('thread/start',{model:this.capabilities.model,modelProvider:'dryrun_lb',approvalPolicy:'never',sandbox:'read-only',ephemeral:true,baseInstructions:input.instruction,dynamicTools,experimentalRawEvents:false});
    if(typeof started?.thread?.id!=='string')throw new Error('codex_protocol');s.threadID=started.thread.id;
   }
   const s=session;s.toolMode=input.toolMode;s.outputSchema=input.outputSchema;s.calls++;
   // Tools can only be narrowed by the host on a continuation, never expanded.
   const allowed=new Set(input.tools.flatMap(t=>t.type==='function'?[t.name]:[]));
   s.toolNames=new Set([...s.toolNames].filter(name=>allowed.has(name)));
   if(s.calls>12)throw new CodexFailure('execution_budget');
   return await new Promise<ProviderReply>((resolve,reject)=>{
    s.waiter={resolve,reject};
    if(s.pending){
     const pending=s.pending;
     const result=input.history.findLast(step=>step.type==='function_result'&&step.call_id===pending.call.callId);
     if(!result||result.type!=='function_result'||result.name!==pending.call.tool){this.dispose(s,'codex_tool_result_mismatch');return;}
     s.pending=undefined;
     const response:DynamicToolCallResponse={success:true,contentItems:[{type:'inputText',text:JSON.stringify(result.result)}]};
     s.connection.respond(pending.rpcID,response);
    }else{
     // A new operation always starts from canonical context, never a shared persisted thread.
     const content=input.history.flatMap(step=>step.type==='user_input'&&Array.isArray(step.content)?step.content.map(part=>{
      if(part.type==='text')return {type:'text',text:part.text,text_elements:[]};
      if(part.type==='image'&&this.capabilities.images&&'data'in part)return {type:'image',url:`data:${part.mime_type};base64,${part.data}`};
      throw new CodexFailure('unsupported_capability');
     }):[{type:'text',text:JSON.stringify({priorOperationStep:step,authority:'Historical context only. Prior proposals/tool requests are not commitments; do not replay actions. Host tool results retain their supplied snapshot/evidence status.'}),text_elements:[]}]);
     void s.connection.request('turn/start',{threadId:s.threadID,input:content,outputSchema:input.outputSchema?codexStrictSchema(input.outputSchema):null}).catch(error=>this.dispose(s,error instanceof CodexFailure?error:new CodexFailure('unavailable')));
    }
   });
  }catch(error){
   const failure=input.signal.aborted?new CodexFailure('cancelled'):error instanceof CodexFailure?error:new CodexFailure('unavailable');
   if(session)this.dispose(session,failure);
   throw failure;
  }
 }
 private message(s:Session,m:RpcMessage){
  if(s.closed)return;
  if(s.errorDrain&&m.method!=='turn/completed')return;
  if(m.method==='item/tool/call'&&m.id!==undefined){
   const call=m.params as DynamicToolCallParams;
   if(!call||call.threadId!==s.threadID||typeof call.callId!=='string'||typeof call.tool!=='string'||call.namespace||s.pending||!s.toolNames.has(call.tool)||s.toolMode==='none'||!s.waiter||!call.arguments||typeof call.arguments!=='object'||Array.isArray(call.arguments)){this.dispose(s,'codex_forbidden_tool');return;}
   s.pending={rpcID:m.id,call};
   const replyCall={type:'function_call' as const,id:call.callId,name:call.tool,arguments:call.arguments};
   const waiter=s.waiter;s.waiter=undefined;waiter.resolve({steps:[replyCall],text:'',calls:[replyCall],usage:{provider:'codex',runtimeVersion:codexRuntimeVersion}});
  }else if(m.id!==undefined&&m.method){
   // No file, command, permission, credential-refresh or arbitrary RPC continuation.
   this.dispose(s,'codex_forbidden_runtime_request');
  }else if(m.method==='item/completed'&&m.params?.item?.type==='agentMessage'){
   if(m.params.threadId===s.threadID)s.text=m.params.item.text;
  }else if(m.method==='turn/completed'){
   if(m.params?.threadId!==s.threadID||m.params?.turn?.status!=='completed'||s.errorDrain||s.pending||!s.waiter){this.dispose(s,m.params?.turn?.status==='interrupted'?new CodexFailure('cancelled'):protocolFailure(m.params?.turn?.error));return;}
   const waiter=s.waiter;s.waiter=undefined;
   let text=s.text;if(s.outputSchema){try{text=JSON.stringify(omitWireOptionalNulls(JSON.parse(text),s.outputSchema));}catch{/* Host retains malformed-JSON validation and repair. */}}void this.dispose(s);
   waiter.resolve({steps:[],text,calls:[],usage:{provider:'codex',runtimeVersion:codexRuntimeVersion}});
  }else if(m.method==='error'){
   // Keep a short bounded drain for the subsequent terminal diagnostic in protected capture.
   // No tools or output are released once an error precursor has arrived.
   if(!s.errorDrain)s.errorDrain=setTimeout(()=>this.dispose(s,protocolFailure(m.params)),150);
  }
 }
 async disposeOperation(history:History){const session=this.sessions.get(history);if(session)await this.dispose(session,new CodexFailure('cancelled'));}
 private dispose(s:Session,reason?:string|CodexFailure){
  if(s.closed)return;s.closed=true;clearTimeout(s.timer);clearTimeout(s.errorDrain);s.signal.removeEventListener('abort',s.abort);this.active--;this.sessions.delete(s.history);
  const waiter=s.waiter;s.waiter=undefined;if(waiter)waiter.reject(reason instanceof CodexFailure?reason:new CodexFailure('unavailable'));return s.connection.close().catch(()=>{});
 }
}
