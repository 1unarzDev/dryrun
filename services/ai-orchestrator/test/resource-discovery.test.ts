import {it,expect} from 'vitest';
import {ResourceDiscovery,researchBrief} from '../src/resource-discovery.js';
import type {AgentProvider} from '../src/provider.js';
const brief={taskID:'private-task-id',locality:{city:'Denver',administrativeArea:'Colorado',countryCode:'US'},capabilities:['cooling','stepFree'],travelMode:'transit',maximumDistanceKm:15,limitedBudget:true};
const comparison={options:[{name:'Synthetic municipal option',locality:'Denver',documentedService:'Dated cooling program published',whyUseful:'A cooling option addresses the linked gap',nextAction:'Check current program hours before traveling',unknowns:['Activation today','Step-free access details'],sourceURLs:['https://example.gov/cooling'],publishedOrUpdatedAt:null}],comparison:'Compare current hours and reachable transit options',limitations:['Published program is not proof of current activation']};
it('isolates public discovery, preserves attribution, and prevents database/map/PDF reuse',async()=>{
 const requests:Parameters<AgentProvider['turn']>[0][]=[];
 const provider:AgentProvider={async turn(input){requests.push(input);return requests.length===1?{text:'Synthetic attributed cooling finding',calls:[],usage:{},steps:[{type:'model_output',content:[{type:'text',text:'Dated program',annotations:[{type:'url_citation',url:'https://example.gov/cooling',title:'Program',start_index:0,end_index:13}]}]},{type:'google_search_result',call_id:'search',result:[{search_suggestions:'<div>provider suggestion</div>'}]},{type:'url_context_result',call_id:'read',result:[{url:'https://example.gov/cooling',status:'success'}]}]}:{text:JSON.stringify(comparison),steps:[],calls:[],usage:{}};}};
 const result=await new ResourceDiscovery(provider).discover(brief);
 expect(JSON.stringify(requests[0]?.history)).not.toContain('private-task-id');
 expect(requests[0]?.tools.map(t=>t.type)).toEqual(['google_search','url_context']);
 expect(result.attribution.searchSuggestions).toEqual(['<div>provider suggestion</div>']);
 expect(result.permissions).toEqual({presentation:'attributed_companion',mapPins:'native_independent_candidates_only',persistentResourceDatabase:false,pdfExport:false});
 expect(result.taskID).toBe('private-task-id');expect(result.execution.calls).toBe(2);
});
it('rejects private payload fields before spending and uncited normalized claims after research',async()=>{
 expect(researchBrief.safeParse({...brief,household:{medication:'private'}}).success).toBe(false);
 let calls=0;const provider:AgentProvider={async turn(){calls++;return calls===1?{text:'No supported sources',steps:[],calls:[],usage:{}}:{text:JSON.stringify(comparison),steps:[],calls:[],usage:{}};}};
 await expect(new ResourceDiscovery(provider).discover({...brief,address:'private street'})).rejects.toThrow();expect(calls).toBe(0);
 await expect(new ResourceDiscovery(provider).discover(brief)).rejects.toThrow('unsupported_research_source');expect(calls).toBe(2);
});
it('retains useful empty results and enforces a finite call budget',async()=>{
 const provider:AgentProvider={async turn(){return {text:JSON.stringify({options:[],comparison:'No supported named option found',limitations:['Use independent native search']}),steps:[],calls:[],usage:{}};}};
 const discovery=new ResourceDiscovery(provider,2);
 expect((await discovery.discover(brief)).comparison.options).toEqual([]);
 await expect(discovery.discover(brief)).rejects.toThrow('research_budget');
});
it('derives public needs without leaking private planner narrative',async()=>{
 const {researchBriefFromPlan}=await import('../src/resource-discovery.js');
 const plan={id:'plan',taskID:'private-task',dependencyIDs:['private-member'],hazardIDs:['heat-grid-strain'],category:'warmingCooling',purpose:'Private medication narrative',mandatoryCapabilities:['Private disability narrative'],unknowns:['Private address'],travelMode:'assistance',maximumDistanceKm:10,expansionLimit:1,requiredEvidence:['Current program information'],cloudReturnPolicy:'local_only'};
 const minimized=researchBriefFromPlan(plan,brief.locality,true);
 expect(minimized.capabilities).toEqual(['cooling']);expect(JSON.stringify(minimized)).not.toContain('narrative');expect(JSON.stringify(minimized)).not.toContain('private-member');
});
it('does not let an ignored-abort primary research request consume the whole fallback deadline',async()=>{
 let release!:(reply:any)=>void,primarySignal:AbortSignal|undefined,fallbackCalls=0;
 const discovery=new ResourceDiscovery({async turn(input){primarySignal=input.signal;return new Promise(resolve=>release=resolve);}},4,()=>new Date(),{async discover(raw:unknown,operation:import('../src/groq.js').ProviderOperation){fallbackCalls++;expect(operation.generation).toBe(1);expect(operation.calls).toBe(1);return {provider:{name:'groq'},execution:{calls:operation.calls},comparison};}} as any,20);
 const result=await discovery.discover(brief);expect(result.provider.name).toBe('groq');expect(fallbackCalls).toBe(1);expect(primarySignal?.aborted).toBe(true);
 release({text:'Late public answer',calls:[],steps:[],usage:{}});await Promise.resolve();await Promise.resolve();expect(discovery.calls).toBe(1);
});
