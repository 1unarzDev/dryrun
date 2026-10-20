import {readFile} from 'node:fs/promises';
import {GroqClient} from '../src/groq.js';
import {GeminiPrimaryFallback} from '../src/provider-fallback.js';
import {Gateway} from '../src/gateway.js';

// Inspect actual request size without a network request or secret.
const historical=JSON.parse(await readFile(process.env.DRYRUN_AUDIT_TRACE??'../../artifacts/ai/six-hazard/runs/2026-10-20T03-29-19-573Z/water-outage.json','utf8'));
const context=historical.trace.find((t:any)=>t.context).context;
let inspected=false;
const provider=new GeminiPrimaryFallback({async turn(){throw new Error('provider_rate_limited');}},new GroqClient('synthetic',undefined,async(_url,request)=>{
 const body=JSON.parse(String(request?.body));inspected=true;
 console.log(JSON.stringify({synthetic:true,networkCalls:0,totalBytes:Buffer.byteLength(String(request?.body)),instructionBytes:body.messages[0].content.length,contextBytes:body.messages[1].content.length,tools:body.tools?.map((t:any)=>({name:t.function.name,bytes:JSON.stringify(t).length})),outputSchemaBytes:JSON.stringify(body.response_format??{}).length}));return new Response('{}',{status:400});
}));
await new Gateway(provider).start('synthetic-audit',{contractVersion:'dryrun.ai/1',requestID:'audit',role:'director',synthetic:true,providerConsent:['gemini','groq'],context});if(!inspected)throw new Error('no_request');
