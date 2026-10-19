import {IntentInterpreter,intentRequest} from './intents.js';
import {PublicEvidenceTools} from './evidence.js';
import {createServer} from 'node:http';
import {Gateway,fixtureAuthorize} from './gateway.js';
import {FeatureRunner,featureContext,roleSchemas,type Role} from './features.js';
import {z} from 'zod';
import {GeminiProvider,SpendBudget} from './provider.js';
if(process.env.NODE_ENV==='production')throw new Error('production_authorization_provider_required');
const secret=process.env.DRYRUN_DEV_TOKEN??'';
if(secret.length<24)throw new Error('local_fixture_token_required');
const provider=new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??'',process.env.DRYRUN_MODEL,new SpendBudget(),{home:process.env.DRYRUN_HOME_MODEL??'gemini-3.8-flash',adjudication:process.env.DRYRUN_ASSESSMENT_MODEL??'gemini-3.1-flash-lite'});
const interpreter=new IntentInterpreter(provider);
const gateway=new Gateway(provider);const features=new FeatureRunner(provider,40,await PublicEvidenceTools.bundled('../..'));const seen=new Set<string>();
createServer(async(req,res)=>{
 res.setHeader('Cache-Control','no-store');res.setHeader('Content-Type','application/json');
 try{const owner=fixtureAuthorize(req.headers.authorization,secret,false);if(req.method!=='POST')throw new Error('method');let body='';for await(const chunk of req){body+=chunk;if(Buffer.byteLength(body)>(req.url==='/v1/features'?6000000:96000))throw new Error('payload');}const input:unknown=JSON.parse(body);
 if(req.url==='/v1/intents'){
 const r=intentRequest.parse(input);const key=owner+':'+r.requestID;
 if(seen.has(key)||seen.size>=100)throw new Error('replay_or_quota');seen.add(key);
 const controller=new AbortController();req.on('aborted',()=>controller.abort());res.on('close',()=>{if(!res.writableEnded)controller.abort()});
 const proposal=await interpreter.interpret(r,AbortSignal.any([controller.signal,AbortSignal.timeout(30000)]));
 res.end(JSON.stringify({status:'completed',requestID:r.requestID,proposal}));return;
 }
 if(req.url==='/v1/features'){
 const r=z.object({contractVersion:z.literal('dryrun.ai/1'),requestID:z.string().min(1).max(120),synthetic:z.literal(true),role:z.enum(['preparation','resources','home','stress','council']),context:featureContext,images:z.array(z.unknown()).max(4).default([])}).strict().parse(input);
 const key=owner+':'+r.requestID;if(seen.has(key)||seen.size>=100)throw new Error('replay_or_quota');seen.add(key);
 const controller=new AbortController();req.on('aborted',()=>controller.abort());res.on('close',()=>{if(!res.writableEnded)controller.abort()});
 const proposal=r.role==='council'?await features.council(r.context,controller.signal):await features.run(r.role,r.context,AbortSignal.any([controller.signal,AbortSignal.timeout(60000)]),r.images);
 res.end(JSON.stringify({status:'completed',contractVersion:'dryrun.ai/1',requestID:r.requestID,householdRevision:r.context.household.revision,proposal}));return;
 }
 const result=req.url==='/v1/operations'?await gateway.start(owner,input):req.url==='/v1/continue'?await gateway.resume(owner,input):req.url==='/v1/cancel'&&typeof input==='object'&&input!==null&&'token'in input&&typeof input.token==='string'?gateway.cancel(owner,input.token):{status:'rejected',reason:'unknown_endpoint'};
 res.end(JSON.stringify(result));}catch{res.statusCode=400;res.end(JSON.stringify({status:'rejected',reason:'invalid_or_unauthorized_request'}));}
}).listen(Number(process.env.PORT??8788),'127.0.0.1');
