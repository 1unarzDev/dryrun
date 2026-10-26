/** Engineering-visible TIMING RECEIPTS ONLY for live Codex preparation and director turns. Never prints model text,
 * proposals, tool arguments or records: each line carries role, run index, wall-clock legs, status and servedBy.
 * Run through scripts/review/firewall.py capture.
 *
 * Usage: tsx scripts/codex-speed-receipts.ts <preparation|director> <runs 1-5> [input.json]
 *   preparation reads the synthetic native preparation input (default /private/tmp/dryrun-native-gateway-inputs/oak.json).
 *   director initializes the synthetic water-outage scenario in the Core host and runs one director turn
 *   (start + client-tool legs until completion). */
import {readFileSync} from 'node:fs';
import {parseEnv} from 'node:util';
import {serviceEnvFile} from '../src/codex-config.js';

const role=process.argv[2]??'preparation';const runs=Number(process.argv[3]??3);
if(!['preparation','director'].includes(role)||!Number.isInteger(runs)||runs<1||runs>5)throw new Error('usage');
// Service secrets are loaded by path into this process only; never echoed.
const service=parseEnv(readFileSync(serviceEnvFile(),'utf8'));
for(const name of ['CODEX_LB_API_KEY','GOOGLE_AI_STUDIO_KEY','GROQ_API_KEY'])if(!process.env[name]&&service[name])process.env[name]=service[name];
process.env.DRYRUN_PROVIDER='codex';
process.env.DRYRUN_CODEX_CAPABILITIES_FILE??=new URL('../profiles/codex-local-synthetic.json',import.meta.url).pathname;
const {configuredProviders}=await import('../src/provider-routing.js');
const {provider,codex}=await configuredProviders(process.env,()=>{});
const receipt=(value:Record<string,unknown>)=>console.log(JSON.stringify({receipt:'codex-speed/1',role,...value}));
receipt({event:'config',codex:!!codex,effort:process.env.DRYRUN_CODEX_EFFORT??'default',serviceTier:process.env.DRYRUN_CODEX_SERVICE_TIER??'default',warm:process.env.DRYRUN_CODEX_WARM??'default',prepack:process.env.DRYRUN_PREPACK_CONTEXT??'default'});
await codex?.prewarm?.();
const settle=Number(process.env.DRYRUN_SPEED_SETTLE_MS??0);if(settle)await new Promise(r=>setTimeout(r,settle));
const durations:number[]=[];
if(role==='preparation'){
 const {FeatureRunner}=await import('../src/features.js');
 const request=JSON.parse(readFileSync(process.argv[4]??'/private/tmp/dryrun-native-gateway-inputs/oak.json','utf8'));request.context.locale='en';
 // Older captured inputs predate the explicit binding; it is derived from the same synthetic snapshot.
 const snapshot=request.context.privateContext;
 if(snapshot&&!request.context.contextBinding)request.context.contextBinding={scope:snapshot.scope,revisions:snapshot.revisions,snapshotID:snapshot.snapshotID,...(snapshot.homeID?{homeID:snapshot.homeID}:{})};
 if(snapshot&&!snapshot.homeID){const geometry=snapshot.records.find((r:any)=>r.section==='home'&&r.sourcePath==='geometry')?.value;if(geometry?.id){snapshot.homeID=geometry.id;request.context.contextBinding.homeID=geometry.id;}}
 const runner=new FeatureRunner(provider,100,undefined,{prepackContext:process.env.DRYRUN_PREPACK_CONTEXT!=='0'});
 for(let run=0;run<runs;run++){
  const started=performance.now();let status='completed',servedBy:string|undefined;const callsBefore=runner.calls;
  try{const output=await runner.run('preparation',request.context,AbortSignal.timeout(90000),[],'synthetic-speed-owner');servedBy=runner.servedBy(output);}
  catch(error){status=error instanceof Error&&/^[a-z_]+$/.test(error.message)?error.message:'failed';}
  const ms=Math.round(performance.now()-started);if(status==='completed')durations.push(ms);
  receipt({event:'run',run,ms,status,servedBy,modelTurns:runner.calls-callsBefore});
 }
}else{
 const {Host}=await import('./host.js');const {Gateway}=await import('../src/gateway.js');
 const {minimizedSnapshot,minimizedAssistance}=await import('../src/contracts.js');const {executeDirectorTool}=await import('./director-tools.js');
 const host=new Host();const gateway=new Gateway(provider,undefined,100,100);
 try{
  for(let run=0;run<runs;run++){
   const state=await host.request({op:'initialize',scenarioID:'water-outage'});
   const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home?.revision??0};
   const context={binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),experience:state.receipt.experience,household:state.householdContext,homeScene:state.homeScene,profiles:state.directorProfiles,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending,lastAction:state.lastAction,recentActions:state.recentActions,learningObjectives:['Offer concrete household actions and respond to their computed effects; teach this selected hazard.']};
   const legs:number[]=[];const started=performance.now();let status='completed',servedBy:unknown;
   try{
    let leg=performance.now();
    let result:any=await gateway.start('synthetic-speed-owner',{contractVersion:'dryrun.ai/1',requestID:`speed-${Date.now()}-${run}`,role:'director',synthetic:true,context});
    legs.push(Math.round(performance.now()-leg));
    while(result.status==='needs_client_tools'){
     const call=result.calls[0],tool=await executeDirectorTool(host,state,binding,call);
     leg=performance.now();result=await gateway.resume('synthetic-speed-owner',{token:result.token,binding,callID:call.id,result:tool.result});legs.push(Math.round(performance.now()-leg));
    }
    status=String(result.status);servedBy=result.servedBy;
   }catch(error){status=error instanceof Error&&/^[a-z_]+$/.test(error.message)?error.message:'failed';}
   const ms=Math.round(performance.now()-started);if(status==='completed')durations.push(ms);
   receipt({event:'run',run,ms,legs,status,servedBy});
  }
 }finally{host.close?.();}
}
const sorted=[...durations].sort((a,b)=>a-b);
receipt({event:'summary',completed:sorted.length,p50:sorted.length?sorted[Math.floor((sorted.length-1)/2)]:null,max:sorted.at(-1)??null});
await codex?.shutdown?.();
process.exit(0);
