import {GeminiPrimaryFallback} from './provider-fallback.js';
import {configuredGroqClients} from './groq.js';
import {GroqResourceDiscovery} from './groq-discovery.js';
import {ResourceDiscovery} from './resource-discovery.js';
import {IntentInterpreter} from './intents.js';
import {PublicEvidenceTools} from './evidence.js';
import {createServer} from 'node:http';
import {Gateway,fixtureAuthorize} from './gateway.js';
import {FeatureRunner} from './features.js';
import {createAIRequestHandler} from './http.js';
import {GeminiProvider,SpendBudget,type AgentProvider} from './provider.js';
if(process.env.NODE_ENV==='production')throw new Error('production_authorization_provider_required');
const secret=process.env.DRYRUN_DEV_TOKEN??'';
if(secret.length<24)throw new Error('local_fixture_token_required');
const provider=new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??'',process.env.DRYRUN_MODEL,new SpendBudget(),{research:process.env.DRYRUN_RESEARCH_MODEL??'gemini-3.8-flash',home:process.env.DRYRUN_HOME_MODEL??'gemini-3.8-flash',adjudication:process.env.DRYRUN_ASSESSMENT_MODEL??'gemini-3.1-flash-lite'});
const groqClients=process.env.GROQ_API_KEY?configuredGroqClients(process.env.GROQ_API_KEY,{extractorModel:process.env.DRYRUN_GROQ_EXTRACTOR_MODEL}):undefined;
const groq=groqClients?.client,extractor=groqClients?.extractor;
const privateProvider=groq?new GeminiPrimaryFallback(provider,groq):provider;
const interpreter=new IntentInterpreter(privateProvider);
// DRYRUN_DIAGNOSTICS=1 (synthetic development only): log each director turn's tool names/arguments (IDs, minutes)
// and the start of its JSON reply, so a validation failure can be traced. Never request context or headers.
const directorProvider:AgentProvider=process.env.DRYRUN_DIAGNOSTICS==='1'?{async turn(input){
 const reply=await privateProvider.turn(input);
 console.log('director turn',JSON.stringify({calls:reply.calls.map(c=>({name:c.name,arguments:c.arguments})),reply:reply.text.slice(0,700)}));
 return reply;
}}:privateProvider;
const gateway=new Gateway(directorProvider);const features=new FeatureRunner(privateProvider,40,await PublicEvidenceTools.bundled('../..'));
const discovery=new ResourceDiscovery(provider,12,()=>new Date(),groq?new GroqResourceDiscovery(groq,()=>new Date(),extractor):undefined);
// Loopback unless DRYRUN_HOST is set for a wired-iPhone development session on a trusted local network.
// Synthetic-only requests, the fixture token and the spend budget still apply; production fails closed above.
const host=process.env.DRYRUN_HOST??'127.0.0.1';
const handler=createAIRequestHandler({gateway,features,interpreter,discovery,authorize:header=>fixtureAuthorize(header,secret,false)});
// Access log for development: path, status and duration only. Never headers, bodies or household fields.
createServer((req,res)=>{const started=Date.now();res.once('finish',()=>console.log(`${new Date().toISOString()} ${req.method} ${req.url} ${res.statusCode} ${Date.now()-started}ms outcomes=${gateway.metrics.outcomes.slice(-1).join(',')}`));return handler(req,res);}).listen(Number(process.env.PORT??8788),host);
