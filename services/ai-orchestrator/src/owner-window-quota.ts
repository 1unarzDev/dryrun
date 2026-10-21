import {ProviderFailure} from './provider-failure.js';
export type QuotaWindowOptions={now?:()=>number;windowMs?:number;maximumOwners?:number};
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
