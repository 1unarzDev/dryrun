import type {RequestListener} from 'node:http';
import {z} from 'zod';
import {normalizeHomeReview} from './home-review.js';
import {intentRequest,type IntentInterpreter} from './intents.js';
import type {Gateway} from './gateway.js';
import {featureContext,type FeatureRunner} from './features.js';
import {practicePlanRequest} from './practice-plan.js';
import {CodexFailure} from './codex-errors.js';
import type {InstallationAuth} from './app-attest.js';
import {ProviderFailure} from './groq.js';
import {FeatureValidationFailure,providerOutcomeMessages} from './provider-failure.js';
import {researchBrief,type ResourceDiscovery} from './resource-discovery.js';
import {RequestWindow,RequestWindowFailure} from './request-window.js';

/** Whole-operation bound per feature role, inside the native client's own request timeout (95 s for
 * preparation/debrief/drillSetup/stress, 70 s for resources/home), so a Codex attempt plus a fallback can finish. */
export function featureTimeoutMs(role:string){return role==='resources'||role==='home'?65000:88000;}
/** Transport adapter only. Production verification remains an explicit startup dependency. */
export function createAIRequestHandler({gateway,features,interpreter,authorize,attest,discovery,maximumRequests}:{gateway:Gateway;features:FeatureRunner;interpreter:IntentInterpreter;authorize:(header:string|undefined)=>string;attest?:InstallationAuth;discovery?:ResourceDiscovery;maximumRequests?:number}):RequestListener {
 const requests=new RequestWindow(maximumRequests);
return async(req,res)=>{
 const controller=new AbortController();
 const disconnected=()=>{if(!res.writableEnded)controller.abort()};
 req.once('aborted',disconnected);res.once('close',disconnected);
 res.setHeader('Cache-Control','no-store');res.setHeader('Content-Type','application/json');
 // Opt-in operator log for the Mac demo gateway: method, path, HTTP status, outcome status/reason and time only.
 if(process.env.DRYRUN_ACCESS_LOG==='1'){const started=Date.now();const end=res.end.bind(res);let outcome='';
  res.end=((chunk?:unknown,...rest:unknown[])=>{try{const o=typeof chunk==='string'?JSON.parse(chunk):undefined;outcome=[o?.status,o?.reason,o?.diagnostic,o?.outcome,o?.provider&&'provider='+o.provider,o?.servedBy&&'servedBy='+o.servedBy].filter(v=>typeof v==='string'&&/^[a-zA-Z0-9_=]{1,64}$/.test(v)).join(' ');}catch{}return(end as (...a:unknown[])=>typeof res)(chunk,...rest);}) as typeof res.end;
  res.once('finish',()=>console.log(`${new Date().toISOString()} ${req.method} ${req.url} ${res.statusCode} ${outcome} ${Date.now()-started}ms`));}
 try{
 if(req.url==='/health'&&req.method==='GET'){res.end(JSON.stringify({status:'ok'}));return;}
 if(attest&&req.url?.startsWith('/v1/attest/')){
  if(req.method!=='POST')throw new Error('method');
  const chunks:Buffer[]=[];let bytes=0;
  for await(const chunk of req){bytes+=chunk.length;if(bytes>24000)throw new Error('payload');chunks.push(chunk);}
  const body=z.object({keyId:z.string().max(64).optional(),attestation:z.string().max(16000).optional(),challenge:z.string().max(64).optional(),assertion:z.string().max(2000).optional(),clientData:z.string().max(1000).optional()}).strict().parse(bytes?JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks))):{});
  const out=req.url==='/v1/attest/challenge'?attest.challenge()
   :req.url==='/v1/attest/register'&&body.keyId&&body.attestation&&body.challenge?attest.register(body.keyId,body.attestation,body.challenge)
   :req.url==='/v1/attest/session'&&body.keyId&&body.assertion&&body.clientData?attest.session(body.keyId,body.assertion,body.clientData)
   :(()=>{throw new Error('unknown_endpoint');})();
  res.end(JSON.stringify(out));return;
 }
 const owner=authorize(req.headers.authorization);if(req.method!=='POST')throw new Error('method');const chunks:Buffer[]=[];let bytes=0;for await(const chunk of req){bytes+=chunk.length;if(bytes>(req.url==='/v1/features'||req.url==='/v1/operations'?6000000:96000))throw new Error('payload');chunks.push(chunk);}const input:unknown=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));
 if(req.url==='/v1/research'){
  const r=z.object({contractVersion:z.literal('dryrun.ai/1'),requestID:z.string().min(1).max(120),synthetic:z.literal(true),brief:researchBrief}).strict().parse(input);
  if(!discovery)throw new Error('provider_unavailable');requests.claim(owner,r.requestID);
  const result=await discovery.discover(r.brief,AbortSignal.any([controller.signal,AbortSignal.timeout(60000)]),owner);
  res.end(JSON.stringify({status:'completed',requestID:r.requestID,result}));return;
 }
 if(req.url==='/v1/intents'){
 const r=intentRequest.parse(input);requests.claim(owner,r.requestID);
 const proposal=await interpreter.interpret(r,AbortSignal.any([controller.signal,AbortSignal.timeout(30000)]),owner);
 res.end(JSON.stringify({status:'completed',requestID:r.requestID,proposal}));return;
 }
 if(req.url==='/v1/practice-plan'){
  const r=practicePlanRequest.parse(input);requests.claim(owner,r.requestID);
  const {plan,servedBy}=await features.practicePlan(r,AbortSignal.any([controller.signal,AbortSignal.timeout(40000)]),owner,35000);
  res.end(JSON.stringify({status:'completed',contractVersion:'dryrun.ai/1',requestID:r.requestID,servedBy,proposal:plan}));return;
 }
 if(req.url==='/v1/features'){
 const r=z.object({contractVersion:z.literal('dryrun.ai/1'),requestID:z.string().min(1).max(120),synthetic:z.literal(true),role:z.enum(['preparation','debrief','drillSetup','resources','home','stress','council']),providerConsent:z.array(z.enum(['gemini','groq','codex'])).min(1).max(3).optional(),context:featureContext,images:z.array(z.unknown()).max(4).default([])}).strict().parse(input);
 requests.claim(owner,r.requestID);
 const timeoutMs=featureTimeoutMs(r.role);
 const proposal=r.role==='council'?await features.council(r.context,controller.signal,owner,r.providerConsent):await features.run(r.role,r.context,AbortSignal.any([controller.signal,AbortSignal.timeout(timeoutMs)]),r.images,owner,r.providerConsent,timeoutMs);
 const servedBy=features.servedBy?.(proposal);
 res.end(JSON.stringify({status:'completed',contractVersion:'dryrun.ai/1',requestID:r.requestID,householdRevision:r.context.household.revision,contextBinding:r.context.contextBinding,...(servedBy?{servedBy}:{}),proposal,...(r.role==='home'?{reviewProposals:normalizeHomeReview(proposal,r.context)}:{})}));return;
 }
 const result=req.url==='/v1/operations'?await gateway.start(owner,input,controller.signal):req.url==='/v1/continue'?await gateway.resume(owner,input,controller.signal):req.url==='/v1/cancel'&&typeof input==='object'&&input!==null&&'token'in input&&typeof input.token==='string'?gateway.cancel(owner,input.token):{status:'rejected',reason:'unknown_endpoint'};
 res.end(JSON.stringify(result));}catch(error){
 if(error instanceof RequestWindowFailure){res.statusCode=error.reason==='request_quota'?429:409;res.end(JSON.stringify({status:'rejected',reason:error.reason}));}
 else if(error instanceof CodexFailure){res.statusCode=error.kind==='throttled'?429:error.kind==='deadline'?504:503;res.end(JSON.stringify({status:'unavailable',reason:'codex_'+error.kind}));}
 // Host validation rejected the served provider's output after one repair: replayable like other provider_ reasons,
 // but attributed to the provider that served it with an allowlisted validator code (never codex_* for Gemini/Groq).
 else if(error instanceof FeatureValidationFailure){res.end(JSON.stringify({status:'unavailable',reason:'provider_validation_failure',provider:error.provider,diagnostic:error.code,preservePriorResult:true,fallback:'existing_local_or_pending'}));}
 else if(error instanceof ProviderFailure){res.end(JSON.stringify({status:'unavailable',reason:`provider_${error.kind}`,provider:error.provider,retryAfterMs:error.retryAfterMs,diagnostic:error.diagnostic,preservePriorResult:true,fallback:'existing_local_or_pending'}));}
 else if(req.url==='/v1/practice-plan'&&error instanceof Error&&/^(?:practice_[a-z_]+|internal_id|unsupported_assurance)$/.test(error.message)){res.end(JSON.stringify({status:'unavailable',reason:'provider_validation_failure',diagnostic:error.message,fallback:'deterministic_core_plan'}));}
 else if(error instanceof Error&&providerOutcomeMessages.includes(error.message)){res.end(JSON.stringify({status:'unavailable',reason:error.message,preservePriorResult:true,fallback:'existing_local_or_pending'}));}
 else{res.statusCode=400;res.end(JSON.stringify({status:'rejected',reason:'invalid_or_unauthorized_request'}));}}
 finally {req.off('aborted',disconnected);res.off('close',disconnected);}
};
}
