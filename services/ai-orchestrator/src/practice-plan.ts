import {z} from 'zod';
import {configuredProviderConsent,scopeProvider,servedProviderID,type AgentProvider,type ServedBy} from './provider.js';

/**
 * practicePlan: ONE model call words a whole four-situation practice set. The host (Core) sends only compact
 * candidates it can set up and score; the model picks one candidate per competency, writes the question, option labels
 * and per-option feedback. Commands, credit and consequences never leave Core; the phone re-adopts the proposal with
 * Core validation and falls back to its deterministic plan on any rejection.
 */
const id=z.string().min(1).max(120);
const competency=z.enum(['initialResponse','adaptation','communication','continuity']);
const hazard=z.enum(['home-fire','tornado','flash-flood','freeze-power-loss','heat-grid-strain','water-outage']);
export const practicePlanRequest=z.object({contractVersion:z.literal('dryrun.ai/1'),requestID:id,synthetic:z.literal(true),
 providerConsent:z.array(z.enum(['gemini','groq','codex'])).min(1).max(3).optional(),
 context:z.object({contractVersion:z.literal('dryrun.practice-plan/1'),locale:z.literal('en'),attemptIndex:z.number().int().min(0).max(10000),
  order:z.array(competency).length(4),
  // Plain-language household facts only (roles and needs), never names, addresses or internal IDs.
  household:z.array(z.string().min(1).max(160)).max(12),
  previousCandidateIDs:z.array(id).max(16).default([]),
  candidates:z.array(z.object({id,competency,hazard,situation:z.string().min(1).max(200),
   options:z.array(z.object({id,action:z.string().min(1).max(160),outcome:z.enum(['credited','notCredited','notAssessed'])}).strict()).min(2).max(8)}).strict()).min(4).max(40)}).strict()}).strict();
export type PracticePlanRequest=z.infer<typeof practicePlanRequest>;
const text=(max:number)=>z.string().min(1).max(max);
export const practicePlanOutput=z.object({situations:z.array(z.object({competency,candidateID:id,prompt:text(240),
 options:z.array(z.object({id,label:text(120),feedback:text(280)}).strict()).min(2).max(6)}).strict()).length(4)}).strict();
export type PracticePlanOutput=z.infer<typeof practicePlanOutput>;

const instruction='DryRun practicePlan prompt/1. Plan a fresh four-question household emergency practice set in one answer; answer directly without deliberating. '+
 'For each competency in context.order, in that order, choose exactly one candidate of that competency (prefer hazards not in previousCandidateIDs and a varied mix of hazards). '+
 'Write prompt: one short plain question a family member reads (under 200 characters) describing the situation and asking what to do now. '+
 'Choose 2 to 4 of that candidate\'s option ids, always including every credited option; keep notCredited options as realistic alternatives. '+
 'label: a short action phrase (under 80 characters). feedback: one or two plain sentences on why this choice helps or what to watch for, consistent with its outcome. '+
 'Plain English. Never use internal IDs, names or brand names. It is practice: never promise safety or that a plan will work.';

const internalID=/\b(?:evt|choice|eq|bk|p|sp|contact|person|room)[.-][A-Za-z0-9]/;
const assurance=/\b(?:will|would|are|is|be|stay|keeps?)\s+(?:\w+\s+){0,2}(?:safe|protected|fine|okay|survive)\b/i;

/** Host validation of the model's whole plan against the request's candidates. Throws an allowlisted code. */
export function validatePracticePlan(output:unknown,request:PracticePlanRequest['context']):PracticePlanOutput {
 const plan=practicePlanOutput.parse(output);
 if(plan.situations.map(s=>s.competency).join()!==request.order.join())throw new Error('practice_order');
 if(new Set(plan.situations.map(s=>s.candidateID)).size!==4)throw new Error('practice_duplicate_candidate');
 for(const s of plan.situations){
  const candidate=request.candidates.find(c=>c.id===s.candidateID&&c.competency===s.competency);
  if(!candidate)throw new Error('practice_unknown_candidate');
  const ids=s.options.map(o=>o.id);
  if(new Set(ids).size!==ids.length||!ids.every(i=>candidate.options.some(o=>o.id===i)))throw new Error('practice_unknown_option');
  if(!candidate.options.filter(o=>o.outcome==='credited').some(o=>ids.includes(o.id)))throw new Error('practice_missing_credited');
  for(const t of [s.prompt,...s.options.flatMap(o=>[o.label,o.feedback])]){
   if(internalID.test(t))throw new Error('internal_id');
   if(assurance.test(t)&&!/\b(?:not|never|no)\b/i.test(t))throw new Error('unsupported_assurance');
  }
 }
 return plan;
}

/** One provider turn, no tools, strict schema. One repair turn on a validation failure, then the caller falls back. */
export async function runPracticePlan(provider:AgentProvider,request:PracticePlanRequest,signal:AbortSignal,timeoutMs=30000):Promise<{plan:PracticePlanOutput;servedBy:ServedBy}>{
 const consent=configuredProviderConsent(provider,request.providerConsent);
 const scoped=scopeProvider(provider,{signal,providers:consent,capability:'privateText',maximumCalls:3,timeoutMs});
 const history:import('./provider.js').History=[{type:'user_input',content:[{type:'text',text:JSON.stringify(request.context)}]}];
 const outputSchema=z.toJSONSchema(practicePlanOutput) as Record<string,unknown>;
 let lastError='practice_validation';
 for(let attempt=0;attempt<2;attempt++){
  const reply=await scoped.turn({history,instruction,tools:[],toolMode:'none',outputSchema,signal});
  signal.throwIfAborted();
  try{return {plan:validatePracticePlan(JSON.parse(reply.text),request.context),servedBy:servedProviderID(scoped)??'host'};}
  catch(error){
   lastError=error instanceof Error&&/^[a-z_]{1,40}$/.test(error.message)?error.message:'practice_validation';
   history.push(...reply.steps,{type:'user_input',content:[{type:'text',text:`Host rejected the plan (${lastError}). Return a corrected complete plan.`}]});
  }
 }
 throw new Error(lastError);
}
