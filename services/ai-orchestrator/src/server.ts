import {IntentInterpreter} from './intents.js';
import {PublicEvidenceTools} from './evidence.js';
import {createServer} from 'node:http';
import {Gateway,fixtureAuthorize} from './gateway.js';
import {FeatureRunner} from './features.js';
import {createAIRequestHandler} from './http.js';
import {developmentListenHost} from './listen-config.js';
import {AppAttestVerifier,InstallationAuth} from './app-attest.js';
import {GroqResourceDiscovery} from './groq-discovery.js';
import {ResourceDiscovery} from './resource-discovery.js';
import {configuredProviders} from './provider-routing.js';
import {quotaLimitsFromEnv} from './owner-window-quota.js';
const production=process.env.NODE_ENV==='production';
const attestAppID=process.env.DRYRUN_APPATTEST_APP_ID;
const attest=attestAppID?new InstallationAuth(new AppAttestVerifier(attestAppID,
 production||process.env.DRYRUN_APPATTEST_ENV==='production'?'production':'development'),process.env.DRYRUN_SESSION_SECRET??''):undefined;
if(production&&!attest)throw new Error('production_authorization_provider_required');
const secret=production?'':process.env.DRYRUN_DEV_TOKEN??'';
if(!production&&secret.length<24)throw new Error('local_fixture_token_required');
// One routing layer for every operation: Codex primary when DRYRUN_PROVIDER=codex, then Gemini, then Groq.
const {gemini,groqClients,codex,provider}=await configuredProviders();
console.log(`provider_chain ${codex?'codex,':''}gemini${groqClients?',groq':''}`);
// Warm Codex runtimes at gateway start, so the first Beacon request skips process spawn and handshake.
if(codex){void codex.prewarm();console.log(`codex_speed effort=${codex.speed.effort} director_effort=${codex.speed.directorEffort} service_tier=${codex.speed.serviceTier??'default'} warm=${codex.speed.warm}`);}
const interpreter=new IntentInterpreter(provider);
const limits=quotaLimitsFromEnv();
console.log(`quota_window feature_turns=${limits.featureTurns} director_starts=${limits.directorStarts} director_turns=${limits.directorTurns} http_requests=${limits.httpRequests}`);
const gateway=new Gateway(provider,undefined,limits.directorTurns,limits.directorStarts);const features=new FeatureRunner(provider,limits.featureTurns,await PublicEvidenceTools.bundled('../..'),{prepackContext:process.env.DRYRUN_PREPACK_CONTEXT!=='0'});
const discovery=new ResourceDiscovery(gemini,12,()=>new Date(),groqClients?new GroqResourceDiscovery(groqClients.client,()=>new Date(),groqClients.extractor):undefined);
createServer(createAIRequestHandler({gateway,features,interpreter,attest,discovery,maximumRequests:limits.httpRequests,authorize:header=>{
 if(attest&&header?.startsWith('Bearer v1.'))return attest.authorize(header);
 return fixtureAuthorize(header,secret,production);
}})).listen(Number(process.env.PORT??8788),developmentListenHost());
