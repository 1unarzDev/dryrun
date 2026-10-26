import {readFile} from 'node:fs/promises';
import {operationRequest} from '../src/contracts.js';
import {authorizedContextReader} from '../src/private-context.js';
import {it,expect} from 'vitest';
import {Gateway} from '../src/gateway.js';
import type {AgentProvider} from '../src/provider.js';
const binding={sessionID:'simulation-a',revision:0,eventSequence:0,contextDigest:'simulation-digest',householdRevision:1,homeRevision:0};
const contextBinding={scope:{householdID:'family-a',origin:'example',sessionID:'family-scope-a'},revisions:{household:1,inventory:2,stateFingerprint:'state-a'},snapshotID:'snapshot-a'};
const privateContext={...contextBinding,version:'dryrun.private-context/1',consent:true,records:[{id:'fact-transport',section:'constraints',subjectID:'family-a',sourcePath:'transport',status:'recorded',value:{accessibleVehicle:false,helper:'neighbor-a'}}]};
const request=()=>({contractVersion:'dryrun.ai/1',requestID:'request-a',role:'director',synthetic:true,providerConsent:['codex'],context:{binding,snapshot:{simMinute:0,resources:{},services:{},unmetRequirements:[],unknowns:[]},profiles:[],privateContext,contextBinding,locale:'es'}});
it('retrieves a consequential omitted fact on the host before requesting authoritative Core preview',async()=>{
 let turns=0;const provider:AgentProvider={providerID:'codex',async turn(input){
  turns++;const initial=JSON.parse(String((input.history[0] as {content:{text:string}[]}).content[0]!.text));expect(initial.privateContext).toBeUndefined();expect(initial.contextManifest.snapshotID).toBe('snapshot-a');expect(input.instruction).toContain('selected locale es');
  const name=turns===1?'read_household_context':'evaluateCandidateAction';const args=turns===1?{snapshotID:'snapshot-a',sections:['constraints']}:{command:{kind:'requestDecision'}};
  if(turns===2){const serialized=JSON.stringify(input.history.at(-1));expect(serialized).toContain('accessibleVehicle');expect(serialized).toContain('neighbor-a');}
  const call={type:'function_call' as const,id:'call-'+turns,name,arguments:args};return {steps:[call],text:'',calls:[call],usage:null};
 }};
 const gateway=new Gateway(provider);const result=await gateway.start('owner-a',request()) as {status:string;contextBinding:unknown;calls:{name:string}[];token:string};
 expect(turns).toBe(2);expect(result.status).toBe('needs_client_tools');expect(result.calls.map(c=>c.name)).toEqual(['evaluateCandidateAction']);expect(result.contextBinding).toEqual(contextBinding);
 await expect(gateway.resume('owner-b',{contractVersion:'dryrun.ai/1',token:result.token,binding,callID:'call-2',result:{binding,snapshot:{simMinute:0,resources:{},services:{},unmetRequirements:[],unknowns:[]},contextDigest:'simulation-digest'}})).rejects.toThrow();expect(gateway.cancel('owner-b',result.token).contextBinding).toBeUndefined();gateway.cancel('owner-a',result.token);
});
it('rejects mismatched full binding before provider execution',async()=>{
 let calls=0;const provider:AgentProvider={async turn(){calls++;throw new Error('must_not_run');}};const input=request();input.context.contextBinding={...contextBinding,snapshotID:'other-snapshot'};
 await expect(new Gateway(provider).start('owner-a',input)).rejects.toThrow('stale_context');expect(calls).toBe(0);
});
it('bounds repeated retrieval without turning it into a preview or client mutation',async()=>{
 let calls=0;const provider:AgentProvider={async turn(){calls++;const call={type:'function_call' as const,id:'read-'+calls,name:'read_household_context',arguments:{snapshotID:'snapshot-a',sections:['constraints']}};return {steps:[call],text:'',calls:[call],usage:null};}};
 const result=await new Gateway(provider).start('owner-a',request()) as {status:string};expect(result.status).toBe('unavailable');expect(calls).toBe(5);
});

// Core writes these bytes on every `swift test` (DirectorPrivateContextTests); the checked-in copy keeps this in the standard check.
it('validates exact native director bytes and retrieves canonical score/history',async()=>{
 const request=operationRequest.parse(JSON.parse(await readFile(process.env.DRYRUN_DIRECTOR_WIRE_PATH??new URL('../../../fixtures/ai/native-bridge/director-private-context-wire.json',import.meta.url),'utf8')));
 expect(request.providerConsent).toEqual(['codex','gemini','groq']);
 const reader=authorizedContextReader(request.context.privateContext,'authored-owner',request.context.contextBinding);
 const result=reader.read({snapshotID:reader.manifest.snapshotID,sections:['scores']});
 expect(result.records.some(record=>record.sourcePath==='currentHostScorecard'&&record.status==='recorded')).toBe(true);
 expect(request.context.experience).toBeDefined();expect(request.context.contextBinding?.revisions.household).toBe(request.context.binding.householdRevision);
});
it('pre-packs authorized records so the director previews on its first turn, with one further read at most',async()=>{
 let turns=0;const offered:string[][]=[];const provider:AgentProvider={providerID:'codex',async turn(input){
  turns++;offered.push(input.tools.flatMap(t=>t.type==='function'&&t.name?[t.name]:[]));
  const first=JSON.stringify(input.history[0]);expect(first).toContain('hostRetrievedRecords');expect(first).toContain('neighbor-a');expect(input.instruction).toContain('already retrieved');
  const call=turns===1?{type:'function_call' as const,id:'read-1',name:'read_household_context',arguments:{snapshotID:'snapshot-a',sections:['constraints']}}:{type:'function_call' as const,id:'call-'+turns,name:'evaluateCandidateAction',arguments:{command:{kind:'requestDecision'}}};
  return {steps:[call],text:'',calls:[call],usage:null};
 }};
 const result=await new Gateway(provider,undefined,40,12,{prepackContext:true}).start('owner-a',request()) as {status:string};
 expect(result.status).toBe('needs_client_tools');expect(turns).toBe(2);
 expect(offered[0]).toContain('read_household_context');expect(offered[1]).not.toContain('read_household_context');
});
