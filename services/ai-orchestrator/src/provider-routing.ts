import {GeminiProvider,SpendBudget,type AgentProvider} from './provider.js';
import {configuredCodexProvider} from './codex-config.js';
import {GeminiPrimaryFallback,type CodexRoute} from './provider-fallback.js';
import {configuredGroqClients} from './groq.js';
import type {CodexProvider} from './codex-provider.js';

type Env=Record<string,string|undefined>;
/** Builds the one provider-routing layer every gateway operation uses (features, director, intents).
 * DRYRUN_PROVIDER=codex makes the attested server-side Codex runtime the primary, with Gemini then Groq as
 * capability/availability fallbacks; DRYRUN_PROVIDER=gemini (or unset) keeps the Gemini→Groq chain unchanged.
 * Public resource discovery stays on Gemini/Groq search until Codex research is attested (profile research=false). */
export async function configuredProviders(env:Env=process.env,log:(line:string)=>void=console.warn){
 const gemini=new GeminiProvider(env.GOOGLE_AI_STUDIO_KEY??'',env.DRYRUN_MODEL,new SpendBudget(),{research:env.DRYRUN_RESEARCH_MODEL??'gemini-3.8-flash',home:env.DRYRUN_HOME_MODEL??'gemini-3.8-flash',adjudication:env.DRYRUN_ASSESSMENT_MODEL??'gemini-3.1-flash-lite'});
 const groqClients=env.GROQ_API_KEY?configuredGroqClients(env.GROQ_API_KEY,{extractorModel:env.DRYRUN_GROQ_EXTRACTOR_MODEL}):undefined;
 let codex:CodexProvider|undefined;
 if(env.DRYRUN_PROVIDER==='codex'){
  try{codex=await configuredCodexProvider(env);}
  catch(error){
   const reason=error instanceof Error&&/^[a-z_]+$/.test(error.message)?error.message:'codex_configuration';
   // Production never serves the experimental runtime; elsewhere the gateway keeps serving Gemini/Groq, loudly.
   if(env.NODE_ENV==='production')throw error;
   log(`codex_unconfigured ${reason}: serving Gemini/Groq only`);
  }
 }
 const route:CodexRoute|undefined=codex?{provider:codex,images:codex.capabilities.images,research:codex.capabilities.research,turnMs:boundedMs(env.DRYRUN_CODEX_TURN_MS,45000),fallbackReserveMs:boundedMs(env.DRYRUN_FALLBACK_RESERVE_MS,25000)}:undefined;
 const provider:AgentProvider=groqClients||route?new GeminiPrimaryFallback(gemini,groqClients?.client,boundedMs(env.DRYRUN_PRIMARY_ATTEMPT_MS,45000),route):gemini;
 return {gemini,groqClients,codex,provider};
}
function boundedMs(value:string|undefined,fallback:number){const n=Number(value??fallback);return Number.isFinite(n)&&n>=1000&&n<=300000?n:fallback;}
