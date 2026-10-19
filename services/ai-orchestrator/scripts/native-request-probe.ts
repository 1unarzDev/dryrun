// Diagnostic: runs a Swift-built native director request (fixtures/ai/native-bridge) through the real Gateway and a
// live Gemini provider, executing requested tools from the matching Swift tool fixtures is NOT possible offline, so
// this stops at the first tool request and reports the provider outcome. Synthetic data only; prints no secrets.
import {readFileSync} from 'node:fs';
import {Gateway} from '../src/gateway.js';
import {GeminiProvider,type AgentProvider} from '../src/provider.js';
const name=process.argv[2]??'home-fire';
const request=JSON.parse(readFileSync(new URL(`../../../fixtures/ai/native-bridge/director-request-${name}.json`,import.meta.url),'utf8'));
request.requestID=`probe-${Date.now()}`;
const live=new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??'',process.env.DRYRUN_MODEL??'gemini-3.1-flash-lite');
const errors:string[]=[];
const provider:AgentProvider={async turn(input){
 try{const reply=await live.turn(input);console.log('provider turn ok',JSON.stringify({calls:reply.calls.map(c=>({name:c.name,arguments:c.arguments})),text:reply.text.slice(0,600)}));return reply;}
 catch(error){errors.push(String(error instanceof Error?error.message:error));throw error;}
}};
const gateway=new Gateway(provider);
const result:any=await gateway.start('probe',request);
console.log(JSON.stringify({status:result.status,reason:result.reason,call:result.calls?.[0]?.name,arguments:result.calls?.[0]?.arguments,outcomes:gateway.metrics.outcomes,providerErrors:errors},null,1));
