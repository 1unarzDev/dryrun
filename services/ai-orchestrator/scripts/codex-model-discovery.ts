/** Reviewer-only metadata probe. Run only through receipt-only firewall capture. */
import {readFile} from 'node:fs/promises';
import {parseEnv} from 'node:util';
import {codexEndpoint} from '../src/codex-runtime.js';
const env=parseEnv(await readFile(new URL('../.env',import.meta.url),'utf8'));
const key=process.env.CODEX_LB_API_KEY??env.CODEX_LB_API_KEY;
if(!key)throw new Error('missing_provider_secret');
// Candidate metadata path, not an assertion of a documented/supported LB contract.
const url=new URL(codexEndpoint+'/models');
const response=await fetch(url,{headers:{Authorization:'Bearer '+key},signal:AbortSignal.timeout(15_000),redirect:'error'});
console.log(JSON.stringify({event:'metadata_headers',status:response.status,contentType:response.headers.get('content-type'),url:url.href}));
const chunks:Uint8Array[]=[];let bytes=0;
let truncated=false;
if(response.body)for await(const chunk of response.body){const remaining=128_000-bytes;if(chunk.length>remaining){chunks.push(chunk.subarray(0,remaining));truncated=true;break;}bytes+=chunk.length;chunks.push(chunk);}
console.log(JSON.stringify({purpose:'LB model discovery; candidate path unverified',status:response.status,url:url.href,body:Buffer.concat(chunks).toString('utf8')}));
if(!response.ok||truncated){console.log(JSON.stringify({event:'metadata_failure',reason:truncated?'metadata_budget':'http_status'}));process.exitCode=1;}
