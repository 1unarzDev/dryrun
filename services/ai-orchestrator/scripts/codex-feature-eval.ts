/** REVIEWER-ONLY. Exact native synthetic inputs and actual responses go to protected capture. */
import {readFile,writeFile} from 'node:fs/promises';
import {randomBytes,randomUUID} from 'node:crypto';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {configuredCodexProvider} from '../src/codex-config.js';
import {Gateway,fixtureAuthorize} from '../src/gateway.js';
import {FeatureRunner,featureContext} from '../src/features.js';
import {IntentInterpreter} from '../src/intents.js';
import {createAIRequestHandler} from '../src/http.js';

const directory=process.argv[2]??'/private/tmp/dryrun-native-gateway-inputs';
const repeats=Number(process.argv[3]??2);if(!Number.isInteger(repeats)||repeats<1||repeats>3)throw new Error('bounded_repeats_required');
process.env.DRYRUN_CODEX_CAPABILITIES_FILE??=new URL('../profiles/codex-local-synthetic.json',import.meta.url).pathname;
const condition=process.argv[4]??'baseline';if(!['baseline','investigation'].includes(condition))throw new Error('unknown_condition');
const provider=await configuredCodexProvider();const secret=randomBytes(32).toString('base64url');
const server=createServer(createAIRequestHandler({gateway:new Gateway(provider),features:new FeatureRunner(provider,100,undefined,{preparationInvestigation:condition==='investigation'}),interpreter:new IntentInterpreter(provider),authorize:header=>fixtureAuthorize(header,secret,false)}));
server.listen(0,'127.0.0.1');await once(server,'listening');const address=server.address();if(!address||typeof address==='string')throw new Error('listen_failed');
let failed=0;
// Optional engineering-visible receipt: allowlisted machine fields only, never request/response content.
const code=(value:unknown)=>typeof value==='string'&&/^[a-z_0-9]{1,48}$/.test(value)?value:value===undefined?undefined:'other';
const attempts:Record<string,unknown>[]=[];
try{
 for(const family of ['oak','lake','pine'])for(let repetition=1;repetition<=repeats;repetition++){
  const request=JSON.parse(await readFile(directory+'/'+family+'.json','utf8'));request.requestID=randomUUID();request.context.locale??='en';featureContext.parse(request.context);
  const runID=randomUUID();const start=Date.now();
  console.log(JSON.stringify({event:'exact_execution_input',runID,family,repetition,request,promptVersion:condition==='investigation'?'preparation/15+preparation-investigation/1':'preparation/15',capabilities:provider.capabilities}));
  try{
   const response=await fetch(`http://127.0.0.1:${address.port}/v1/features`,{method:'POST',headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json'},body:JSON.stringify(request),signal:AbortSignal.timeout(95_000)});
   const body=await response.json();console.log(JSON.stringify({event:'protected_feature_response',runID,status:response.status,body,elapsedMS:Date.now()-start}));
   if(!response.ok||body.status!=='completed')failed++;
   attempts.push({runID,family,repetition,condition,httpStatus:response.status,status:code(body?.status),reason:code(body?.reason),elapsedMS:Date.now()-start});
  }catch{failed++;attempts.push({runID,family,repetition,condition,status:'transport_or_deadline',elapsedMS:Date.now()-start});console.log(JSON.stringify({event:'feature_attempt_failure',runID,reason:'transport_or_deadline',elapsedMS:Date.now()-start}));}
 }
 console.log(JSON.stringify({event:'complete_attempt_receipt',attempts:3*repeats,failed,promptVersion:condition==='investigation'?'preparation/15+preparation-investigation/1':'preparation/15'}));
 if(failed)process.exitCode=1;
}finally{server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));
 if(process.env.DRYRUN_SAFE_RECEIPT)await writeFile(process.env.DRYRUN_SAFE_RECEIPT,JSON.stringify({receipt:'dryrun.codex-feature-eval/1',inputDirectory:directory,condition,promptVersion:condition==='investigation'?'preparation/15+preparation-investigation/1':'preparation/15',model:provider.capabilities.model,runtime:provider.capabilities.runtimeVersion,attempts},null,1),{mode:0o600});
}
