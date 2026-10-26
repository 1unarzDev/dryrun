// Authored synthetic protocol inputs only. No recorded provider answers/fixtures.
import {describe,it,expect} from 'vitest';
import {CodexProvider,codexSpeedFromEnv,defaultCodexSpeed,type CodexCapabilities} from '../src/codex-provider.js';
import {codexEndpoint,codexRuntimeVersion,type CodexConnection,type RpcMessage} from '../src/codex-runtime.js';
import type {History} from '../src/provider.js';

const capabilities:CodexCapabilities={runtimeVersion:codexRuntimeVersion,endpoint:codexEndpoint,model:'synthetic-model',reviewReportID:'report-synthetic-only',streaming:true,tools:true,continuation:true,structuredOutput:true,lifecycle:true,images:false,research:false};
class SyntheticConnection implements CodexConnection {
 onMessage=(_m:RpcMessage)=>{};onFailure=()=>{};closed=false;requests:{method:string;params:any}[]=[];
 async request(method:string,params:any){this.requests.push({method,params});if(method==='thread/start')return {thread:{id:'thread-synthetic'}};return {};}
 notify(){}respond(){}
 async close(){this.closed=true;}
 finish(){this.onMessage({method:'item/completed',params:{threadId:'thread-synthetic',item:{type:'agentMessage',text:'{"synthetic":true}'}}});this.onMessage({method:'turn/completed',params:{threadId:'thread-synthetic',turn:{status:'completed'}}});}
}
const history=():History=>[{type:'user_input',content:[{type:'text',text:'{"synthetic":1}'}]}];
const flush=async()=>{for(let i=0;i<20;i++)await Promise.resolve();};
const run=async(p:CodexProvider,c:()=>SyntheticConnection,instruction:string)=>{const pending=p.turn({history:history(),instruction,tools:[],signal:new AbortController().signal});await flush();c().finish();return pending;};

describe('Codex speed settings',()=>{
 it('defaults to low effort, no reasoning summary and the priority tier on every turn',async()=>{
  const c=new SyntheticConnection();const p=new CodexProvider('synthetic-key',capabilities,async()=>c);
  await run(p,()=>c,'DryRun preparation prompt/16.');
  const start=c.requests.find(r=>r.method==='turn/start')!.params;
  expect(start).toMatchObject({effort:'low',summary:'none',serviceTier:'priority'});
 });
 it('applies the director effort to director turns and omits the tier when disabled',async()=>{
  const c=new SyntheticConnection();const p=new CodexProvider('synthetic-key',capabilities,async()=>c,undefined,{...defaultCodexSpeed,effort:'medium',directorEffort:'low',serviceTier:null});
  await run(p,()=>c,'DryRun RehearsalDirector prompt/32.');
  const start=c.requests.find(r=>r.method==='turn/start')!.params;
  expect(start.effort).toBe('low');expect('serviceTier' in start).toBe(false);
 });
 it('parses only catalog-verified efforts and bounded warm sizes from the environment',()=>{
  expect(codexSpeedFromEnv({})).toEqual({effort:'low',directorEffort:'low',serviceTier:'priority',warm:2});
  expect(codexSpeedFromEnv({DRYRUN_CODEX_EFFORT:'minimal',DRYRUN_CODEX_DIRECTOR_EFFORT:'medium',DRYRUN_CODEX_SERVICE_TIER:'none',DRYRUN_CODEX_WARM:'9'})).toEqual({effort:'low',directorEffort:'medium',serviceTier:null,warm:2});
  expect(codexSpeedFromEnv({DRYRUN_CODEX_WARM:'0'}).warm).toBe(0);
 });
 it('serves an operation from a pre-initialized warm runtime and refills the pool',async()=>{
  const spawned:SyntheticConnection[]=[];
  const p=new CodexProvider('synthetic-key',capabilities,async()=>{const c=new SyntheticConnection();spawned.push(c);return c;},undefined,{...defaultCodexSpeed,warm:1});
  await p.prewarm();expect(spawned).toHaveLength(1);expect(spawned[0]!.requests.map(r=>r.method)).toEqual(['initialize']);
  await run(p,()=>spawned[0]!,'DryRun debrief prompt/1.');
  // The warm runtime was not initialized twice; the operation went straight to thread/start.
  expect(spawned[0]!.requests.map(r=>r.method)).toEqual(['initialize','thread/start','turn/start']);
  expect(spawned[0]!.closed).toBe(true);
  await flush();expect(spawned).toHaveLength(2);
  await p.shutdown();expect(spawned[1]!.closed).toBe(true);
 });
 it('drops a warm runtime that failed while idle and starts cold',async()=>{
  const spawned:SyntheticConnection[]=[];
  const p=new CodexProvider('synthetic-key',capabilities,async()=>{const c=new SyntheticConnection();spawned.push(c);return c;},undefined,{...defaultCodexSpeed,warm:1});
  await p.prewarm();spawned[0]!.onFailure();
  const pending=p.turn({history:history(),instruction:'DryRun debrief prompt/1.',tools:[],signal:new AbortController().signal});await flush();
  const cold=spawned.find(c=>c.requests.some(r=>r.method==='thread/start'))!;
  expect(cold).not.toBe(spawned[0]);cold.finish();await pending;await p.shutdown();
 });
});
