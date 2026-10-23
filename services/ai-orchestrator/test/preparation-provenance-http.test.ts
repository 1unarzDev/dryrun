import {it,expect} from 'vitest';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {FeatureRunner} from '../src/features.js';
import {Gateway} from '../src/gateway.js';
import {IntentInterpreter} from '../src/intents.js';
import {createAIRequestHandler} from '../src/http.js';
import {authorizedContextReader} from '../src/private-context.js';
import type {AgentProvider} from '../src/provider.js';
const binding={scope:{householdID:'family-a',origin:'example',sessionID:'scope-a'},revisions:{household:1,inventory:1,stateFingerprint:'state-a'},snapshotID:'snapshot-a'};
const facts=[{id:'context.constraints.transport',section:'constraints',subjectID:'family-a',sourcePath:'transport',status:'recorded',value:{accessibleVehicle:false}},{id:'context.medical.instructions',section:'medical',subjectID:'person-a',sourcePath:'instructions',status:'not_recorded'}];
const task={id:'task-a',actionID:'prep.transport',criterionID:'meetups',subjectID:'household',why:'Review recorded assistance before arranging transport.',evidenceIDs:['legacy-a'],completionPredicates:['transport'],editor:'meetingPlace',dependencyIDs:[],priority:1};
const input=()=>({household:{revision:1,people:[],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[{id:'legacy-a',origin:'userConfirmed',status:'confirmed',sourceIDs:[],fieldIDs:[]}]},tasks:[],gaps:[],taskCatalog:[task],allowedActionIDs:['prep.transport'],allowedCriterionIDs:['meetups'],contextBinding:binding,privateContext:{...binding,version:'dryrun.private-context/1',consent:true,records:facts}});
const call=(sections=['constraints'],extra={})=>({type:'function_call' as const,id:'read-a',name:'read_household_context',arguments:{snapshotID:'snapshot-a',sections,...extra}});
const proposal=(evidenceIDs=['context.constraints.transport'],tasks=true)=>({tasks:tasks?[{...task,evidenceIDs}]:[],inventoryObservations:[],question:null});
async function http(provider:AgentProvider,context:unknown){const server=createServer(createAIRequestHandler({gateway:new Gateway(provider),features:new FeatureRunner(provider),interpreter:new IntentInterpreter(provider),authorize:header=>{if(header!=='Bearer authored-token')throw new Error('unauthorized');return 'owner-a';}}));server.listen(0,'127.0.0.1');await once(server,'listening');try{const address=server.address();if(!address||typeof address==='string')throw new Error('address');const response=await fetch(`http://127.0.0.1:${address.port}/v1/features`,{method:'POST',headers:{authorization:'Bearer authored-token','content-type':'application/json'},body:JSON.stringify({contractVersion:'dryrun.ai/1',requestID:'request-a',synthetic:true,role:'preparation',context})});return {status:response.status,body:await response.json()};}finally{server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));}}
it('delivers a catalog task through actual HTTP/tool provenance and one repair without erasing it',async()=>{
 let turns=0;const provider:AgentProvider={async turn(request){turns++;if(turns===1){const read=call();return {steps:[read],calls:[read],text:'',usage:null};}if(turns===3){const repair=JSON.stringify(request.history.at(-1));expect(repair).toContain('task-a');expect(repair).toContain('context.constraints.transport');expect(repair).toContain('recorded');expect(repair).toContain('full');}return {steps:[],calls:[],text:JSON.stringify(proposal(turns===2?['context.fabricated']:undefined)),usage:null};}};
 const result=await http(provider,input());expect(turns).toBe(3);expect(result.status).toBe(200);expect(result.body.status).toBe('completed');expect(result.body.proposal.tasks).toHaveLength(1);expect(result.body.proposal.tasks[0].id).toBe('task-a');expect(result.body.proposal.tasks[0].evidenceIDs).toEqual(['context.constraints.transport']);
});
it.each(['context.fabricated','context.medical.instructions'])('rejects fabricated or unread filtered provenance %s',async evidence=>{let turns=0;const provider:AgentProvider={async turn(){turns++;if(turns===1){const read=call();return {steps:[read],calls:[read],text:'',usage:null};}return {steps:[],calls:[],text:JSON.stringify(proposal([evidence])),usage:null};}};const result=await http(provider,input());expect(result.body.status).toBe('unavailable');expect(turns).toBe(3);});
it('rejects erased tasks when applicable unfinished catalog work exists',async()=>{let turns=0;const provider:AgentProvider={async turn(){turns++;if(turns===1){const read=call();return {steps:[read],calls:[read],text:'',usage:null};}return {steps:[],calls:[],text:JSON.stringify(proposal([],false)),usage:null};}};expect((await http(provider,input())).body.status).toBe('unavailable');});
it.each(['satisfied','completed'])('permits honest no-action when catalog work is %s under host inputs',async state=>{let turns=0;const provider:AgentProvider={async turn(){turns++;if(turns===1){const read=call();return {steps:[read],calls:[read],text:'',usage:null};}return {steps:[],calls:[],text:JSON.stringify(proposal([],false)),usage:null};}};const context={...input(),...(state==='completed'?{completedTaskIDs:['task-a']}:{allowedActionIDs:[]})};expect((await http(provider,context)).body.status).toBe('completed');});
it('retains exposure/status and scopes fragments to the parent snapshot without admitting unseen records',()=>{
 const large={...facts[0]!,value:'x'.repeat(150000)};const reader=authorizedContextReader({...binding,version:'dryrun.private-context/1',consent:true,records:[large,facts[1]]},'owner-a',binding);
 expect(reader.evidence('owner-a',binding)).toEqual([]);reader.read({snapshotID:'snapshot-a',sections:['constraints']});expect(reader.evidence('owner-a',binding)[0]?.exposure).toBe('metadata');
 reader.read({snapshotID:'snapshot-a',sections:['constraints'],recordID:large.id,valuePath:[]});expect(reader.evidence('owner-a',binding)[0]).toMatchObject({id:large.id,status:'recorded',exposure:'fragment',snapshotID:'snapshot-a',valuePaths:[[]]});
 expect(reader.evidence('owner-a',binding).some(record=>record.id===facts[1]!.id)).toBe(false);expect(()=>reader.read({snapshotID:'snapshot-a',sections:['constraints'],recordID:facts[1]!.id,valuePath:[]})).toThrow('context_record_not_in_query');
 expect(()=>reader.evidence('owner-b',binding)).toThrow('context_authorization_required');expect(()=>reader.evidence('owner-a',{...binding,snapshotID:'stale'})).toThrow();expect(()=>reader.read({snapshotID:'stale',sections:['constraints']})).toThrow();
 reader.read({snapshotID:'snapshot-a',sections:['medical']});expect(reader.evidence('owner-a',binding).find(record=>record.id===facts[1]!.id)?.status).toBe('not_recorded');
});
it('rejects stale full snapshot binding over HTTP before any provider turn',async()=>{
 let calls=0;const provider:AgentProvider={async turn(){calls++;throw new Error('must_not_run');}};
 const context=structuredClone(input());context.contextBinding={...context.contextBinding,revisions:{...context.contextBinding.revisions,stateFingerprint:'stale-state'}};expect(context.privateContext.revisions.stateFingerprint).toBe('state-a');expect(context.contextBinding.revisions).not.toEqual(context.privateContext.revisions);
 const result=await http(provider,context);expect(result.body.status).toBe('rejected');expect(calls).toBe(0);
});
it('does not accept metadata-only oversized values as unseen full task evidence',async()=>{
 const context={...input(),privateContext:{...input().privateContext,records:[{...facts[0]!,value:'x'.repeat(150000)}]}};let calls=0;
 const provider:AgentProvider={async turn(){calls++;if(calls===1){const read=call();return {steps:[read],calls:[read],text:'',usage:null};}return {steps:[],calls:[],text:JSON.stringify(proposal()),usage:null};}};
 expect((await http(provider,context)).body.status).toBe('unavailable');
});

it('retains critical medical-backup validation despite legitimate retrieved provenance',async()=>{
 let turns=0;const provider:AgentProvider={async turn(){turns++;if(turns===1){const read=call();return {steps:[read],calls:[read],text:'',usage:null};}return {steps:[],calls:[],text:JSON.stringify(proposal()),usage:null};}};
 const context={...input(),allowedActionIDs:['prep.transport','prep.medicalBackup'],household:{...input().household,equipment:[{id:'device-a',essential:true,powerRequired:true,documentation:'missing'}]}};
 expect((await http(provider,context)).body.status).toBe('unavailable');expect(turns).toBe(3);
});
