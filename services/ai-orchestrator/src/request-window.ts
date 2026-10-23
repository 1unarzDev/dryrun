/** Bounded replay protection and request quota for each authorized installation.
 * Expired windows are reclaimed; one family's requests cannot exhaust every family forever.
 */
export class RequestWindowFailure extends Error {
 constructor(readonly reason:'replayed_request'|'request_quota'){super(reason);}
}
export class RequestWindow {
 private readonly owners=new Map<string,{expires:number;ids:Set<string>}>();
 constructor(private readonly maximumRequests=100,private readonly windowMs=600_000,
             private readonly maximumOwners=1000,private readonly now=()=>Date.now()){}
 claim(owner:string,requestID:string):void {
  const at=this.now();
  for(const [key,window] of this.owners)if(window.expires<=at)this.owners.delete(key);
  let window=this.owners.get(owner);
  if(!window){
   if(this.owners.size>=this.maximumOwners)throw new RequestWindowFailure('request_quota');
   window={expires:at+this.windowMs,ids:new Set()};this.owners.set(owner,window);
  }
  if(window.ids.has(requestID))throw new RequestWindowFailure('replayed_request');
  if(window.ids.size>=this.maximumRequests)throw new RequestWindowFailure('request_quota');
  window.ids.add(requestID);
 }
}
