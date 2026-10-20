import {GoogleGenAI} from '@google/genai';
import {evaluationKey} from './eval-key.js';
import {mkdir,writeFile} from 'node:fs/promises';
// Synthetic, bounded entitlement probe; no automatic billing, retry or account mutation.
const key=await evaluationKey(),ai=new GoogleGenAI({apiKey:key});
const backup=process.env.DRYRUN_USE_BACKUP_KEY==='1';
const model=process.env.DRYRUN_RESEARCH_MODEL??'gemini-2.5-flash';
if(!['gemini-2.5-flash','gemini-3.8-flash','gemini-3.1-flash-lite'].includes(model))throw new Error('unsupported_model');
let result:unknown;
try {
 const response=await ai.interactions.create({model,store:false,input:'Find one official Denver city cooling-resource page using Search and inspect it with URL Context. Synthetic public research only. Cite your source; do not claim current activation.',tools:[{type:'google_search'},{type:'url_context'}],generation_config:{max_output_tokens:500}},{signal:AbortSignal.timeout(30000),retries:{strategy:'none'}});
 result={status:'completed',usage:response.usage,steps:response.steps?.map(s=>s.type),note:'Entitlement probe only; not a qualified resource comparison or app acceptance pass'};
}catch(error){
 const status=typeof error==='object'&&error&&'status'in error?error.status:null;
 // Exact known secret and key-shaped strings are removed before printing or saving.
 const message=(error instanceof Error?error.message:'unknown').replaceAll(key,'[REDACTED]').replace(/AIza[\w-]+/g,'[REDACTED]').slice(0,4000);
 result={status:'failed',httpStatus:status,message};process.exitCode=1;
}
const artifact={synthetic:true,recordedAt:new Date().toISOString(),keySlot:backup?'backup':'primary',model,result};
await mkdir('../../artifacts/ai/provider-entitlement',{recursive:true});
await writeFile(`../../artifacts/ai/provider-entitlement/${backup?'backup':'primary'}-${model}.json`,JSON.stringify(artifact,null,2)+'\n');
console.log(JSON.stringify(artifact));
