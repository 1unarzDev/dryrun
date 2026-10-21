/** Reviewer-only: preserve triggering notifications before adapter teardown. */
import {readFile} from 'node:fs/promises';
import {configuredCodexProvider} from '../../services/ai-orchestrator/src/codex-config.js';
import {FeatureRunner} from '../../services/ai-orchestrator/src/features.js';
process.env.DRYRUN_CODEX_CAPABILITIES_FILE=new URL('../../services/ai-orchestrator/profiles/codex-local-synthetic.json',import.meta.url).pathname;
const provider=await configuredCodexProvider();
const original=(provider as any).connect;
(provider as any).connect=async(...args:any[])=>{
 const connection=await original(...args);
 let handler=connection.onMessage;
 Object.defineProperty(connection,'onMessage',{get:()=>((message:any)=>{console.log(JSON.stringify({event:'protected_protocol',message}));handler(message);}),set:(value:any)=>{handler=value;},configurable:true});
 return connection;
};
const request=JSON.parse(await readFile('/private/tmp/dryrun-native-gateway-inputs/oak.json','utf8'));
request.context.locale='en';
console.log(JSON.stringify({event:'exact_execution_input',request}));
try{const output=await new FeatureRunner(provider,100).run('preparation',request.context,undefined,[],'synthetic-review-owner');console.log(JSON.stringify({event:'protected_feature_output',output}));}
catch{console.log(JSON.stringify({event:'feature_failure'}));process.exitCode=1;}
