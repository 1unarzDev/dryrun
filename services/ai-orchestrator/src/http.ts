import type {RequestListener} from 'node:http';
import {z} from 'zod';
import {normalizeHomeReview} from './home-review.js';
import {intentRequest,type IntentInterpreter} from './intents.js';
import type {Gateway} from './gateway.js';
import {featureContext,type FeatureRunner} from './features.js';

/** Transport adapter only. Production verification remains an explicit startup dependency. */
export function createAIRequestHandler({gateway,features,interpreter,authorize}:{gateway:Gateway;features:FeatureRunner;interpreter:IntentInterpreter;authorize:(header:string|undefined)=>string}):RequestListener {
 const seen=new Set<string>();
return async(req,res)=>{
 const controller=new AbortController();
 const disconnected=()=>{if(!res.writableEnded)controller.abort()};
 req.once('aborted',disconnected);res.once('close',disconnected);
 res.setHeader('Cache-Control','no-store');res.setHeader('Content-Type','application/json');
 try{const owner=authorize(req.headers.authorization);if(req.method!=='POST')throw new Error('method');const chunks:Buffer[]=[];let bytes=0;for await(const chunk of req){bytes+=chunk.length;if(bytes>(req.url==='/v1/features'?6000000:96000))throw new Error('payload');chunks.push(chunk);}const input:unknown=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));
 if(req.url==='/v1/intents'){
 const r=intentRequest.parse(input);const key=owner+':'+r.requestID;
 if(seen.has(key)||seen.size>=100)throw new Error('replay_or_quota');seen.add(key);
 const proposal=await interpreter.interpret(r,AbortSignal.any([controller.signal,AbortSignal.timeout(30000)]));
 res.end(JSON.stringify({status:'completed',requestID:r.requestID,proposal}));return;
 }
 if(req.url==='/v1/features'){
 const r=z.object({contractVersion:z.literal('dryrun.ai/1'),requestID:z.string().min(1).max(120),synthetic:z.literal(true),role:z.enum(['preparation','resources','home','stress','council']),context:featureContext,images:z.array(z.unknown()).max(4).default([])}).strict().parse(input);
 const key=owner+':'+r.requestID;if(seen.has(key)||seen.size>=100)throw new Error('replay_or_quota');seen.add(key);
 const proposal=r.role==='council'?await features.council(r.context,controller.signal):await features.run(r.role,r.context,AbortSignal.any([controller.signal,AbortSignal.timeout(60000)]),r.images);
 res.end(JSON.stringify({status:'completed',contractVersion:'dryrun.ai/1',requestID:r.requestID,householdRevision:r.context.household.revision,proposal,...(r.role==='home'?{reviewProposals:normalizeHomeReview(proposal,r.context)}:{})}));return;
 }
 const result=req.url==='/v1/operations'?await gateway.start(owner,input,controller.signal):req.url==='/v1/continue'?await gateway.resume(owner,input,controller.signal):req.url==='/v1/cancel'&&typeof input==='object'&&input!==null&&'token'in input&&typeof input.token==='string'?gateway.cancel(owner,input.token):{status:'rejected',reason:'unknown_endpoint'};
 res.end(JSON.stringify(result));}catch{res.statusCode=400;res.end(JSON.stringify({status:'rejected',reason:'invalid_or_unauthorized_request'}));}
 finally {req.off('aborted',disconnected);res.off('close',disconnected);}
};
}
