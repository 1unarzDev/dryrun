// Cleared authored synthetic inputs only; no recorded generated text.
import {describe,it,expect} from 'vitest';
import {readFile} from 'node:fs/promises';
import {authorizedContextReader,privateContext} from '../src/private-context.js';
import {FeatureRunner} from '../src/features.js';
import type {AgentProvider,History} from '../src/provider.js';

const snapshot=(storage='Keep in synthetic cool storage')=>({version:'dryrun.private-context/1' as const,consent:true as const,scope:{householdID:'synthetic-household',origin:'example' as const,sessionID:'session-a'},snapshotID:'snapshot-a',revisions:{household:1,inventory:0,stateFingerprint:'synthetic-v1'},records:[{id:'context.medical.equipment-a',section:'medical' as const,subjectID:'person-a',sourcePath:'equipment.a',status:'recorded' as const,value:{storageInstructions:storage,personID:'person-a'}}]});
const binding=(s:any,revision=s.revisions.household)=>({scope:s.scope,revisions:{...s.revisions,household:revision},snapshotID:s.snapshotID,...(s.homeID?{homeID:s.homeID}:{})});
const candidate=(id:string,actionID:string,editor:'medical'|'family')=>({id,actionID,criterionID:'criterion-a',subjectID:'person-a',why:'Authored candidate explanation',evidenceIDs:['household-needs'],completionPredicates:['predicate-a'],editor,dependencyIDs:[],priority:1});
const context=(storage?:string)=>({privateContext:snapshot(storage),contextBinding:binding(snapshot(storage)),household:{revision:1,people:[{id:'person-a',ageBand:'adult',needs:[]}],pets:[],equipment:[],transport:'noCar',limitedBudget:true,regionID:'synthetic',evidence:[{id:'household-needs',origin:'userConfirmed',status:'confirmed',sourceIDs:[],fieldIDs:['equipment.storageInstructions']}]},tasks:[],gaps:[],taskCatalog:[candidate('cold','prep.coldStorage','medical'),candidate('helper','prep.helper','family')],allowedActionIDs:['prep.coldStorage','prep.helper'],allowedCriterionIDs:['criterion-a']});
describe('authorized retrievable private context',()=>{
 it('requires host authorization and matching household revision',()=>{
  expect(()=>authorizedContextReader(snapshot(),'',binding(snapshot()))).toThrow('context_authorization_required');
  expect(()=>authorizedContextReader(snapshot(),'owner-a',binding(snapshot(),2))).toThrow('stale_context');
 });
 it('rejects tenant selectors, stale snapshots and unavailable records with disguised values',()=>{
  const reader=authorizedContextReader(snapshot(),'owner-a',binding(snapshot()));
  expect(()=>reader.read({snapshotID:'snapshot-a',sections:['medical'],householdID:'other'})).toThrow();
  expect(()=>reader.read({snapshotID:'other',sections:['medical']})).toThrow('stale_context_snapshot');
  expect(()=>privateContext.parse({...snapshot(),records:[{...snapshot().records[0],status:'not_recorded'}]})).toThrow();
 });
 it('paginates a fixed snapshot and filters canonical subject relationships',()=>{
  const source=snapshot();source.records=Array.from({length:73},(_,n)=>({...source.records[0]!,id:'context.medical.'+n,subjectID:n<69?'person-a':'person-b'}));
  const reader=authorizedContextReader(source,'owner-a',binding(source));const ids:string[]=[];let cursor:string|undefined;
  do{const page=reader.read({snapshotID:source.snapshotID,sections:['medical'],subjectIDs:['person-a'],cursor});ids.push(...page.records.map(r=>r.id));cursor=page.nextCursor??undefined;}while(cursor);
  expect(ids).toHaveLength(69);expect(new Set(ids).size).toBe(69);expect(reader.manifest).not.toHaveProperty('records');
 });
 it('supplies a decision-changing recorded instruction only through the actual feature tool',async()=>{
  for(const storage of ['Keep in synthetic cool storage','No recorded storage instruction']){
   let turns=0;
   const provider:AgentProvider={async turn(input){turns++;
    if(turns===1){const initial=JSON.stringify(input.history);expect(initial).not.toContain(storage);const first=input.history[0];const part=first?.type==='user_input'&&Array.isArray(first.content)?first.content[0]:undefined;const parsed=part?.type==='text'?JSON.parse(part.text):{};expect(parsed).not.toHaveProperty('privateContext');expect(parsed).toHaveProperty('contextManifest');expect(parsed.contextManifest).not.toHaveProperty('records');expect(input.tools.some(t=>t.type==='function'&&t.name==='read_household_context')).toBe(true);
     const call={type:'function_call' as const,id:'read-a',name:'read_household_context',arguments:{snapshotID:'snapshot-a',sections:['medical'],subjectIDs:['person-a']}};return {steps:[call],text:'',calls:[call],usage:null};}
    const step=input.history.findLast(s=>s.type==='function_result');expect(step?.type).toBe('function_result');
    const result=step?.type==='function_result'?JSON.stringify(step.result):'';
    const candidateID=result.includes('cool storage')?'cold':'helper';
    return {steps:[],text:JSON.stringify({selected:[{candidateID,why:'Synthetic transport and storage comparison',evidenceIDs:['household-needs']}],inventoryObservations:[],question:null}),calls:[],usage:null};
   }};
   const output=await new FeatureRunner(provider).run('preparation',context(storage),undefined,[],'owner-a') as {tasks:{actionID:string}[]};
   expect(output.tasks[0]?.actionID).toBe(storage.includes('cool storage')?'prep.coldStorage':'prep.helper');expect(turns).toBe(2);
  }
 });
 it('does not return private-context results when no authorized read occurred',async()=>{
  const provider:AgentProvider={async turn(){return {steps:[],text:'{"tasks":[],"inventoryObservations":[],"question":null}',calls:[],usage:null};}};
  await expect(new FeatureRunner(provider).run('preparation',context(),undefined,[],'owner-a')).rejects.toThrow();
 });
 it('isolates same snapshot names and subjects in concurrent owner-bound readers',()=>{
  const a=authorizedContextReader(snapshot('synthetic-a'),'owner-a',binding(snapshot('synthetic-a'))),b=authorizedContextReader(snapshot('synthetic-b'),'owner-b',binding(snapshot('synthetic-b')));
  const args={snapshotID:'snapshot-a',sections:['medical']};expect(JSON.stringify(a.read(args))).toContain('synthetic-a');expect(JSON.stringify(a.read(args))).not.toContain('synthetic-b');expect(JSON.stringify(b.read(args))).toContain('synthetic-b');
 });
 it('finishes after five read pages and closes the host operation immediately',async()=>{
  const raw=context();raw.privateContext.records=Array.from({length:129},(_,n)=>({...raw.privateContext.records[0]!,id:'context.medical.'+n}));
  let turns=0,disposed=0;let operationSignal:AbortSignal|undefined;
  const provider:AgentProvider & {disposeOperation:()=>Promise<void>}={async disposeOperation(){disposed++;},async turn(input){
   operationSignal=input.signal;turns++;
   const last=input.history.findLast(s=>s.type==='function_result');const content=last?.type==='function_result'&&Array.isArray(last.result)?last.result[0]:undefined;
   const page=content?.type==='text'?JSON.parse(content.text):undefined;
   if(!page||page.nextCursor){const call={type:'function_call' as const,id:'read-'+turns,name:'read_household_context',arguments:{snapshotID:'snapshot-a',sections:['medical'],...(page?.nextCursor?{cursor:page.nextCursor}:{})}};return {steps:[call],text:'',calls:[call],usage:null};}
   return {steps:[],text:JSON.stringify({selected:[{candidateID:'cold',why:'Authored synthetic storage decision',evidenceIDs:['household-needs']}],inventoryObservations:[],question:null}),calls:[],usage:null};
  }};
  const output=await new FeatureRunner(provider).run('preparation',raw,undefined,[],'owner-a') as {tasks:unknown[]};expect(output.tasks).toHaveLength(1);expect(turns).toBe(6);expect(disposed).toBe(1);expect(operationSignal?.aborted).toBe(true);
 });
 it('reserves finalization after bounded reads and disposes a noncompliant repeated reader',async()=>{
  let turns=0,disposed=0;let operationSignal:AbortSignal|undefined;
  const provider:AgentProvider & {disposeOperation:()=>Promise<void>}={async disposeOperation(){disposed++;},async turn(input){turns++;operationSignal=input.signal;
   if(turns===9){expect(input.tools).toHaveLength(0);expect(input.toolMode).toBe('none');}
   const call={type:'function_call' as const,id:'read-'+turns,name:'read_household_context',arguments:{snapshotID:'snapshot-a',sections:['medical']}};return {steps:[call],text:'',calls:[call],usage:null};
  }};
  await expect(new FeatureRunner(provider).run('preparation',context(),undefined,[],'owner-a')).rejects.toThrow('codex_execution_budget');expect(turns).toBe(9);expect(disposed).toBe(1);expect(operationSignal?.aborted).toBe(true);
 });
 it('closes a paused provider on host-side tool argument rejection',async()=>{
  let disposed=0;let operationSignal:AbortSignal|undefined;
  const provider:AgentProvider & {disposeOperation:()=>Promise<void>}={async disposeOperation(){disposed++;},async turn(input){operationSignal=input.signal;const call={type:'function_call' as const,id:'read-bad',name:'read_household_context',arguments:{snapshotID:'wrong-snapshot',sections:['medical']}};return {steps:[call],text:'',calls:[call],usage:null};}};
  await expect(new FeatureRunner(provider).run('preparation',context(),undefined,[],'owner-a')).rejects.toThrow('codex_unavailable');expect(disposed).toBe(1);expect(operationSignal?.aborted).toBe(true);
 });
 it('rejects equal-revision scope/home/inventory mismatches against the accepted binding',()=>{
  const raw={...snapshot(),homeID:'home-a'};
  for(const expected of [{...binding(raw),scope:{...raw.scope,householdID:'other'}},{...binding(raw),scope:{...raw.scope,origin:'real'}},{...binding(raw),scope:{...raw.scope,sessionID:'other'}},{...binding(raw),homeID:'home-b'},{...binding(raw),revisions:{...raw.revisions,inventory:1}},{...binding(raw),revisions:{...raw.revisions,stateFingerprint:'changed'}}])expect(()=>authorizedContextReader(raw,'owner-a',expected)).toThrow('stale_context');
 });
 it('binds continuation cursors to the same snapshot and record filter',()=>{
  const raw=snapshot();raw.records=Array.from({length:40},(_,n)=>({...raw.records[0]!,id:'context.medical.'+n}));const reader=authorizedContextReader(raw,'owner-a',binding(raw));const page=reader.read({snapshotID:raw.snapshotID,sections:['medical']});expect(page.nextCursor).toBeTruthy();
  expect(()=>reader.read({snapshotID:raw.snapshotID,sections:['medical','family'],cursor:page.nextCursor})).toThrow('invalid_context_cursor');expect(()=>reader.read({snapshotID:raw.snapshotID,sections:['medical'],subjectIDs:['person-a'],cursor:page.nextCursor})).toThrow('invalid_context_cursor');
  expect(reader.read({snapshotID:raw.snapshotID,sections:['medical'],cursor:page.nextCursor}).records).toHaveLength(8);
 });
 it.each(['home','learning'] as const)('retrieves oversized %s canonical text and nested arrays without skipping or truncating them',section=>{
  const longText='Authored large recorded instruction. '.repeat(9000);
  const nested=Array.from({length:65},(_,index)=>({index,recorded:'Synthetic record '+index}));
  const raw=snapshot();raw.records=[{...raw.records[0]!,section,sourcePath:section==='home'?'geometry.annotations.item.0.large':'sessions.item.0.large',value:{storageInstructions:longText,history:nested}} as any];
  const reader=authorizedContextReader(raw,'owner-a',binding(raw));const initial=reader.read({snapshotID:raw.snapshotID,sections:[section]});expect(initial.unavailable).toHaveLength(0);expect(initial.records[0]?.valueRead?.recordID).toBe(raw.records[0]!.id);
  const base={snapshotID:raw.snapshotID,sections:[section],recordID:raw.records[0]!.id};
  const root=reader.read({...base,valuePath:[]});expect(root.valueRead?.kind).toBe('object');expect(JSON.stringify(root)).toContain('value_reference');
  let cursor:string|undefined;let reconstructed='';
  do{const page=reader.read({...base,valuePath:['storageInstructions'],cursor});expect(Buffer.byteLength(JSON.stringify(page))).toBeLessThan(128000);reconstructed+=String(page.valueRead?.text);cursor=page.nextCursor??undefined;}while(cursor);
  expect(reconstructed).toBe(longText);
  const history:any[]=[];cursor=undefined;
  do{const page=reader.read({...base,valuePath:['history'],cursor});for(const item of page.valueRead?.items as {value:any}[])history.push(item.value);cursor=page.nextCursor??undefined;}while(cursor);
  expect(history).toEqual(nested);
  const first=reader.read({...base,valuePath:['storageInstructions']});expect(()=>reader.read({...base,valuePath:['history'],cursor:first.nextCursor})).toThrow('invalid_context_cursor');
 });
 // Core writes these bytes on every `swift test` (AuthorizedAIContextTests); the checked-in copy keeps this in the standard check.
 it('validates actual Swift-encoded bytes through the strict server schema',async()=>{
  const data=privateContext.parse(JSON.parse(await readFile(process.env.DRYRUN_CONTEXT_WIRE_PATH??new URL('../../../fixtures/ai/native-bridge/authorized-context-wire.json',import.meta.url),'utf8')));
  expect(data.scope.sessionID).toBe('synthetic-session');
  const reader=authorizedContextReader(data,'synthetic-owner',binding(data));
  const page=reader.read({snapshotID:data.snapshotID,sections:['family','medical'],subjectIDs:['person-a']});
  expect(JSON.stringify(page)).toContain('Casey');expect(JSON.stringify(page)).toContain('person-b');expect(JSON.stringify(page)).toContain('Synthetic recorded medicine');
 });
});
