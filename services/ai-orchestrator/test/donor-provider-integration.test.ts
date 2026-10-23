// Authored synthetic contract cases. No recorded responses or replay assets.
import {it,expect} from 'vitest';
import {researchBriefFromPlan} from '../src/resource-discovery.js';
import {GeminiPrimaryFallback} from '../src/provider-fallback.js';
import {GroqClient} from '../src/groq.js';
import {ProviderFailure} from '../src/provider-failure.js';
import {FeatureRunner,preparationOutput} from '../src/features.js';
import type {AgentProvider,History} from '../src/provider.js';

it('restored public discovery projection excludes private task narrative and medication/helper facts',()=>{
 const brief=researchBriefFromPlan({id:'plan-a',taskID:'task-a',dependencyIDs:['private-equipment-a'],hazardIDs:['water-outage'],category:'pharmacy',purpose:'Private medicine and person narrative',mandatoryCapabilities:['Private helper label'],unknowns:['Private care instruction'],travelMode:'transit',maximumDistanceKm:8,expansionLimit:1,requiredEvidence:['Private note'],cloudReturnPolicy:'local_only'},{city:'Synthetic City',administrativeArea:'Synthetic State',countryCode:'US'},true);
 expect(Object.keys(brief).sort()).toEqual(['capabilities','limitedBudget','locality','maximumDistanceKm','taskID','travelMode']);expect(JSON.stringify(brief)).not.toContain('Private');expect(brief.capabilities).toEqual(['pharmacy']);
});
it('restored consented fallback retains canonical private facts and advances attempt generation once',async()=>{
 let body:any;const transport:typeof fetch=async(_url,options)=>{body=JSON.parse(String(options?.body));return new Response(JSON.stringify({choices:[{message:{content:'{"synthetic":true}'}}],usage:{total_tokens:2}}),{status:200,headers:{'Content-Type':'application/json'}});};
 const primary:AgentProvider={async turn(){throw new ProviderFailure('rate_limit','gemini',429,undefined,undefined,'provider_rate_limited');}};
 const router=new GeminiPrimaryFallback(primary,new GroqClient('authored-key','openai/gpt-oss-120b',transport));
 const signal=new AbortController().signal;const provider=router.scope({signal,providers:['gemini','groq'],capability:'privateText',maximumCalls:3});expect(provider.attemptGeneration).toBe(0);
 const history:History=[{type:'user_input',content:[{type:'text',text:JSON.stringify({snapshot:'authored',medication:'Synthetic medicine',storageInstructions:'Synthetic recorded instruction',helperPersonID:'helper-a'})}]}];
 const result=await provider.turn({signal,history,instruction:'Authored synthetic fallback case',tools:[],outputSchema:{type:'object',properties:{synthetic:{type:'boolean'}},required:['synthetic'],additionalProperties:false}});
 expect(JSON.parse(result.text)).toEqual({synthetic:true});expect(provider.attemptGeneration).toBe(1);expect(JSON.stringify(body.messages)).toContain('Synthetic recorded instruction');expect(JSON.stringify(body.messages)).toContain('helper-a');
});
it('fallback does not send an image operation to Groq or bypass missing consent',async()=>{
 let sent=0;const transport:typeof fetch=async()=>{sent++;throw new Error('should_not_send');};const primary:AgentProvider={async turn(){throw new ProviderFailure('rate_limit','gemini',429,undefined,undefined,'provider_rate_limited');}};
 const router=new GeminiPrimaryFallback(primary,new GroqClient('authored-key','openai/gpt-oss-120b',transport));const signal=new AbortController().signal;
 for(const options of [{providers:['gemini'],capability:'privateText' as const},{providers:['gemini','groq'],capability:'image' as const}])await expect(router.scope({signal,...options}).turn({signal,history:[],instruction:'synthetic',tools:[]})).rejects.toThrow();expect(sent).toBe(0);
});
it('restored debrief/drill roles validate household-linked task choices',async()=>{
 const base={household:{revision:1,people:[],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[]},tasks:[],gaps:[],allowedActionIDs:[],allowedCriterionIDs:[],debrief:{scenarioID:'water-outage'}};
 const provider:AgentProvider={async turn(input){return {steps:[],text:input.instruction.startsWith('DryRun debrief')?JSON.stringify({summary:'This synthetic rehearsal leaves preparation details to review.',focusTaskIDs:[]}):JSON.stringify({reason:'Practice the recorded household choices.',choiceTaskIDs:[]}),calls:[],usage:null};}};
 expect(await new FeatureRunner(provider).run('debrief',base)).toHaveProperty('focusTaskIDs');expect(await new FeatureRunner(provider).run('drillSetup',base)).toHaveProperty('choiceTaskIDs');
 expect(preparationOutput.safeParse({tasks:[{id:'bespoke-a',actionID:'prep.bespoke',criterionID:'unscored',subjectID:'household',why:'Authored',evidenceIDs:['household-needs'],completionPredicates:[],editor:'family',dependencyIDs:[],priority:2,bespoke:{title:'Review a recorded dependency',fact:'Authored fact',implication:'Authored implication',action:'Authored action',completionCheck:'Authored check'}}],inventoryObservations:[],question:null}).success).toBe(true);
});
