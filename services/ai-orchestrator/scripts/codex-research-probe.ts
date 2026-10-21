/** REVIEWER ONLY; genuine public search/open capability, no private family context. */
import {readFile} from 'node:fs/promises';
import {parseEnv} from 'node:util';
import {launchCodex} from '../src/codex-runtime.js';
const env=parseEnv(await readFile(new URL('../.env',import.meta.url),'utf8'));
const key=process.env.CODEX_LB_API_KEY??env.CODEX_LB_API_KEY;if(!key)throw new Error('missing_provider_secret');
const abort=new AbortController();const timer=setTimeout(()=>abort.abort(),75_000);
const connection=await launchCodex(key,'gpt-6.1-sol',abort.signal,{webSearch:'live'});
let success=false;let done!:()=>void;const ended=new Promise<void>(resolve=>{done=resolve});
connection.onFailure=()=>{console.log(JSON.stringify({event:'transport_failed'}));done();};
connection.onMessage=m=>{console.log(JSON.stringify(m));if(m.id!==undefined&&m.method)abort.abort();if(m.method==='turn/completed'){success=m.params?.turn?.status==='completed';done();}};
try{
 await connection.request('initialize',{clientInfo:{name:'dryrun_public_research_probe',version:'1'},capabilities:{experimentalApi:true}});connection.notify('initialized');
 const thread=await connection.request('thread/start',{model:'gpt-6.1-sol',modelProvider:'dryrun_lb',approvalPolicy:'never',sandbox:'read-only',ephemeral:true,baseInstructions:'DryRun synthetic public-research compatibility probe. Only public planning information; no private household records. You must genuinely search the web, then OPEN selected source pages. Emitted URLs or remembered content are not evidence. If hosted search or page-open is unavailable, explicitly report unavailable and do not answer from memory. No current hazard-safety, business stock or shelter activation claims.'});
 const prompt='For planning in Stephenville, Texas, search official city/county utility and emergency-management sources. Discover at least two candidates, open the selected actual pages, and compare which role each has for preparing for a future water outage. Identify supported contact/service information, source publisher/URL, retrieval date and material unknowns. This is preparation, not an active emergency. Do not claim any route or destination is safe or activated. Distinguish verified page content from assumptions. Be concise.';
 console.log(JSON.stringify({event:'exact_public_input',prompt,webSearch:'live',privateContext:false}));
 await connection.request('turn/start',{threadId:thread.thread.id,input:[{type:'text',text:prompt,text_elements:[]}]});await ended;
 console.log(JSON.stringify({event:'research_probe_receipt',successfulTerminal:success}));if(!success)process.exitCode=1;
}finally{clearTimeout(timer);await connection.close();}
