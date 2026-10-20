import {GroqClient,ProviderFailure} from '../src/groq.js';
import {GeminiPrimaryFallback} from '../src/provider-fallback.js';
import type {AgentProvider} from '../src/provider.js';
import {evaluationKey,groqEvaluationKey} from './eval-key.js';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {Host} from './host.js';
import {Gateway,directorPrompt} from '../src/gateway.js';
import {GeminiProvider,SpendBudget} from '../src/provider.js';
import {minimizedSnapshot,minimizedAssistance,hazardExperience} from '../src/contracts.js';
import {executeDirectorTool} from './director-tools.js';
const live=process.argv.includes('--live');
const runID=new Date().toISOString().replace(/[:.]/g,'-');
const host=new Host();
const budget=new SpendBudget(Number(process.env.DRYRUN_MAX_USD??1.5));
const providerResponses:unknown[]=[];
const groqFallback=process.env.DRYRUN_PROVIDER==='groq-fallback';
const rawProvider:AgentProvider|undefined=live&&groqFallback?new GeminiPrimaryFallback({async turn(){throw new Error('provider_rate_limited');}},new GroqClient(await groqEvaluationKey(),process.env.DRYRUN_GROQ_MODEL,fetch,raw=>providerResponses.push(raw))):live?new GeminiProvider(await evaluationKey(),process.env.DRYRUN_MODEL??'gemini-3.1-flash-lite',budget):undefined;
const providerTurns:unknown[]=[];
function loggedProvider(raw:AgentProvider):AgentProvider{return {scope:raw.scope?options=>loggedProvider(raw.scope!(options)):undefined,get attemptGeneration(){return raw.attemptGeneration;},get attemptID(){return raw.attemptID;},async turn(input){const requestHashes={instruction:createHash('sha256').update(input.instruction).digest('hex'),outputSchema:createHash('sha256').update(JSON.stringify(input.outputSchema??{})).digest('hex'),tools:createHash('sha256').update(JSON.stringify(input.tools)).digest('hex')};try{const r=await raw.turn(input);providerTurns.push({requestHashes,text:r.text,calls:r.calls.map(c=>({name:c.name,arguments:c.arguments})),usage:r.usage});return r;}catch(error){providerTurns.push({requestHashes,error:error instanceof Error?error.message:'provider_error',...(error instanceof ProviderFailure?{kind:error.kind,httpStatus:error.status,retryAfterMs:error.retryAfterMs,diagnostic:error.diagnostic}:{})});throw error;}}};}
const gateway=rawProvider?new Gateway(loggedProvider(rawProvider),()=>Date.now(),80):undefined;
const ids=['home-fire','tornado','flash-flood','freeze-power-loss','heat-grid-strain','water-outage'];
const selected=process.env.DRYRUN_HAZARD;
const requireFinish=process.env.DRYRUN_REQUIRE_FINISH==='1';
const maxTurns=Number(process.env.DRYRUN_MAX_TURNS??(requireFinish?'8':'2'));
assert(Number.isInteger(maxTurns)&&maxTurns>=2&&maxTurns<=8,'turn_budget');
const reports:unknown[]=[];
await mkdir('../../artifacts/ai/six-hazard',{recursive:true});
try {
 const base=await host.request({op:'initialize',scenarioID:'home-fire'});
 const documented=process.env.DRYRUN_REPRESENTATIVE==='documented'?JSON.parse(await readFile('../../fixtures/ai/six-hazard-mechanics.json','utf8')):undefined;
 const household=documented?.household??base.session.initial.household;
 const commonHome=documented?.home??base.session.initial.home;
 household.housing.waterSource='municipal';
 household.transport={vehicles:[{id:'exercise-car',seats:8,wheelchairAccessible:{value:true,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]},isElectric:false}],alternatives:[],destinations:[{id:'exercise-alternative',kind:'friendOrFamilyHome',label:'Synthetic agreed alternative',conditionsConfirmed:{value:true,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]},acceptsPets:{value:true,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]},stepFreeAccess:{value:true,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]}}]};
 household.people.forEach((p:any)=>p.sleepingSpaceID='sp-bed1');
 for(const id of ids.filter(id=>!selected||id===selected)){
  providerTurns.length=0;providerResponses.length=0;
  const outcomeStart=gateway?.metrics.outcomes.length??0;
  const validationStart=gateway?.metrics.validationFailures.length??0;
  const trace:any[]=[];let status='passed',finished=false;
  try {
   const original=await host.request({op:'initialize',scenarioID:id});
   let state=await host.request({op:'initialize',input:{...original.session.initial,household,home:commonHome}});
   trace.push({initial:state});
   assert.equal(hazardExperience.parse(state.receipt.experience).hazard,state.session.directorPolicy.permittedHazardFamilies[0]);
   for(let turn=0;turn<maxTurns;turn++){
    if(live){
     const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home?.revision??0};
     const context={binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),experience:state.receipt.experience,household:state.householdContext,homeScene:state.homeScene,profiles:state.directorProfiles,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending,lastAction:state.lastAction,recentActions:state.recentActions,learningObjectives:['Offer concrete household actions and respond to their computed effects; teach this selected hazard.']};
     let result:any=await gateway!.start(`synthetic-${id}`,{contractVersion:'dryrun.ai/1',requestID:`${id}-${turn}`,role:'director',synthetic:true,...(groqFallback?{providerConsent:['gemini','groq']}:{}),context});
     trace.push({context,result:withoutToken(result)});
     while(result.status==='needs_client_tools'){
      const call=result.calls[0],tool=await executeDirectorTool(host,state,binding,call);
      trace.push({tool:call,result:tool.result});
      result=await gateway!.resume(`synthetic-${id}`,{token:result.token,binding,callID:call.id,result:tool.result});trace.push({result:withoutToken(result)});
     }
     assert.equal(result.status,'completed','actual gateway did not complete');
     state=await host.request({op:'directorCommit',session:state.session,proposal:result.proposal,binding});trace.push({committed:state});
     if(state.receipt.finished)break;
     const accepted:any[]=[];
     for(const action of result.proposal.suggestedActions??[]){
      const commit={id:`selected-${id}-${turn}`,actor:'user',baseRevision:state.receipt.revision,commands:action.commands};
      try {const preview=await host.request({op:'preview',session:state.session,commit});accepted.push({action,commit,preview});}
      catch {trace.push({infeasibleSuggestion:action});}
     }
     assert(accepted.length>0,'no offered action passed actual host validation');
     assert.equal(accepted.length,result.proposal.suggestedActions?.length,'every offered action must pass actual host validation');
     trace.push({alternatives:accepted});
     state=await host.request({op:'commit',session:state.session,commit:accepted[0].commit});trace.push({submittedAction:accepted[0].action,committed:state});
    } else {
     state=await host.request({op:'fallback',session:state.session});trace.push({fallback:state});
     if(state.receipt.directorState?.awaitingUserAction){
      // A recorded concept attempt resumes the same state; offline never defaults a physical action.
      state=await host.request({op:'commit',session:state.session,commit:{id:`offline-attempt-${turn}`,actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'unsupported'}]}});
     }
    }
   }
   finished=state.receipt.finished;
   if(requireFinish)assert(finished,'budget ended before a committed finish; continuation is not a completed debrief');
   const replay=await host.request({op:'query',session:JSON.parse(JSON.stringify(state.session))});
   assert.equal(replay.receipt.contextDigest,state.receipt.contextDigest);assert.deepEqual(replay.receipt.experience,state.receipt.experience);
   trace.push({replayDigest:replay.receipt.contextDigest,finalExperience:state.receipt.experience});
  }catch(error){status='failed';trace.push({failure:error instanceof Error?error.message:'unknown'});}
  const artifact={representative:documented?'documented-common-household':'recorded-unknowns-common-household',synthetic:true,directorPrompt,runID,keySlot:live?(groqFallback?'groq':process.env.DRYRUN_USE_BACKUP_KEY==='1'?'backup':'primary'):null,mode:live?'live-model-tested':'offline-host-tested',hazard:id,status,finished,requireFinish,maxTurns,evaluationScope:requireFinish?'bounded completion and debrief':'bounded executable continuation only',recordedAt:new Date().toISOString(),model:live?(groqFallback?(process.env.DRYRUN_GROQ_MODEL??'openai/gpt-oss-120b'):(process.env.DRYRUN_MODEL??'gemini-3.1-flash-lite')):null,provider:groqFallback?'groq-fallback-injected-primary429':'gemini',sdk:groqFallback?'native-fetch-no-retry':'2.30.0',providerTurns:[...providerTurns],providerResponses:[...providerResponses],outcomes:[...(gateway?.metrics.outcomes.slice(outcomeStart)??[])],validationFailures:[...(gateway?.metrics.validationFailures.slice(validationStart)??[])],trace};
  await writeFile(`../../artifacts/ai/six-hazard/${id}-${groqFallback?'groq-fallback':live?'live':'offline'}.json`,JSON.stringify(artifact,null,2)+'\n');
  await mkdir('../../artifacts/ai/six-hazard/runs/'+runID,{recursive:true});
  await writeFile(`../../artifacts/ai/six-hazard/runs/${runID}/${id}.json`,JSON.stringify(artifact,null,2)+'\n');
  reports.push({hazard:id,status,finished,requireFinish,maxTurns});console.log(JSON.stringify({hazard:id,status}));
 }
 await writeFile(`../../artifacts/ai/six-hazard/${selected?selected+'-':''}${live?'live':'offline'}-report.json`,JSON.stringify({synthetic:true,directorPrompt,runID,keySlot:live?(groqFallback?'groq':process.env.DRYRUN_USE_BACKUP_KEY==='1'?'backup':'primary'):null,reports,calls:gateway?.metrics.calls??0,usage:gateway?.metrics.usage??[],budgetUSD:budget.limitUSD,accountedUSD:budget.spentUSD,native:'pending',humanReview:'pending'},null,2)+'\n');
 if(reports.some((r:any)=>r.status!=='passed'))process.exitCode=1;
}finally{host.close();}
function withoutToken(result:any){const {token,...safe}=result;return safe;}
