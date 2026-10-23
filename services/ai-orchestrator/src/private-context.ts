import {z} from 'zod';
import {createHmac,randomBytes} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
export const contextSections=['family','medical','home','location','constraints','inventory','tasks','learning','scores'] as const;
const identifier=z.string().min(1).max(240);
export const contextBinding=z.object({scope:z.object({householdID:identifier,origin:z.enum(['real','example']),sessionID:z.string().min(1).max(120)}).strict(),revisions:z.object({household:z.number().int().nonnegative(),home:z.number().int().nonnegative().optional(),inventory:z.number().int().nonnegative(),stateFingerprint:identifier}).strict(),snapshotID:identifier,homeID:identifier.optional()}).strict();
export const privateContext=contextBinding.extend({version:z.literal('dryrun.private-context/1'),consent:z.literal(true),records:z.array(z.object({id:identifier,section:z.enum(contextSections),subjectID:identifier,sourcePath:identifier,status:z.enum(['recorded','not_recorded','confirmed_absent','unsupported','stale','conflicting','permission_denied']),value:z.json().optional()}).strict()).max(3000)}).strict().superRefine((data,ctx)=>{
 if(new Set(data.records.map(r=>r.id)).size!==data.records.length)ctx.addIssue({code:'custom',message:'duplicate_context_record'});
 if(Buffer.byteLength(JSON.stringify(data))>4_000_000)ctx.addIssue({code:'custom',message:'context_budget'});
 for(const record of data.records)if(record.status!=='recorded'&&record.value!==undefined)ctx.addIssue({code:'custom',message:'unavailable_record_has_value'});
});
export const contextRead=z.object({snapshotID:identifier,sections:z.array(z.enum(contextSections)).min(1).max(9),subjectIDs:z.array(identifier).max(30).optional(),sourcePrefixes:z.array(identifier).max(12).optional(),recordID:identifier.optional(),valuePath:z.array(z.union([z.string().max(240),z.number().int().nonnegative()])).max(30).optional(),cursor:z.string().regex(/^\d{1,8}\.[a-f0-9]{24}$/).optional()}).strict();
export type PrivateContext=z.infer<typeof privateContext>;
export type ContextReadReply={snapshotID:string;revisions:PrivateContext['revisions'];records:(PrivateContext['records'][number]&{valueRead?:{recordID:string;valuePath:(string|number)[];reason:string}})[];valueRead?:{recordID:string;valuePath:(string|number)[];status:string;offset:number;total:number;[key:string]:unknown};nextCursor:string|null;unavailable:{id:string;reason:string}[]};
export const contextPageRecordLimit=32;
export const contextPageByteLimit=128_000;

/** Closure ownership is the authorization boundary; tool arguments contain no tenant selector. */
export function authorizedContextReader(raw:unknown,owner:string,rawExpected:unknown){
 if(!owner)throw new Error('context_authorization_required');
 const snapshot=privateContext.parse(raw);
 const expected=contextBinding.parse(rawExpected);
 if(!isDeepStrictEqual(snapshot.scope,expected.scope)||!isDeepStrictEqual(snapshot.revisions,expected.revisions)||snapshot.snapshotID!==expected.snapshotID||snapshot.homeID!==expected.homeID)throw new Error('stale_context');
 const geometry=snapshot.records.find(record=>record.section==='home'&&record.sourcePath==='geometry');
 if(geometry?.status==='recorded'&&geometry.value&&typeof geometry.value==='object'&&!Array.isArray(geometry.value)&&geometry.value.id!==expected.homeID)throw new Error('stale_context');
 const exposed=new Map<string,{id:string;status:string;section:string;sourcePath:string;snapshotID:string;exposure:'full'|'metadata'|'fragment';valuePaths:(string|number)[][];fragments:{valuePath:(string|number)[];offset:number;total:number;kind:unknown}[]}>();
 const release=(reply:ContextReadReply):ContextReadReply=>{
  for(const emitted of reply.records){const previous=exposed.get(emitted.id);exposed.set(emitted.id,{id:emitted.id,status:emitted.status,section:emitted.section,sourcePath:emitted.sourcePath,snapshotID:snapshot.snapshotID,exposure:previous?.exposure==='full'?'full':emitted.valueRead?'metadata':'full',valuePaths:previous?.valuePaths??[],fragments:previous?.fragments??[]});}
  if(reply.valueRead){const record=snapshot.records.find(record=>record.id===reply.valueRead!.recordID)!;const previous=exposed.get(record.id);exposed.set(record.id,{id:record.id,status:record.status,section:record.section,sourcePath:record.sourcePath,snapshotID:snapshot.snapshotID,exposure:previous?.exposure==='full'?'full':'fragment',valuePaths:[...(previous?.valuePaths??[]),reply.valueRead.valuePath],fragments:[...(previous?.fragments??[]),{valuePath:reply.valueRead.valuePath,offset:reply.valueRead.offset,total:reply.valueRead.total,kind:reply.valueRead.kind}]});}
  return reply;
 };
 const cursorSecret=randomBytes(32);
 const cursorFor=(offset:number,args:z.infer<typeof contextRead>)=>String(offset)+'.'+createHmac('sha256',cursorSecret).update(JSON.stringify([snapshot.snapshotID,[...new Set(args.sections)].sort(),[...new Set(args.subjectIDs??[])].sort(),[...new Set(args.sourcePrefixes??[])].sort(),args.recordID??null,args.valuePath??[],offset])).digest('hex').slice(0,24);
 const manifest={version:snapshot.version,readerVersion:'dryrun.context-reader/2',provenanceVersion:'dryrun.context-provenance/1',snapshotID:snapshot.snapshotID,scope:snapshot.scope,revisions:snapshot.revisions,pageRecordLimit:contextPageRecordLimit,pageByteLimit:contextPageByteLimit,sections:contextSections.map(section=>({section,recordCount:snapshot.records.filter(r=>r.section===section).length})),limitations:['Recorded values retain their nested evidence state; empty arrays do not establish confirmed absence.','Numeric budget is unsupported unless separately recorded.','Collection indexes name individual-record sourcePrefixes; preserve numeric source array order.','valueRead references require a same-snapshot recordID/valuePath read; text/object/array fragments must be completed before assuming their whole value.']};
 return {manifest,evidence(requestOwner:string,requestBinding:unknown){
  if(requestOwner!==owner||!isDeepStrictEqual(contextBinding.parse(requestBinding),expected))throw new Error('context_authorization_required');
  return structuredClone([...exposed.values()]);
 },read(rawArguments:unknown):ContextReadReply{
  const args=contextRead.parse(rawArguments);if(args.snapshotID!==snapshot.snapshotID)throw new Error('stale_context_snapshot');
  const selected=snapshot.records.filter(record=>args.sections.includes(record.section)&&(!args.subjectIDs?.length||args.subjectIDs.includes(record.subjectID))&&(!args.sourcePrefixes?.length||args.sourcePrefixes.some(prefix=>record.sourcePath.startsWith(prefix))));
  const start=args.cursor?Number(args.cursor.split('.')[0]):0;if(args.cursor&&args.cursor!==cursorFor(start,args))throw new Error('invalid_context_cursor');
  if(args.recordID){
   const record=selected.find(record=>record.id===args.recordID);if(!record)throw new Error('context_record_not_in_query');
   let value:unknown=record.value;const path=args.valuePath??[];
   for(const key of path){if(!value||typeof value!=='object'||!Object.hasOwn(value,key))throw new Error('invalid_context_value_path');value=Reflect.get(value,key);}
   const reference=(child:unknown,childPath:(string|number)[])=>({kind:'value_reference',recordID:record.id,valuePath:childPath,valueType:Array.isArray(child)?'array':child===null?'null':typeof child});
   const bounded=(child:unknown,childPath:(string|number)[])=>Buffer.byteLength(JSON.stringify(child)??'null')>24_000?reference(child,childPath):{kind:'value',value:child};
   let body:Record<string,unknown>,total:number,next:number;
   if(typeof value==='string'){total=value.length;next=Math.min(total,start+16_000);body={kind:'text',text:value.slice(start,next)};}
   else if(Array.isArray(value)){total=value.length;next=Math.min(total,start+4);body={kind:'array',items:value.slice(start,next).map((child,index)=>({index:start+index,...bounded(child,[...path,start+index])}))};}
   else if(value&&typeof value==='object'){const keys=Object.keys(value).sort();total=keys.length;next=Math.min(total,start+4);body={kind:'object',entries:keys.slice(start,next).map(key=>({key,...bounded(Reflect.get(value,key),[...path,key])}))};}
   else{total=1;next=1;body={kind:'scalar',value};}
   if(start>total)throw new Error('invalid_context_cursor');
   return release({snapshotID:snapshot.snapshotID,revisions:snapshot.revisions,records:[],valueRead:{recordID:record.id,valuePath:path,status:record.status,offset:start,total,...body},nextCursor:next<total?cursorFor(next,args):null,unavailable:[]});
  }
  if(args.valuePath?.length||start>selected.length)throw new Error('invalid_context_cursor');
  const records:Array<Omit<typeof selected[number],'value'> & {value?:z.infer<typeof privateContext>['records'][number]['value'];valueRead?:{recordID:string;valuePath:never[];reason:string}}>=[];let bytes=0,index=start;
  while(index<selected.length&&records.length<contextPageRecordLimit){const record=selected[index]!;let emitted:typeof records[number]=record;const fullSize=Buffer.byteLength(JSON.stringify(record));if(fullSize>contextPageByteLimit){const {value,...metadata}=record;emitted={...metadata,valueRead:{recordID:record.id,valuePath:[],reason:'value_requires_paging'}};}const size=Buffer.byteLength(JSON.stringify(emitted));if(bytes+size>contextPageByteLimit)break;records.push(emitted);bytes+=size;index++;}
  return release({snapshotID:snapshot.snapshotID,revisions:snapshot.revisions,records,nextCursor:index<selected.length?cursorFor(index,args):null,unavailable:[]});
 }};
}
