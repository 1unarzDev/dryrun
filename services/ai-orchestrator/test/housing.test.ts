import {readFile} from 'node:fs/promises';
import {expect,it} from 'vitest';
import {FeatureRunner,featureContext,scene,siteHazardContext} from '../src/features.js';
import {inspectOutput} from '../src/output-quality.js';
it('accepts actual host housing, windows, markers and person-specific baseline routes',async()=>{
 const fixture=JSON.parse(await readFile('../../fixtures/ai/housing-layout-live.json','utf8'));
 for(const r of fixture.results){const s=scene.parse(r.context.scene);expect(s.schemaVersion).toBe('dryrun.home-scene/2');if(s.schemaVersion==='dryrun.home-scene/2'){expect(s.planningRoutes?.length).toBe(1);expect(s.objects.some(a=>a.kind==='fireExtinguisher')).toBe(r.id.startsWith('twostory')?false:true);}}
 const context=fixture.outputs[0].context;expect(featureContext.safeParse(context).success).toBe(true);
 for(const field of ['latitude','longitude','elevationMeters','routes','address'])expect(siteHazardContext.safeParse({...context.household.site,[field]:'private'}).success).toBe(false);
});
it('keeps a manufactured-home advance shelter task ahead of generic shopping and fixes electric-CO causation',async()=>{
 const data=JSON.parse(await readFile('../../fixtures/ai/housing-layout-live.json','utf8')).outputs[1].context;
 const co=data.taskCatalog.find((t:any)=>t.actionID==='prep.coAlarms');
 const shelter={...co,id:'prep.shelterPlan',actionID:'prep.shelterPlan',subjectID:'manufacturedAdvancePlan',criterionID:'shelter',editor:'meetingPlace',priority:0};
 data.taskCatalog.push(shelter);data.allowedActionIDs.push(shelter.actionID);
 const runner=new FeatureRunner({async turn(){return {steps:[],calls:[],usage:{},text:JSON.stringify({selected:[{candidateID:co.id,why:'Monitor the electric heater for CO.',evidenceIDs:['household-needs']}],inventoryObservations:[],question:null})}}});
 const output:any=await runner.run('preparation',data);
 expect(output.tasks[0].actionID).toBe('prep.shelterPlan');expect(output.tasks[0].why).toContain('in advance');
 expect(output.tasks.find((t:any)=>t.actionID==='prep.coAlarms').why).toContain('do not produce CO');
});
it('flags length/depth for review without rewriting or truncating model content',()=>{
 const text='Check supplies.';const audit=inspectOutput('preparation',{tasks:[{why:text}]});
 expect(audit[0]?.flags).toContain('review_depth');expect(audit[0]?.text).toBe(text);
 const long='Important detail. '.repeat(100);expect(inspectOutput('director',{purpose:long})[0]?.text).toBe(long);
});
it('keeps shelter/drill resource explanations tied to official planning rather than invented protective purchases',async()=>{
 const data=JSON.parse(await readFile('../../fixtures/ai/housing-layout-live-v2.json','utf8')).outputs[2];
 const runner=new FeatureRunner({async turn(){return {steps:[],calls:[],usage:{},text:JSON.stringify(data.resources)}}});
 const result:any=await runner.run('resources',{...data.context,tasks:data.preparation.tasks});
 for(const plan of result.searchPlans){
  const task=data.preparation.tasks.find((t:any)=>t.id===plan.taskID);
  if(task.actionID==='prep.shelterPlan'||task.actionID==='prep.fireDrill'){
   expect(plan.category).toBe('emergencyManagement');expect(plan.mandatoryCapabilities).toEqual(['Official preparedness guidance']);
   expect(plan.purpose).toMatch(/does not establish/);
  }
 }
});

it('does not certify an upstairs bathroom or outsource exit inspection to a store',async()=>{
 const recorded=JSON.parse(await readFile('../../fixtures/ai/housing-features-live-v4.json','utf8'));
 for(const sample of ['apartment-complex','manufactured']){
  const data=recorded.outputs.find((o:any)=>o.sample===sample);
  const selection={selected:data.preparation.tasks.map((t:any)=>({candidateID:t.id,why:t.why,evidenceIDs:t.evidenceIDs})),inventoryObservations:[],question:null};
  const runner=new FeatureRunner({async turn(){return {steps:[],calls:[],usage:{},text:JSON.stringify(selection)}}});
  const prep:any=await runner.run('preparation',data.context);
  const shelter=prep.tasks.find((t:any)=>t.actionID==='prep.shelterPlan');
  expect(shelter.why).not.toContain('most suitable');
  expect(shelter.why).toMatch(sample==='manufactured'?/before a tornado warning/:/does not establish tornado protection/);
  const resources=new FeatureRunner({async turn(){return {steps:[],calls:[],usage:{},text:JSON.stringify(data.resources)}}});
  const result:any=await resources.run('resources',{...data.context,tasks:prep.tasks});
  for(const plan of result.searchPlans)if(prep.tasks.find((t:any)=>t.id===plan.taskID)?.actionID==='prep.clearExits'){
   expect(plan.category).toBe('emergencyManagement');expect(plan.purpose).toContain('Inspect the actual paths locally');
   expect(plan.purpose).toContain('cannot verify clearance');
  }
 }
});

it('replays latest provider wording without promoting a locked bathroom or declaring all upstairs windows unusable',async()=>{
 const recorded=JSON.parse(await readFile('../../fixtures/ai/housing-features-live-v5.json','utf8'));
 for(const data of recorded.outputs){
  const selection={selected:data.preparation.tasks.map((t:any)=>({candidateID:t.id,why:t.why,evidenceIDs:t.evidenceIDs})),inventoryObservations:[],question:data.preparation.question};
  const runner=new FeatureRunner({async turn(){return {steps:[],calls:[],usage:{},text:JSON.stringify(selection)}}});
  const result:any=await runner.run('preparation',data.context);
  expect(result.question).not.toMatch(/locked/);
  const exits=result.tasks.find((t:any)=>t.actionID==='prep.clearExits');
  if(exits){expect(exits.why).toContain('do not establish a walking exit');expect(exits.why).not.toContain('not safe exits');}
 }
});

it('preserves shared-stair status and compiles a drill rationale without invented independence',async()=>{
 const data=JSON.parse(await readFile('../../fixtures/ai/housing-features-live-v7.json','utf8')).outputs[2];
 const route=data.context.scene.planningRoutes[0];
 route.alternativeStatus='sharesChokepoint';route.alternativeConnectorIDs=['cn-stairs'];route.sharedChokepointIDs=['cn-stairs'];
 expect(featureContext.safeParse(data.context).success).toBe(true);
 const selection={selected:data.preparation.tasks.map((t:any)=>({candidateID:t.id,why:t.why,evidenceIDs:t.evidenceIDs})),inventoryObservations:[],question:null};
 const runner=new FeatureRunner({async turn(input){expect(input.instruction).toContain('elevators are excluded from fire egress');return {steps:[],calls:[],usage:{},text:JSON.stringify(selection)}}});
 const output:any=await runner.run('preparation',data.context);
 const drill=output.tasks.find((t:any)=>t.actionID==='prep.fireDrill');
 expect(drill.why).toContain('shares a chokepoint');expect(drill.why).toContain('does not establish');expect(drill.why).not.toContain('two primary');
 route.alternativeStatus='inventedSafe';expect(featureContext.safeParse(data.context).success).toBe(false);
});

it('does not turn a smoke-alarm test into a guarantee of future fire performance',async()=>{
 const data=JSON.parse(await readFile('../../fixtures/ai/housing-features-live-v8.json','utf8')).outputs[2];
 const selection={selected:data.preparation.tasks.map((t:any)=>({candidateID:t.id,why:t.why,evidenceIDs:t.evidenceIDs})),inventoryObservations:[],question:null};
 const runner=new FeatureRunner({async turn(){return {steps:[],calls:[],usage:{},text:JSON.stringify(selection)}}});
 const output:any=await runner.run('preparation',data.context);
 const alarm=output.tasks.find((t:any)=>t.actionID==='prep.smokeAlarms');
 expect(alarm.why).toContain('without guaranteeing');expect(alarm.why).not.toContain('ensures');
});
