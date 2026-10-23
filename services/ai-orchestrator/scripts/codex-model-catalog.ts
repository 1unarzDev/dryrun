/** Prints only model catalog metadata (ids, reasoning efforts, service tiers) from the pinned runtime. No model output. */
import {readFileSync} from 'node:fs';
import {parseEnv} from 'node:util';
import {launchCodex} from '../src/codex-runtime.js';
import {serviceEnvFile} from '../src/codex-config.js';

const key=process.env.CODEX_LB_API_KEY??parseEnv(readFileSync(serviceEnvFile(),'utf8')).CODEX_LB_API_KEY??'';
const connection=await launchCodex(key,'gpt-6.1-sol',AbortSignal.timeout(30_000));
connection.onMessage=()=>{};
await connection.request('initialize',{clientInfo:{name:'dryrun_catalog',version:'1.0.0'},capabilities:{experimentalApi:true}});
connection.notify('initialized');
const listed=await connection.request('model/list',{});
for(const model of listed?.data??[])console.log(JSON.stringify({model:model.model,efforts:(model.supportedReasoningEfforts??[]).map((e:any)=>e.reasoningEffort),defaultEffort:model.defaultReasoningEffort,serviceTiers:(model.serviceTiers??[]).map((t:any)=>t.id),speedTiers:model.additionalSpeedTiers??[]}));
await connection.close();
