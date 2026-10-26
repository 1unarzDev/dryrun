import {it,expect} from 'vitest';
import {CodexProvider,type CodexCapabilities} from '../src/codex-provider.js';
import {codexRuntimeVersion,codexEndpoint} from '../src/codex-runtime.js';
import {configuredProviderConsent,scopeProvider,SpendBudget,type AgentProvider} from '../src/provider.js';
import {OwnerWindowQuota} from '../src/owner-window-quota.js';
import {FeatureRunner} from '../src/features.js';
import {ResourceDiscovery} from '../src/resource-discovery.js';
import {Gateway} from '../src/gateway.js';

const capabilities:CodexCapabilities={runtimeVersion:codexRuntimeVersion,endpoint:codexEndpoint,model:'synthetic-model',reviewReportID:'report-synthetic-only',streaming:true,tools:true,continuation:true,structuredOutput:true,lifecycle:true,images:false,research:false};
const feature={household:{revision:1,people:[],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[]},tasks:[],gaps:[],allowedActionIDs:[],allowedCriterionIDs:[],debrief:{scenarioID:'water-outage'}};
it('rejects explicit Gemini/Groq consent and unsupported images before Codex launch',async()=>{
 let launches=0;const provider=new CodexProvider('authored-key',capabilities,async()=>{launches++;throw new Error('authored_transport');});
 for(const providers of [['gemini'],['groq'],['gemini','groq']])await expect(new FeatureRunner(provider).run('debrief',feature,undefined,[],'owner-a',providers)).rejects.toMatchObject({kind:'unsupported',diagnostic:'provider_consent_required'});
 expect(()=>provider.scope({signal:new AbortController().signal,providers:['codex'],capability:'image'})).toThrow();expect(launches).toBe(0);
 expect(configuredProviderConsent(provider)).toEqual(['codex']);expect(configuredProviderConsent(provider,['gemini'])).toEqual(['gemini']);
 const allowed=provider.scope({signal:new AbortController().signal,providers:['codex'],capability:'privateText'});await expect(allowed.turn({signal:new AbortController().signal,history:[],instruction:'authored',tools:[]})).rejects.toThrow('codex_unavailable');expect(launches).toBe(1);
});
it('does not route an unscoped identified Gemini provider under Codex-only consent',()=>{
 let calls=0;const provider:AgentProvider={providerID:'gemini',async turn(){calls++;throw new Error('should_not_run');}};
 expect(()=>scopeProvider(provider,{providers:['codex'],signal:new AbortController().signal,capability:'privateText'})).toThrow();expect(calls).toBe(0);
});
it('renews bounded per-owner quota over more than100 windows and isolates other owners',()=>{
 let now=0;const quota=new OwnerWindowQuota(2,{now:()=>now,windowMs:1000});
 for(let i=0;i<130;i++){quota.consume('owner-a');quota.consume('owner-a');expect(()=>quota.consume('owner-a')).toThrow();quota.consume('owner-b');now+=1001;}
});
it('renews the configured global cost ceiling without charging a late old reservation to a new window',()=>{
 let now=0;const budget=new SpendBudget(0.025,{now:()=>now,windowMs:1000});const old=budget.reserve(0.02);expect(()=>budget.reserve(0.01)).toThrow('spend_budget');now=1001;budget.reserve(0.02);expect(budget.spentUSD).toBe(0.02);budget.charge({total_input_tokens:5_000_000},'gemini-3.8-flash',0.02,old);expect(budget.spentUSD).toBe(0.02);expect(budget.calls).toBe(1);
});
it('feature call allowance renews without restarting the singleton',async()=>{
 let now=0,calls=0;const provider:AgentProvider={async turn(){calls++;return {steps:[],text:JSON.stringify({summary:'Authored synthetic rehearsal summary.',focusTaskIDs:[]}),calls:[],usage:null};}};
 const runner=new FeatureRunner(provider,1,undefined,{}, {now:()=>now,windowMs:1000});
 await runner.run('debrief',feature,undefined,[],'owner-a');await expect(runner.run('debrief',feature,undefined,[],'owner-a')).rejects.toMatchObject({kind:'rate_limit'});await runner.run('debrief',feature,undefined,[],'owner-b');now=1001;await runner.run('debrief',feature,undefined,[],'owner-a');expect(calls).toBe(3);expect(runner.calls).toBe(3);
});
it('actual research two-call flow renews per owner after its window',async()=>{
 let now=0;const provider:AgentProvider={async turn(input){return {steps:[],text:input.modelRole==='research'?'Authored public-only search response':JSON.stringify({options:[],comparison:'No supported options in synthetic source.',limitations:['Authored unknowns remain.']}),calls:[],usage:null};}};
 const discovery=new ResourceDiscovery(provider,2,()=>new Date(now),undefined,45000,{windowMs:1000});const brief={taskID:'task-a',locality:{city:'Synthetic City',administrativeArea:'Synthetic State',countryCode:'US'},capabilities:['drinkingWater'],travelMode:'walking',maximumDistanceKm:4,limitedBudget:true};
 await discovery.discover(brief,undefined,'owner-a');await expect(discovery.discover(brief,undefined,'owner-a')).rejects.toMatchObject({kind:'rate_limit'});await discovery.discover(brief,undefined,'owner-b');now=1001;await discovery.discover(brief,undefined,'owner-a');expect(discovery.calls).toBe(6);
});
it('director owner-start allowance renews rather than exhausting after12 lifetime starts',async()=>{
 let now=0;const provider:AgentProvider={async turn(){return {steps:[],text:JSON.stringify({commands:[{kind:'requestDecision'}],purpose:'Authored synthetic decision',evidenceIDs:[]}),calls:[],usage:null};}};
 const gateway=new Gateway(provider,()=>now,100);let sequence=0;const request=()=>({contractVersion:'dryrun.ai/1',requestID:'request-'+sequence++,role:'director',synthetic:true,context:{binding:{sessionID:'synthetic-session',revision:0,eventSequence:0,contextDigest:'synthetic-digest',householdRevision:1,homeRevision:0},snapshot:{simMinute:0,resources:{},services:{},unmetRequirements:[],unknowns:[]},profiles:[]}});
 for(let i=0;i<12;i++)await gateway.start('owner-a',request());await expect(gateway.start('owner-a',request())).rejects.toMatchObject({kind:'rate_limit'});await gateway.start('owner-b',request());now=600001;await expect(gateway.start('owner-a',request())).resolves.toBeDefined();
});
