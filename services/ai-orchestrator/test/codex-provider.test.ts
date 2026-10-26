// Authored synthetic protocol inputs only. No recorded provider answers/fixtures.
import {describe,it,expect} from 'vitest';
import {CodexProvider,type CodexCapabilities} from '../src/codex-provider.js';
import {codexEndpoint,codexRuntimeVersion,type CodexConnection,type RpcMessage} from '../src/codex-runtime.js';
import type {History} from '../src/provider.js';

const capabilities:CodexCapabilities={runtimeVersion:codexRuntimeVersion,endpoint:codexEndpoint,model:'synthetic-model',reviewReportID:'report-synthetic-only',streaming:true,tools:true,continuation:true,structuredOutput:true,lifecycle:true,images:false,research:false};
class SyntheticConnection implements CodexConnection {
 onMessage=(_m:RpcMessage)=>{};onFailure=()=>{};closed=false;requests:{method:string;params:any}[]=[];results:{id:number|string;result:any}[]=[];
 async request(method:string,params:any){this.requests.push({method,params});if(method==='thread/start')return {thread:{id:'thread-synthetic'}};return {};}
 notify(){}respond(id:number|string,result:unknown){this.results.push({id,result});}
 async close(){this.closed=true;}
 emit(m:RpcMessage){this.onMessage(m);}
 tool(args:unknown={},name='preview'){this.emit({id:77,method:'item/tool/call',params:{threadId:'thread-synthetic',turnId:'turn-synthetic',callId:'call-synthetic',namespace:null,tool:name,arguments:args}});}
 finish(){this.emit({method:'item/completed',params:{threadId:'thread-synthetic',item:{type:'agentMessage',text:'{"synthetic":true}'}}});this.emit({method:'turn/completed',params:{threadId:'thread-synthetic',turn:{status:'completed'}}});}
}
const history=():History=>[{type:'user_input',content:[{type:'text',text:JSON.stringify({snapshot:'synthetic-one',member:'person-a'})}]}];
const input=(h:History,signal=new AbortController().signal)=>({history:h,instruction:'Authored synthetic protocol exercise only',tools:[{type:'function' as const,name:'preview',parameters:{type:'object',properties:{},additionalProperties:false}}],signal});
const flush=async()=>{for(let i=0;i<10;i++)await Promise.resolve();};
describe('Codex bounded runtime contract',()=>{
 it('rejects incomplete capability evidence before invoking the runtime',()=>{
  expect(()=>new CodexProvider('synthetic-key',{...capabilities,tools:false})).toThrow('codex_capability_gate');
  expect(()=>new CodexProvider('synthetic-key',{...capabilities,runtimeVersion:'different'})).toThrow('codex_capability_gate');
 });
 it('continues the exact dynamic call with the matched host result, without starting another turn',async()=>{
  const c=new SyntheticConnection();const p=new CodexProvider('synthetic-key',capabilities,async()=>c);const h=history();
  const first=p.turn(input(h));await flush();c.tool();const reply=await first;h.push(...reply.steps,{type:'function_result',name:'preview',call_id:'call-synthetic',result:[{type:'text',text:'{"hostRevision":9}'}]});
  const next=p.turn(input(h));await flush();expect(c.results).toHaveLength(1);expect(c.results[0]?.id).toBe(77);expect(c.results[0]?.result.success).toBe(true);c.finish();await next;
  expect(c.requests.filter(r=>r.method==='turn/start')).toHaveLength(1);expect(c.closed).toBe(true);
 });
 it('rejects unmatched continuation results and closes the private worker',async()=>{
  const c=new SyntheticConnection();const p=new CodexProvider('synthetic-key',capabilities,async()=>c);const h=history();const first=p.turn(input(h));await flush();c.tool();await first;
  await expect(p.turn(input(h))).rejects.toThrow('codex_unavailable');expect(c.closed).toBe(true);expect(c.results).toHaveLength(0);
 });
 it.each([null,[],5])('rejects non-object dynamic arguments (%j)',async args=>{
  const c=new SyntheticConnection();const p=new CodexProvider('synthetic-key',capabilities,async()=>c);const pending=p.turn(input(history()));const assertion=expect(pending).rejects.toThrow();await flush();c.tool(args);await assertion;expect(c.closed).toBe(true);
 });
 it('rejects unknown tools and arbitrary runtime permission requests',async()=>{
  for(const request of [{id:8,method:'item/permissions/requestApproval',params:{}},{id:77,method:'item/tool/call',params:{threadId:'thread-synthetic',callId:'x',tool:'read_owner_file',namespace:null,arguments:{}}}]){
   const c=new SyntheticConnection();const p=new CodexProvider('synthetic-key',capabilities,async()=>c);const pending=p.turn(input(history()));const assertion=expect(pending).rejects.toThrow();await flush();c.emit(request);await assertion;expect(c.closed).toBe(true);
  }
 });
 it('isolates equal-ID households by distinct host history identity',async()=>{
  const connections:SyntheticConnection[]=[];const p=new CodexProvider('synthetic-key',capabilities,async()=>{const c=new SyntheticConnection();connections.push(c);return c;});
  const a=p.turn(input(history())),b=p.turn(input(history()));await flush();expect(connections).toHaveLength(2);connections[0]!.finish();await a;expect(connections[1]!.closed).toBe(false);connections[1]!.finish();await b;
 });
 it('cancels a paused native continuation and rejects late worker content',async()=>{
  const c=new SyntheticConnection();const p=new CodexProvider('synthetic-key',capabilities,async()=>c);const a=new AbortController();const h=history();const first=p.turn(input(h,a.signal));await flush();c.tool();await first;a.abort();expect(c.closed).toBe(true);c.finish();await expect(p.turn(input(h,a.signal))).rejects.toThrow('codex_cancelled');
 });
 it('bounds an unresponsive runtime and sanitizes its failure',async()=>{
  const c=new SyntheticConnection();const p=new CodexProvider('synthetic-key',capabilities,async()=>c,10);const pending=p.turn(input(history()));await expect(pending).rejects.toThrow('codex_deadline');expect(c.closed).toBe(true);
 });
 it('explicitly disposes a paused tool operation without waiting for its deadline',async()=>{
  const c=new SyntheticConnection();const p=new CodexProvider('synthetic-key',capabilities,async()=>c);const h=history();const first=p.turn(input(h));await flush();c.tool();await first;
  await p.disposeOperation(h);expect(c.closed).toBe(true);expect(c.results).toHaveLength(0);c.finish();
 });
 it.each([[{error:{codexErrorInfo:{httpConnectionFailed:{httpStatusCode:429}},message:'private sentinel'}},'codex_throttled'],[{error:{code:'invalid_schema',message:'private sentinel'}},'codex_invalid_schema'],[{error:{code:'unsupported_image',message:'private sentinel'}},'codex_unsupported_capability']])('maps safe metadata only',async(metadata,expected)=>{
  const c=new SyntheticConnection();const p=new CodexProvider('synthetic-key',capabilities,async()=>c);const pending=p.turn(input(history()));const assertion=pending.then(()=>{throw new Error('expected_rejection');},error=>{expect(error.message).toBe(expected);expect(JSON.stringify(error)).not.toContain('private sentinel');});await flush();c.emit({method:'error',params:metadata});await assertion;expect(c.closed).toBe(true);
 });
});

it('retains a bounded terminal diagnostic drain after an error precursor without releasing late output',async()=>{
 const c=new SyntheticConnection();const p=new CodexProvider('authored-key',capabilities,async()=>c);const pending=p.turn(input(history()));const assertion=expect(pending).rejects.toThrow('codex_invalid_schema');await flush();
 c.emit({method:'error',params:{message:'Authored error precursor'}});expect(c.closed).toBe(false);
 c.emit({method:'item/completed',params:{threadId:'thread-synthetic',item:{type:'agentMessage',text:'Authored late untrusted text'}}});
 c.emit({method:'turn/completed',params:{threadId:'thread-synthetic',turn:{status:'failed',error:{code:'invalid_schema',message:'Invalid schema for response_format: authored schema diagnostic'}}}});await assertion;expect(c.closed).toBe(true);
});
it('closes an error precursor without terminal event within the finite drain allowance',async()=>{
 const c=new SyntheticConnection();const p=new CodexProvider('authored-key',capabilities,async()=>c);const pending=p.turn(input(history()));const assertion=expect(pending).rejects.toThrow();await flush();c.emit({method:'error',params:{message:'Authored unavailable'}});await assertion;expect(c.closed).toBe(true);
});
