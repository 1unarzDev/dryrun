import {ProviderFailure} from './provider-failure.js';
export type QuotaWindowOptions={now?:()=>number;windowMs?:number;maximumOwners?:number};
/** Per-owner ten-minute call windows. Defaults are the production-shaped limits; the Mac reviewer profile
 * (scripts/mac/beacon-gateway.sh, synthetic households only) raises them through the environment so a review matrix
 * is not cut short by a call-count window. Spend (DRYRUN_MAX_USD) and per-operation bounds stay independent. */
export type QuotaLimits={featureTurns:number;directorStarts:number;directorTurns:number;httpRequests:number};
export const defaultQuotaLimits:QuotaLimits={featureTurns:40,directorStarts:12,directorTurns:40,httpRequests:100};
export function quotaLimitsFromEnv(env:Record<string,string|undefined>=process.env):QuotaLimits{
 const read=(name:string,fallback:number)=>{const raw=env[name];if(raw===undefined||raw==='')return fallback;const value=Number(raw);return Number.isInteger(value)&&value>=1&&value<=100000?value:fallback;};
 return {featureTurns:read('DRYRUN_FEATURE_TURNS_PER_WINDOW',defaultQuotaLimits.featureTurns),directorStarts:read('DRYRUN_DIRECTOR_STARTS_PER_WINDOW',defaultQuotaLimits.directorStarts),
  directorTurns:read('DRYRUN_DIRECTOR_TURNS_PER_WINDOW',defaultQuotaLimits.directorTurns),httpRequests:read('DRYRUN_HTTP_REQUESTS_PER_WINDOW',defaultQuotaLimits.httpRequests)};
}
/** Renewable owner-isolated call budget; operation deadlines/spend/concurrency remain independent. */
export class OwnerWindowQuota {
 private owners=new Map<string,{started:number;calls:number}>();
 private now:()=>number;private windowMs:number;private maximumOwners:number;
 constructor(private maximumCalls:number,options:QuotaWindowOptions={}){
  this.now=options.now??Date.now;this.windowMs=options.windowMs??600_000;this.maximumOwners=options.maximumOwners??1000;
  if(!Number.isInteger(maximumCalls)||maximumCalls<1||this.windowMs<=0||this.maximumOwners<1)throw new Error('invalid_quota_configuration');
 }
 consume(owner:string){
  const now=this.now();for(const [key,state]of this.owners)if(now-state.started>=this.windowMs)this.owners.delete(key);
  let state=this.owners.get(owner);
  if(!state){if(this.owners.size>=this.maximumOwners)throw new ProviderFailure('rate_limit','operation',429,this.windowMs,'owner_window_capacity');state={started:now,calls:0};this.owners.set(owner,state);}
  if(state.calls>=this.maximumCalls)throw new ProviderFailure('rate_limit','operation',429,Math.max(1,this.windowMs-(now-state.started)),'owner_window_quota');
  state.calls++;
 }
}
