// Authored synthetic inputs only (fictional household). Verifies host pre-packed context, not model quality.
import {it,expect} from 'vitest';
import {FeatureRunner} from '../src/features.js';
import type {AgentProvider} from '../src/provider.js';
const binding={scope:{householdID:'family-a',origin:'example',sessionID:'scope-a'},revisions:{household:1,inventory:1,stateFingerprint:'state-a'},snapshotID:'snapshot-a'};
const facts=[{id:'context.constraints.transport',section:'constraints',subjectID:'family-a',sourcePath:'transport',status:'recorded',value:{accessibleVehicle:false}},{id:'context.medical.instructions',section:'medical',subjectID:'person-a',sourcePath:'instructions',status:'not_recorded'}];
const task={id:'task-a',actionID:'prep.transport',criterionID:'meetups',subjectID:'household',why:'Review recorded assistance before arranging transport.',evidenceIDs:['legacy-a'],completionPredicates:['transport'],editor:'meetingPlace',dependencyIDs:[],priority:1};
const input=()=>({household:{revision:1,people:[],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[{id:'legacy-a',origin:'userConfirmed',status:'confirmed',sourceIDs:[],fieldIDs:[]}]},tasks:[],gaps:[],taskCatalog:[task],allowedActionIDs:['prep.transport'],allowedCriterionIDs:['meetups'],contextBinding:binding,privateContext:{...binding,version:'dryrun.private-context/1',consent:true,records:facts}});
const proposal={tasks:[{...task,evidenceIDs:['context.constraints.transport']}],inventoryObservations:[],question:null};

it('answers preparation in one model turn from host pre-packed records, with provenance intact',async()=>{
 const seen:{tools:number;packed:boolean}[]=[];
 const provider:AgentProvider={async turn(request){seen.push({tools:request.tools.length,packed:JSON.stringify(request.history[0]).includes('hostRetrievedRecords')&&JSON.stringify(request.history[0]).includes('context.constraints.transport')});return {steps:[],calls:[],text:JSON.stringify(proposal),usage:null};}};
 const output:any=await new FeatureRunner(provider,40,undefined,{prepackContext:true}).run('preparation',input(),AbortSignal.timeout(5000),[],'owner-a');
 expect(seen).toEqual([{tools:1,packed:true}]);
 expect(output.tasks[0].evidenceIDs).toEqual(['context.constraints.transport']);
});
it('still rejects provenance the host never released when pre-packing is off',async()=>{
 let turns=0;const provider:AgentProvider={async turn(){turns++;return {steps:[],calls:[],text:JSON.stringify(proposal),usage:null};}};
 await expect(new FeatureRunner(provider,40).run('preparation',input(),AbortSignal.timeout(5000),[],'owner-a')).rejects.toThrow();
 expect(turns).toBeGreaterThan(0);
});
it('caps extra retrieval at one tool turn after pre-packing',async()=>{
 let turns=0;const offered:number[]=[];
 const provider:AgentProvider={async turn(request){turns++;offered.push(request.tools.length);if(turns===1){const read={type:'function_call' as const,id:'read-a',name:'read_household_context',arguments:{snapshotID:'snapshot-a',sections:['medical']}};return {steps:[read],calls:[read],text:'',usage:null};}return {steps:[],calls:[],text:JSON.stringify(proposal),usage:null};}};
 await new FeatureRunner(provider,40,undefined,{prepackContext:true}).run('preparation',input(),AbortSignal.timeout(5000),[],'owner-a');
 expect(offered).toEqual([1,0]);
});
