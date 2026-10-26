import {createServer,request as httpRequest,type Server} from 'node:http';
import {once} from 'node:events';
import {afterEach,describe,it,expect,vi} from 'vitest';
import {createAIRequestHandler} from '../src/http.js';
import {Gateway} from '../src/gateway.js';
import {FeatureRunner} from '../src/features.js';
import {IntentInterpreter} from '../src/intents.js';
import type {AgentProvider,ProviderReply} from '../src/provider.js';
function deferred<T>(){let resolve!:(value:T)=>void;const promise=new Promise<T>(done=>{resolve=done});return {promise,resolve};}
const binding={sessionID:'synthetic-session',revision:1,eventSequence:1,contextDigest:'synthetic-digest',householdRevision:1,homeRevision:1};
const snapshot={simMinute:0,resources:{},services:{},unmetRequirements:[],unknowns:[]};
const request={contractVersion:'dryrun.ai/1',requestID:'synthetic-request',role:'director',synthetic:true,context:{binding,snapshot,profiles:[]}};
const previewCall={type:'function_call' as const,id:'preview',name:'evaluateCandidateAction',arguments:{command:{kind:'advance',minute:20}}};
const toolReply:ProviderReply={steps:[previewCall],text:'',calls:[previewCall],usage:{input:3}};
const finalReply:ProviderReply={steps:[],text:JSON.stringify({commands:[{kind:'advance',minute:20}],purpose:'Examine the actual result',evidenceIDs:[]}),calls:[],usage:{input:5}};
const servers:Server[]=[];
afterEach(async()=>{for(const server of servers.splice(0)){server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));}});
async function service(provider:AgentProvider){
 const gateway=new Gateway(provider),features=new FeatureRunner(provider),interpreter=new IntentInterpreter(provider);
 const handler=createAIRequestHandler({gateway,features,interpreter,authorize:header=>{if(header!=='Bearer synthetic-A'&&header!=='Bearer synthetic-B')throw new Error('unauthorized');return header;}});
 const server=createServer(handler);servers.push(server);server.listen(0,'127.0.0.1');await once(server,'listening');
 const address=server.address();if(!address||typeof address==='string')throw new Error('test_server');
 const post=async(path:string,body:unknown,signal?:AbortSignal,owner='synthetic-A')=>fetch(`http://127.0.0.1:${address.port}${path}`,{method:'POST',headers:{authorization:`Bearer ${owner}`,'Content-Type':'application/json'},body:JSON.stringify(body),signal});
 return {post,gateway,features,port:address.port};
}
describe('actual HTTP disconnect and director continuation cancellation',()=>{
 it('preserves a normal authenticated tool continuation through completion',async()=>{
  let calls=0;const {post}=await service({async turn(){return ++calls===1?toolReply:finalReply;}});
  const denied=await post('/v1/operations',request,undefined,'not-authorized');expect(denied.status).toBe(400);expect(calls).toBe(0);
  const response=await post('/v1/operations',request);expect(response.headers.get('cache-control')).toBe('no-store');
  const start=await response.json() as any;expect(start.status).toBe('needs_client_tools');
  const continuation={token:start.token,binding,callID:'preview',result:{binding,snapshot,contextDigest:'synthetic-preview'}};
  const completed=await (await post('/v1/continue',continuation)).json() as any;
  expect(completed.status).toBe('completed');expect(completed.proposal.binding).toEqual(binding);expect(calls).toBe(2);
  expect((await post('/v1/continue',continuation)).status).toBe(400);
 });
 it('preserves submitted Unicode evidence when a UTF-8 character spans transport chunks',async()=>{
  const text='agua para bebés · nước · 水';let observed='';
  const {port}=await service({async turn(input){observed=JSON.parse((input.history[0] as any).content[0].text).intake[0].text;return {steps:[],calls:[],usage:{},text:JSON.stringify({tasks:[],inventoryObservations:[],question:null})};}});
  const context={household:{revision:1,people:[],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[]},tasks:[],gaps:[],allowedActionIDs:[],allowedCriterionIDs:[],intake:[{id:'typed',text}]};
  const bytes=Buffer.from(JSON.stringify({contractVersion:'dryrun.ai/1',requestID:'unicode',synthetic:true,role:'preparation',context}));
  const split=bytes.indexOf(Buffer.from('水'))+1;
  const response=new Promise<number>((resolve,reject)=>{
   const req=httpRequest({hostname:'127.0.0.1',port,path:'/v1/features',method:'POST',headers:{authorization:'Bearer synthetic-A','Content-Type':'application/json'}},res=>{res.resume();res.on('end',()=>resolve(res.statusCode!))});
   req.on('error',reject);req.setNoDelay(true);req.write(bytes.subarray(0,split));
   setTimeout(()=>req.end(bytes.subarray(split)),20);
  });
  expect(await response).toBe(200);expect(observed).toBe(text);
 });
 it('aborts a director SDK boundary when its initiating connection disconnects',async()=>{
  const started=deferred<void>(),aborted=deferred<void>(),late=deferred<ProviderReply>();
  const provider:AgentProvider={async turn(input){input.signal.addEventListener('abort',()=>aborted.resolve(),{once:true});started.resolve();return late.promise;}};
  const {post,gateway}=await service(provider),abort=new AbortController();
  const pending=post('/v1/operations',request,abort.signal),rejected=expect(pending).rejects.toThrow();await started.promise;
  abort.abort();await rejected;await aborted.promise;late.resolve(toolReply);
  await vi.waitFor(()=>expect(gateway.metrics.outcomes).toEqual(['cancelled']));
  expect(gateway.metrics.calls).toBe(1);expect(gateway.metrics.usage).toEqual([{input:3}]);
  await expect(gateway.start('Bearer synthetic-A',request)).rejects.toThrow('replay');
 });
 it('keeps a delivered tool request alive, then aborts a disconnected continuation',async()=>{
  const started=deferred<void>(),aborted=deferred<void>(),late=deferred<ProviderReply>();let calls=0;
  const provider:AgentProvider={async turn(input){if(++calls===1)return toolReply;input.signal.addEventListener('abort',()=>aborted.resolve(),{once:true});started.resolve();return late.promise;}};
  const {post,gateway}=await service(provider);
  const start=await (await post('/v1/operations',request)).json() as any;expect(start.status).toBe('needs_client_tools');
  const continuation={token:start.token,binding,callID:'preview',result:{binding,snapshot,contextDigest:'synthetic-preview'}};
  const abort=new AbortController(),pending=post('/v1/continue',continuation,abort.signal),rejected=expect(pending).rejects.toThrow();
  await started.promise;abort.abort();await rejected;await aborted.promise;late.resolve(finalReply);
  await vi.waitFor(()=>expect(gateway.metrics.outcomes).toEqual(['cancelled']));expect(calls).toBe(2);
  const retry=await post('/v1/continue',continuation);expect(retry.status).toBe(400);
 });
 it('allows only the owner to cancel an in-flight continuation using its consumed token',async()=>{
  const started=deferred<void>(),aborted=deferred<void>(),late=deferred<ProviderReply>();let calls=0;let wasAborted=false;
  const provider:AgentProvider={async turn(input){if(++calls===1)return toolReply;input.signal.addEventListener('abort',()=>{wasAborted=true;aborted.resolve()},{once:true});started.resolve();return late.promise;}};
  const {post}=await service(provider);
  const start=await (await post('/v1/operations',request)).json() as any;
  const continuation={token:start.token,binding,callID:'preview',result:{binding,snapshot,contextDigest:'synthetic-preview'}};
  const pending=post('/v1/continue',continuation);await started.promise;
  await post('/v1/cancel',{token:start.token},undefined,'synthetic-B');expect(wasAborted).toBe(false);
  await post('/v1/cancel',{token:start.token});await aborted.promise;late.resolve(finalReply);
  expect(await (await pending).json()).toMatchObject({status:'unavailable'});
  expect((await post('/v1/continue',continuation)).status).toBe(400);
 });
 it('aborts preparation on disconnect and rejects an ignored-abort late result',async()=>{
  const started=deferred<void>(),aborted=deferred<void>(),late=deferred<ProviderReply>();
  const {post,features}=await service({async turn(input){input.signal.addEventListener('abort',()=>aborted.resolve(),{once:true});started.resolve();return late.promise;}});
  const context={household:{revision:1,people:[],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[]},tasks:[],gaps:[],allowedActionIDs:[],allowedCriterionIDs:[]};
  const abort=new AbortController(),pending=post('/v1/features',{contractVersion:'dryrun.ai/1',requestID:'synthetic-feature',synthetic:true,role:'preparation',context},abort.signal),rejected=expect(pending).rejects.toThrow();
  await started.promise;abort.abort();await rejected;await aborted.promise;
  late.resolve({steps:[],calls:[],text:JSON.stringify({tasks:[],inventoryObservations:[],question:null}),usage:{input:9}});
  await vi.waitFor(()=>expect(features.usage).toEqual([{input:9}]));expect(features.calls).toBe(1);
 });
});
