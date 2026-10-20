export type FailureKind='rate_limit'|'quota_exhausted'|'timeout'|'configuration'|'unsupported'|'refusal'|'invalid_output'|'cancelled'|'unavailable';
export class ProviderFailure extends Error {
 constructor(readonly kind:FailureKind,readonly provider:string,readonly status?:number,readonly retryAfterMs?:number,readonly diagnostic?:string,message=`${provider}_${kind}`){super(message);}
}
/** HTTP Retry-After is seconds or an HTTP date; Groq reset durations use e.g. 2m59.56s. */
export function resetDuration(value:string|null):number|undefined {
 if(!value)return;let total=0,end=0;const re=/(\d+(?:\.\d+)?)(ms|s|m|h)/g;for(const m of value.matchAll(re)){if(m.index!==end)return;total+=Number(m[1])*({ms:1,s:1000,m:60000,h:3600000}[m[2]!]??0);end=m.index+m[0].length;}return end===value.length&&end>0?total:undefined;
}
export function retryDelay(headers:Headers,now=Date.now()):number|undefined {
 const value=headers.get('retry-after');if(value)return /^\d+(?:\.\d+)?$/.test(value)?Number(value)*1000:Math.max(0,Date.parse(value)-now)||undefined;
 // Requests and tokens have different windows; retain whichever exhausted counter blocks us longest.
 const blocked=['requests','tokens'].filter(k=>headers.get('x-ratelimit-remaining-'+k)==='0').map(k=>resetDuration(headers.get('x-ratelimit-reset-'+k))).filter((x):x is number=>x!==undefined);
 return blocked.length?Math.max(...blocked):undefined;
}
/** Per configured provider/model/capability circuit; one half-open caller, no key rotation. */
export class QuotaCircuit {
 private until=0;private probing=false;private epoch=0;
 get generation(){return this.epoch;}
 constructor(private now=Date.now,private jitter=()=>Math.random()*1000){}
 enter(){if(this.now()<this.until||this.probing)return false;if(this.until>0)this.probing=true;return true;}
 retryAfterMs(){const delay=this.until-this.now();return delay>0?delay:undefined;}
 success(generation=this.epoch){if(generation!==this.epoch)return;this.until=0;this.probing=false;}
 failure(delay=60000){this.until=Math.max(this.until,this.now()+Math.max(1000,delay)+this.jitter());this.epoch++;this.probing=false;}
 release(generation=this.epoch){if(generation===this.epoch)this.probing=false;}
}

/** Interactions SDK APIError exposes status, headers and error. Only allowlisted
 * machine metadata escapes; raw messages may echo private request content. */
export function geminiFailure(error:unknown,signal:AbortSignal):ProviderFailure {
 const e=error as any,status=typeof e?.status==='number'?e.status:undefined;
 if(signal.aborted)return new ProviderFailure(signal.reason?.name==='TimeoutError'?'timeout':'cancelled','gemini',status,undefined,undefined,'provider_timeout_or_cancelled');
 let body=e?.error;
 if(typeof body==='string'){try{body=JSON.parse(body);}catch{body=undefined;}}
 body=body?.error??body;
 const details=Array.isArray(body?.details)?body.details:[];
 const delays=details.filter((d:any)=>d?.['@type']==='type.googleapis.com/google.rpc.RetryInfo').map((d:any)=>typeof d.retryDelay==='string'?resetDuration(d.retryDelay):undefined).filter((d:unknown):d is number=>typeof d==='number');
 let headers:Headers|undefined;try{if(e?.headers)headers=new Headers(e.headers);}catch{/* Invalid metadata is not a delay. */}
 const headerDelay=headers?retryDelay(headers):undefined;
 const retryAfterMs=headerDelay===undefined?(delays.length?Math.max(...delays):undefined):Math.max(headerDelay,...delays);
 const violations=details.filter((d:any)=>d?.['@type']==='type.googleapis.com/google.rpc.QuotaFailure').flatMap((d:any)=>Array.isArray(d.violations)?d.violations:[]);
 const daily=violations.some((v:any)=>/per.?day|daily/i.test(String(v.quotaId??v.quotaMetric??'')));
 const known=['RESOURCE_EXHAUSTED','UNAVAILABLE','PERMISSION_DENIED','UNAUTHENTICATED','INVALID_ARGUMENT','NOT_FOUND'];
 const diagnostic=known.includes(body?.status)?body.status:undefined;
 const kind:FailureKind=status===429?(daily?'quota_exhausted':'rate_limit'):status===401||status===403?'configuration':status===400||status===404||status===413?'unsupported':'unavailable';
 const message=status===429?'provider_rate_limited':status===503?'provider_overloaded':status===404?'provider_model_unavailable':status===401||status===403?'provider_access_denied':status===400||status===413?'provider_request_rejected':'provider_unavailable';
 return new ProviderFailure(kind,'gemini',status,retryAfterMs,diagnostic,message);
}

/** Bound a primary attempt inside the logical deadline. A transport may ignore
 * abort; its eventual result is still never accepted by this attempt. */
export async function primaryAttempt<T>(parent:AbortSignal,timeoutMs:number,run:(signal:AbortSignal)=>Promise<T>):Promise<T>{
 parent.throwIfAborted();
 const signal=AbortSignal.any([parent,AbortSignal.timeout(Math.max(1,Math.floor(timeoutMs)))]);
 return new Promise<T>((resolve,reject)=>{
  const aborted=()=>{signal.removeEventListener('abort',aborted);reject(new ProviderFailure(parent.aborted?'cancelled':'timeout','gemini',undefined,undefined,undefined,'provider_timeout_or_cancelled'));};
  signal.addEventListener('abort',aborted,{once:true});
  Promise.resolve().then(()=>{signal.throwIfAborted();return run(signal);}).then(value=>{signal.removeEventListener('abort',aborted);if(signal.aborted){aborted();return;}resolve(value);},error=>{signal.removeEventListener('abort',aborted);reject(error);});
 });
}
