import {it,expect} from 'vitest';
import {readFile} from 'node:fs/promises';
import {GroqClient,ProviderFailure,ProviderOperation,QuotaCircuit,parseGroqResearch,retryDelay,resetDuration} from '../src/groq.js';
import {GroqResourceDiscovery} from '../src/groq-discovery.js';
import {ResourceDiscovery} from '../src/resource-discovery.js';
const fixture=JSON.parse(await readFile('../../fixtures/ai/groq-browser-search-live.json','utf8'));
const brief={taskID:'private-id',locality:{city:'Denver',administrativeArea:'Colorado',countryCode:'US'},capabilities:['cooling','stepFree'],travelMode:'transit',maximumDistanceKm:15,limitedBudget:true};
const signal=()=>AbortSignal.timeout(10000);
it('parses actual sanitized browser response with source text and excludes hidden reasoning',()=>{
 const result=parseGroqResearch(fixture.response);expect(result.searchSteps).toBe(2);expect(result.inspectionSteps).toBe(2);
 expect(result.sources.find(s=>s.inspection==='opened')?.content).toContain('Heat Advisory');
 expect(JSON.stringify(fixture)).not.toContain('reasoning_content');expect(fixture.request.include_reasoning).toBe(false);
});
it('never treats plain assistant links, unresolved citations or requested tools as retrieval',()=>{
 for(const content of ['See https://example.gov/water','Useful option 【9†L1】']){const result=parseGroqResearch({choices:[{message:{content}}]});expect(result.answer).toBe(content);expect(result.sources).toEqual([]);expect(result.searchSteps).toBe(0);}
});
it('handles tool output snippets without optional search_results and preserves actual URLs',()=>{
 const result=parseGroqResearch({choices:[{message:{content:'Qualified answer',executed_tools:[{name:'browser.search',output:'L0: URL: https://example.gov/cooling\nL1: Published seasonal program'}]}}]});
 expect(result.sources[0]?.url).toBe('https://example.gov/cooling');expect(result.sources[0]?.content).toContain('seasonal');
});
it('parses request/token reset units and HTTP Retry-After without per-minute assumptions',()=>{
 expect(resetDuration('2m59.56s')).toBe(179560);expect(resetDuration('1h2m3s5ms')).toBe(3723005);expect(resetDuration('59')).toBeUndefined();
 expect(retryDelay(new Headers({'retry-after':'15'}))).toBe(15000);
 expect(retryDelay(new Headers({'x-ratelimit-remaining-requests':'0','x-ratelimit-reset-requests':'1h','x-ratelimit-remaining-tokens':'0','x-ratelimit-reset-tokens':'2m'}))).toBe(3600000);
});
it('opens quota circuit and permits only one half-open probe',()=>{
 let now=0;const circuit=new QuotaCircuit(()=>now,()=>0);expect(circuit.enter()).toBe(true);circuit.failure(3000);expect(circuit.enter()).toBe(false);now=3001;expect(circuit.enter()).toBe(true);expect(circuit.enter()).toBe(false);circuit.success();expect(circuit.enter()).toBe(true);
});
it('does not reset allowance/deadline on switch and rejects stale same-revision acceptance',()=>{
 const operation=new ProviderOperation(signal(),2,0.10);const deadline=operation.deadline;operation.reserve(0.04);operation.switch();expect(operation.deadline).toBe(deadline);expect(()=>operation.check(0)).toThrow('stale_provider_attempt');expect(()=>operation.switch()).toThrow('provider_switch_budget');operation.reserve(0.04);expect(()=>operation.reserve(0.01)).toThrow('operation_budget');
});
it('rejects invalid credentials/config and unsupported search+schema before spending',async()=>{
 expect(()=>new GroqClient('')).toThrow('groq_configuration');expect(()=>new GroqClient('synthetic','groq/compound')).toThrow('groq_unsupported');
 const op=new ProviderOperation(signal());await expect(new GroqClient('synthetic').request([],op,{search:true,schema:{}})).rejects.toThrow('groq_unsupported');expect(op.calls).toBe(0);
});
it('uses no SDK retries, typed HTTP errors, and respects cancellation even if transport ignores abort',async()=>{
 let calls=0;const client=new GroqClient('synthetic',undefined,async()=>{calls++;return new Response('{}',{status:429,headers:{'retry-after':'12'}});});
 await expect(client.request([],new ProviderOperation(signal(),4,0.1,1000))).rejects.toMatchObject({kind:'rate_limit',retryAfterMs:12000});expect(calls).toBe(1);
 const controller=new AbortController();const stuck=new GroqClient('synthetic',undefined,()=>new Promise(()=>{}));const pending=stuck.request([],new ProviderOperation(controller.signal));controller.abort();await expect(pending).rejects.toMatchObject({kind:'cancelled'});
});
it('stops repeated invalid-credential requests without disabling a working model after an unsupported combination',async()=>{
 let calls=0;const unauthorized=new GroqClient('synthetic',undefined,async()=>{calls++;return new Response('{}',{status:401});});
 for(let i=0;i<2;i++)await expect(unauthorized.request([],new ProviderOperation(signal()))).rejects.toMatchObject({kind:'configuration',status:401});
 expect(calls).toBe(1);
 const compatible=new GroqClient('synthetic',undefined,async()=>{calls++;return Response.json({choices:[{message:{content:'{}'}}]});});
 await expect(compatible.request([],new ProviderOperation(signal()),{search:true,schema:{}})).rejects.toMatchObject({kind:'unsupported'});
 await compatible.request([],new ProviderOperation(signal()));expect(calls).toBe(2);
});
it('classifies actual provider-rejected generated JSON separately from unsupported requests without adapter retries',async()=>{
 const captured=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-extraction-v2-live.json','utf8'));
 const actual=captured.responses.find((r:any)=>r.error?.code==='json_validate_failed').error;
 let calls=0;
 const client=new GroqClient('synthetic',undefined,async()=>{calls++;return Response.json({error:{code:actual.code,message:actual.message}},{status:actual.status});});
 const operation=new ProviderOperation(signal());
 await expect(client.request([],operation,{schema:{type:'object',properties:{}}})).rejects.toMatchObject({kind:'invalid_output',status:400,diagnostic:'json_validate_failed'});
 expect(calls).toBe(1);expect(operation.calls).toBe(1);
 const unsupported=new GroqClient('synthetic',undefined,async()=>Response.json({error:{code:'unsupported_tool'}},{status:400}));
 await expect(unsupported.request([],new ProviderOperation(signal()))).rejects.toMatchObject({kind:'unsupported'});
});
it('repairs generated-output failures once within the shared extraction budget and retains original evidence',async()=>{
 const captured=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-extraction-v2-live.json','utf8'));
 const invalid=captured.responses.find((r:any)=>r.error?.code==='json_validate_failed').error;
 const found={answer:'Untrusted answer',sources:captured.result.attribution.evidence,searchSteps:2,inspectionSteps:2,usage:{}};
 for(const exhausted of [false,true]){
  let calls=0;
  const client=new GroqClient('synthetic',undefined,async()=>{
   calls++;
   if(calls===1||exhausted)return Response.json({error:{code:invalid.code}},{status:400});
   return Response.json(captured.responses[0]); // Actual recorded model output, including rejected sibling.
  });
  const operation=new ProviderOperation(signal(),2);
  const result=await new GroqResourceDiscovery(client,()=>new Date(captured.sourceRetrievedAt)).formatEvidence(found,captured.result.brief,operation,{retrievedAt:captured.result.retrievedAt,expiresAt:captured.result.expiresAt});
  expect(calls).toBe(2);expect(operation.calls).toBe(2);
  expect(result.status).toBe('partial_sourced');expect(result.execution.extractionStatus).toBe('invalid_output');
  expect(result.execution.extractionErrors[0]).toBe('provider_invalid_output:json_validate_failed');
  expect(result.attribution.evidence).toEqual(captured.result.attribution.evidence);
  expect(result.retrievedAt).toBe(captured.result.retrievedAt);expect(result.expiresAt).toBe(captured.result.expiresAt);
  expect(result.comparison.options.map(o=>o.name)).toEqual(exhausted?[]:['Albuquerque City Drug']);
 }
});
it('revalidates actual partial live extraction and its malformed repair without promoting historical status',async()=>{
 const captured=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-extraction-v2-live.json','utf8'));
 let calls=0;
 const client=new GroqClient('synthetic',undefined,async()=>{
  const response=captured.responses[calls++];
  return Response.json(response,{status:response.error?.status??200});
 });
 const result=await new GroqResourceDiscovery(client,()=>new Date(captured.sourceRetrievedAt)).formatEvidence({answer:captured.result.attribution.answer,sources:captured.result.attribution.evidence,searchSteps:2,inspectionSteps:2,usage:{}},captured.result.brief,new ProviderOperation(signal(),2),{retrievedAt:captured.result.retrievedAt,expiresAt:captured.result.expiresAt});
 expect(calls).toBe(2);expect(result.status).toBe('partial_sourced');
 expect(result.comparison.options.map(o=>o.name)).toEqual(['Albuquerque City Drug']);
 expect(result.execution.extractionStatus).toBe('invalid_output');
 expect(result.execution.extractionErrors).toEqual(['Public Health Pharmacy Clinic:unsupported_research_identity_service_binding','provider_invalid_output:json_validate_failed']);
 expect(captured.result.execution.extractionFailure.kind).toBe('unsupported'); // Original capture is immutable history.
});
it('distinguishes operation timeout from an explicit cancellation even when HTTP ignores abort',async()=>{
 const client=new GroqClient('synthetic',undefined,()=>new Promise(()=>{}));
 await expect(client.request([],new ProviderOperation(AbortSignal.timeout(20)))).rejects.toMatchObject({kind:'timeout'});
 const controller=new AbortController(),pending=client.request([],new ProviderOperation(controller.signal));controller.abort();await expect(pending).rejects.toMatchObject({kind:'cancelled'});
});
it('sends public-only brief and performs Groq-only tools-disabled extraction after injected Gemini 429',async()=>{
 const bodies:any[]=[];let primaryCalls=0;
 const client=new GroqClient('synthetic',undefined,async(_url,input)=>{
  const body=JSON.parse(String(input?.body));bodies.push(body);
  if(bodies.length%2===1)return Response.json({choices:[{message:{content:'Synthetic attributed finding',executed_tools:[{name:'browser.search',search_results:{results:[{url:'https://example.gov/center',title:'Synthetic Civic Center',content:'Synthetic Civic Center offers a published seasonal heat relief program during business hours.'}]}},{name:'browser.open',search_results:{results:[{url:'https://example.gov/center',title:'Synthetic Civic Center',content:'Synthetic Civic Center offers a published seasonal heat relief program during business hours.'}]}}]}}]});
  const source=JSON.parse(body.messages[1].content).sources.find((s:any)=>s.inspection==='opened');
  return Response.json({choices:[{message:{content:JSON.stringify({options:[{name:'Synthetic Civic Center',locality:'Denver',documentedService:'offers a published seasonal heat relief program during business hours.',whyUseful:'Published heat relief addresses the cooling need.',nextAction:'Check current activation, the selected center and transit/access before travel.',unknowns:['Current activation and step-free access are unverified'],publishedOrUpdatedAt:null,support:[JSON.parse(body.messages[1].content).passages.find((p:any)=>p.sourceID===source.id).id]}],comparison:'Recreation centers have normal business hours; library branches are another published option.',limitations:['No route, transport, opening or access guarantee']})}}]});
 });
 const discovery=new ResourceDiscovery({async turn(){primaryCalls++;throw new Error('provider_rate_limited');}},12,()=>new Date(),new GroqResourceDiscovery(client));
 const result=await discovery.discover(brief);expect(result.status).toBe('live_sourced');expect(result.provider.name).toBe('groq');expect(result.comparison.options).toHaveLength(1);
 expect(JSON.stringify(bodies)).not.toContain('private-id');expect(bodies[0].tools).toEqual([{type:'browser_search'}]);expect(bodies[1].tools).toBeUndefined();expect(bodies[1].tool_choice).toBe('none');expect(bodies[1].response_format.json_schema.strict).toBe(true);expect(bodies[1].store).toBeUndefined();
 await discovery.discover(brief);expect(primaryCalls).toBe(1); // Research quota circuit, not a second primary probe.
});
it('retains attributable evidence if extraction fails rather than fabricating success',async()=>{
 let count=0;const client=new GroqClient('synthetic',undefined,async()=>{count++;return count===1?Response.json(fixture.response):new Response('{}',{status:429});});
 const result=await new GroqResourceDiscovery(client).discover(brief,new ProviderOperation(signal()));
 expect(result.status).toBe('partial_sourced');expect(result.comparison.options).toEqual([]);expect(result.attribution.evidence.length).toBeGreaterThan(0);expect(result.execution.extractionStatus).toBe('unavailable');expect(count).toBe(2);
});
it('retains supported named options while replacing unsupported publication dates with unknown',async()=>{
 let calls=0;
 const client=new GroqClient('synthetic',undefined,async(_url,input)=>{
  calls++;const body=JSON.parse(String(input?.body));
  const passages=JSON.parse(body.messages[1].content).passages;
  const options=['Civic Center','Town Library'].map((name,index)=>({name,locality:'Denver',documentedService:index?'Seasonal cooling during staffed hours.':'Seasonal cooling during business hours.',whyUseful:'A published cooling lead to investigate for the linked preparation.',nextAction:'Confirm current activation, access and feasible transport before travel.',unknowns:['Current activation, opening, access and transport are unverified.'],publishedOrUpdatedAt:index?'2023-02-15':'2026-09-18',support:passages.filter((p:any)=>p.quote.includes(name)).map((p:any)=>p.id)}));
  return Response.json({choices:[{message:{content:JSON.stringify({options,comparison:'The center lists business hours; the library lists staffed hours. Neither establishes current activation.',limitations:['Current activation is unverified.']})}}]});
 });
 const found={answer:'Unsupported interpretation: both pages updated today.',sources:[{id:'a',url:'https://example.gov/center',title:'Center',inspection:'opened' as const,content:'Civic Center. Seasonal cooling during business hours. Last updated: 2026-09-18'},{id:'b',url:'https://example.gov/library',title:'Library',inspection:'opened' as const,content:'Town Library. Seasonal cooling during staffed hours. Copyright 2023.'}],searchSteps:1,inspectionSteps:2,usage:{}};
 const result=await new GroqResourceDiscovery(client,()=>new Date('2026-10-20T05:00:00Z')).formatEvidence(found,brief,new ProviderOperation(signal()),{retrievedAt:'2026-10-20T04:30:00Z',expiresAt:'2026-10-20T05:30:00Z',cached:false});
 expect(calls).toBe(1);expect(result.status).toBe('live_sourced');expect(result.comparison.options).toHaveLength(2);
 expect(result.comparison.options.map(o=>o.publishedOrUpdatedAt)).toEqual(['2026-09-18',null]);
 expect(result.comparison.limitations.join(' ')).toContain('Town Library');
 expect(result.retrievedAt).toBe('2026-10-20T04:30:00.000Z');expect(result.expiresAt).toBe('2026-10-20T05:30:00Z');
});
it('charges fallback search and extraction to the same service allowance as primary attempts',async()=>{
 let primary=0,secondary=0;
 const client=new GroqClient('synthetic',undefined,async()=>{secondary++;return Response.json(fixture.response);});
 const discovery=new ResourceDiscovery({async turn(){primary++;throw new Error('provider_rate_limited');}},2,()=>new Date(),new GroqResourceDiscovery(client));
 const result=await discovery.discover(brief);
 expect(result.status).toBe('partial_sourced');// Renewable owner-window quota (shared by primary and fallback) reports a typed operation rate limit.
 expect(result.execution).toMatchObject({extractionFailure:{kind:'rate_limit'},totalOperationCalls:2});
 expect(discovery.calls).toBe(2);expect(primary).toBe(1);expect(secondary).toBe(1);
 await expect(discovery.discover(brief)).rejects.toThrow('operation_rate_limit');expect(secondary).toBe(1);
});
it('preserves a supported option when its sibling is invented and the repair hits quota',async()=>{
 let calls=0;const client=new GroqClient('synthetic',undefined,async(_url,request)=>{
  calls++;if(calls===1)return Response.json({choices:[{message:{content:'Synthetic attributed finding',executed_tools:[{name:'browser.search',search_results:{results:[{url:'https://example.gov/center',title:'Civic Center',content:'Civic Center offers seasonal cooling during business hours.'}]}}]}}]});
  if(calls===3)return new Response('{}',{status:429});
  const passage=JSON.parse(JSON.parse(String(request?.body)).messages[1].content).passages[0];
  const option={name:'Civic Center',locality:'Denver',documentedService:'offers seasonal cooling during business hours.',whyUseful:'A seasonal cooling lead; current activation is unverified.',nextAction:'Check activation, access and transit before travel.',unknowns:['Current activation, site accessibility and transport'],publishedOrUpdatedAt:null,support:[passage.id]};
  return Response.json({choices:[{message:{content:JSON.stringify({options:[option,{...option,name:'Invented Hydration Library'}],comparison:'Two purported options',limitations:['Current service unverified']})}}]});
 });
 const result=await new GroqResourceDiscovery(client).discover(brief,new ProviderOperation(signal()));
 expect(result.status).toBe('partial_sourced');expect(result.execution.extractionStatus).toBe('unavailable');expect(result.comparison.options.map(o=>o.name)).toEqual(['Civic Center']);expect(result.comparison.options[0]?.sourceURLs).toEqual(['https://example.gov/center']);expect(JSON.stringify(result.comparison)).not.toContain('Invented');expect(calls).toBe(3);
});
it('retains research at extraction timeout with original retrieval time, but never after consent cancellation',async()=>{
 const retrieved='2026-10-20T04:00:00.000Z';let now=new Date(retrieved);
 const transport:typeof fetch=async()=>{now=new Date('2026-10-20T04:00:30.000Z');throw new ProviderFailure('timeout','groq');};
 const client=new GroqClient('synthetic',undefined,transport),found=parseGroqResearch(fixture.response);
 const result=await new GroqResourceDiscovery(client,()=>now).formatEvidence(found,brief,new ProviderOperation(signal()),{retrievedAt:retrieved,expiresAt:'2026-10-20T05:00:00.000Z',cached:false});
 expect(result.status).toBe('partial_sourced');expect(result.retrievedAt).toBe(retrieved);expect(result.formattedAt).toBe('2026-10-20T04:00:30.000Z');expect(result.expiresAt).toBe('2026-10-20T05:00:00.000Z');expect(result.attribution.evidence.length).toBeGreaterThan(0);
 const revoked=new AbortController();revoked.abort();
 await expect(new GroqResourceDiscovery(client,()=>now).formatEvidence(found,brief,new ProviderOperation(revoked.signal))).rejects.toThrow();
});
it('rejects fabricated support with one repair and never switches on refusal, access denial or revoked consent',async()=>{
 let count=0;const client=new GroqClient('synthetic',undefined,async()=>{count++;return count===1?Response.json(fixture.response):Response.json({choices:[{message:{content:'{}'}}]});});
 const result=await new GroqResourceDiscovery(client).discover(brief,new ProviderOperation(signal()));expect(count).toBe(3);expect(result.status).toBe('partial_sourced');
 for(const reason of ['provider_access_denied','provider_request_rejected','policy_refusal']){
  let fallback=0;const discovery=new ResourceDiscovery({async turn(){throw new Error(reason);}},12,()=>new Date(),{async discover(){fallback++;throw new Error('unexpected');}});
  await expect(discovery.discover(brief)).rejects.toThrow(reason);expect(fallback).toBe(0);
 }
});
it('paces extraction from actual returned token reset metadata without inventing account quotas',async()=>{
 let count=0;const start=Date.now();const client=new GroqClient('synthetic',undefined,async()=>{
  count++;return Response.json({choices:[{message:{content:'{}'}}]},{headers:count===1?{'x-ratelimit-remaining-tokens':'0','x-ratelimit-reset-tokens':'25ms'}:{}});
 });
 const operation=new ProviderOperation(signal());await client.request([],operation);await client.request([],operation);expect(count).toBe(2);expect(Date.now()-start).toBeGreaterThanOrEqual(25);expect(operation.calls).toBe(2);
});

it('replays historical partial extraction without promoting obsolete passage bindings after segmentation changes',async()=>{
 const captured=JSON.parse(await readFile('../../fixtures/ai/groq-partial-extraction-live.json','utf8'));
 let calls=0;const now=()=>new Date(captured.sourceRetrievedAt);
 const client=new GroqClient('synthetic','openai/gpt-oss-20b',async()=>{
  const raw=captured.responses[calls++];
  return raw.error?Response.json({error:raw.error},{status:raw.error.status,headers:{'retry-after':'756'}}):Response.json(raw);
 });
 const result=await new GroqResourceDiscovery(client,now).formatEvidence(captured.found,captured.brief,new ProviderOperation(signal()),{retrievedAt:captured.sourceRetrievedAt,expiresAt:captured.sourceExpiresAt});
 expect(calls).toBe(2);expect(result.status).toBe('partial_sourced');
 // Historical receipt remains unchanged; current passage IDs/scopes no longer
 // bind that captured response. Never silently reinterpret old IDs as new evidence.
 expect(captured.expectedOptions[0]?.name).toBe('Daytime Cooling Centers');
 expect(result.comparison.options).toEqual([]);
 expect(result.execution.extractionErrors.join(',')).toContain('unsupported_research_identity_service_binding');
 expect(result.execution.extractionFailure).toMatchObject({kind:'quota_exhausted',status:429});
 expect(result.retrievedAt).toBe(captured.sourceRetrievedAt);expect(result.expiresAt).toBe(captured.sourceExpiresAt);
 expect(result.provider.extractorModel).toBe('openai/gpt-oss-20b');
});

it('supports documented browser_results without search_results and keeps search snippets distinct from inspection',()=>{
 const raw={choices:[{message:{content:'Attributed answer',executed_tools:[{type:'browser_search',browser_results:[{title:'Public service',url:'https://example.gov/services',content:'Documented program; confirm activation.'}]},{name:'browser.open',browser_results:[{title:'Public service page',url:'https://example.gov/services',content:'Documented program; confirm activation and access before travel.'}]}]}}]};
 const result=parseGroqResearch(raw);expect(result.searchSteps).toBe(1);expect(result.inspectionSteps).toBe(1);
 expect(result.sources).toEqual([{id:'source-1',title:'Public service page',url:'https://example.gov/services',content:'Documented program; confirm activation and access before travel.',inspection:'opened'}]);
});
it('preserves an optional-metadata-free attributed browser answer unresolved without promoting assistant URL blocks',async()=>{
 const answer='URL: https://example.gov/water\nPublic water service 【1†L2-L4】';
 let calls=0;const client=new GroqClient('synthetic',undefined,async()=>{calls++;return Response.json({choices:[{message:{content:answer}}]});});
 const result=await new GroqResourceDiscovery(client).discover(brief,new ProviderOperation(signal()));
 expect(calls).toBe(1);expect(result.status).toBe('unresolved_evidence');expect(result.attribution.answer).toBe(answer);
 expect(result.attribution.evidence).toEqual([]);expect(result.comparison.options).toEqual([]);
 expect(result.execution.retrievalEvidence).toBe('unresolved_optional_metadata');expect(result.execution.internalSearchCount).toBe('unreported');
});

it('replays actual rural Marfa browser execution under injected429 without treating its answer as verified facility or access facts',async()=>{
 const captured=JSON.parse(await readFile('../../fixtures/ai/groq-marfa-browser-live.json','utf8'));
 const result=parseGroqResearch(captured.response);
 expect(result.searchSteps).toBe(8);expect(result.inspectionSteps).toBe(5);
 expect(result.sources.some(s=>s.url==='https://www.cityofmarfa.com/administration/page/city-utilities')).toBe(true);
 expect(result.answer).toBe(captured.response.choices[0].message.content);
 expect(JSON.stringify(captured.response)).not.toContain('reasoning_content');
 let calls=0;const client=new GroqClient('synthetic',undefined,async()=>{calls++;return calls===1?Response.json(captured.response):Response.json({error:{code:'rate_limit_exceeded',type:'tokens',message:'Daily token quota exhausted'}},{status:429,headers:{'retry-after':'1179'}});});
 const discovery=new ResourceDiscovery({async turn(){throw new Error('provider_rate_limited');}},12,()=>new Date(captured.recordedAt),new GroqResourceDiscovery(client,()=>new Date(captured.recordedAt)));
 const replay=await discovery.discover(captured.brief);
 expect(replay.status).toBe('partial_sourced');expect(replay.provider).toMatchObject({name:'groq',fallback:true,primaryFailure:'provider_rate_limited',generation:1});
 expect(replay.comparison.options).toEqual([]);expect(replay.attribution.answer).toBe(result.answer);
 expect(replay.execution).toMatchObject({searchSteps:8,urlInspectionSteps:5});expect(calls).toBe(2);
});

it('revalidates actual Albuquerque120B extraction into three separately sourced named records without another search',async()=>{
 const captured=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-extraction-live.json','utf8'));
 let calls=0;
 const client=new GroqClient('synthetic','openai/gpt-oss-120b',async()=>{calls++;return Response.json(captured.response);});
 const result=await new GroqResourceDiscovery(client,()=>new Date(captured.extractionRecordedAt)).formatEvidence(captured.found,captured.brief,new ProviderOperation(signal()),{retrievedAt:captured.sourceRetrievedAt,expiresAt:captured.sourceExpiresAt});
 expect(calls).toBe(1);expect(result.status).toBe('cached_sourced');
 expect(result.comparison.options.map(o=>o.name)).toEqual(['Albuquerque City Drug','Highland Pharmacy','University Hospital Outpatient Pharmacy']);
 expect(result.comparison.comparison).toContain('Medicaid');
 expect(result.comparison.comparison).toContain('Drive');
 expect(result.comparison.options.every(o=>o.unknowns.length>0&&o.sourceURLs[0]?.includes('healthgrades.com'))).toBe(true);
 expect(result.retrievedAt).toBe(captured.sourceRetrievedAt);expect(result.expiresAt).toBe(captured.sourceExpiresAt);
 expect(result.execution.extractionErrors).toEqual([]);
});

it('shares a configured model quota across actual search, extraction and a later private operation',async()=>{
 const {configuredGroqClients}=await import('../src/groq.js');
 let dispatched=0;const observed:string[]=[];
 const clients=configuredGroqClients('synthetic',{model:'openai/gpt-oss-120b',observeResponse:(_raw,kind)=>observed.push(kind),transport:async(_url,request)=>{
  const body=JSON.parse(String(request?.body));if(body.tools?.some((t:any)=>t.type==='browser_search'))expect(body.reasoning_effort).toBe('medium');if(body.response_format){expect(body.max_completion_tokens).toBe(6000);expect(body.reasoning_effort).toBe('medium');}
  dispatched++;
  return dispatched===1?Response.json(fixture.response):Response.json({error:{code:'rate_limit_exceeded',message:'Daily token quota exhausted'}},{status:429,headers:{'retry-after':'1800'}});
 }});
 expect(clients.extractor).toBe(clients.client);
 const operation=new ProviderOperation(signal(),4);
 const result=await new GroqResourceDiscovery(clients.client,()=>new Date(),clients.extractor).discover(brief,operation);
 expect(result.status).toBe('partial_sourced');expect(result.attribution.evidence.length).toBeGreaterThan(0);
 expect(result.execution.extractionFailure).toMatchObject({kind:'quota_exhausted',retryAfterMs:1800000});
 const privateOperation=new ProviderOperation(signal());
 await expect(clients.client.request([{role:'user',content:'Synthetic private continuation'}],privateOperation)).rejects.toMatchObject({kind:'rate_limit'});
 const blocked=await clients.extractor.request([{role:'user',content:'Another role, same quota'}],new ProviderOperation(signal())).catch(e=>e);
 expect(blocked).toMatchObject({kind:'rate_limit',diagnostic:'model_cooldown'});if(!(blocked instanceof ProviderFailure))throw new Error('expected_provider_failure');expect(blocked.retryAfterMs).toBeGreaterThan(1790000);expect(blocked.retryAfterMs).toBeLessThanOrEqual(1801000);
 expect(dispatched).toBe(2);expect(operation.calls).toBe(2);expect(privateOperation.calls).toBe(0);
 expect(observed).toEqual(['search','structured']);
});

it('keeps different configured model pools independent without losing per-request response attribution',async()=>{
 const {configuredGroqClients}=await import('../src/groq.js');
 const dispatched:string[]=[],observed:string[]=[];
 const clients=configuredGroqClients('synthetic',{model:'openai/gpt-oss-20b',extractorModel:'openai/gpt-oss-120b',observeResponse:(_raw,kind)=>observed.push(kind),transport:async(_url,request)=>{
  const body=JSON.parse(String(request?.body));dispatched.push(body.model);
  return body.model==='openai/gpt-oss-20b'?Response.json({error:{message:'Daily token quota exhausted'}},{status:429,headers:{'retry-after':'1800'}}):Response.json({choices:[{message:{content:'{"value":"supported"}'}}]});
 }});
 expect(clients.extractor).not.toBe(clients.client);
 await expect(clients.client.request([{role:'user',content:'Public research'}],new ProviderOperation(signal()),{search:true})).rejects.toMatchObject({kind:'quota_exhausted'});
 await expect(clients.extractor.request([{role:'user',content:'Fresh public source evidence'}],new ProviderOperation(signal()),{schema:{type:'object',properties:{value:{type:'string'}},required:['value']}})).resolves.toBeDefined();
 expect(dispatched).toEqual(['openai/gpt-oss-20b','openai/gpt-oss-120b']);expect(observed).toEqual(['search','structured']);
});

it('does not let an older successful response erase a newer model quota cooldown',async()=>{
 const releases:((response:Response)=>void)[]=[];let dispatched=0;
 const client=new GroqClient('synthetic',undefined,async()=>{dispatched++;if(dispatched>2)throw new Error('unexpected_upstream_dispatch');return new Promise<Response>(resolve=>releases.push(resolve));});
 const messages=[{role:'user' as const,content:'Synthetic independent operation'}];
 const first=client.request(messages,new ProviderOperation(signal()));
 const second=client.request(messages,new ProviderOperation(signal()));
 expect(releases).toHaveLength(2);
 releases[0]!(Response.json({error:{message:'Daily token quota exhausted'}},{status:429,headers:{'retry-after':'1800'}}));
 await expect(first).rejects.toMatchObject({kind:'quota_exhausted'});
 releases[1]!(Response.json({choices:[{message:{content:'An earlier in-flight response'}}]}));
 await expect(second).resolves.toBeDefined();
 await expect(client.request(messages,new ProviderOperation(signal()))).rejects.toMatchObject({kind:'rate_limit',diagnostic:'model_cooldown'});
 expect(dispatched).toBe(2);
});

it('retains the longer of overlapping quota windows rather than the last response delay',()=>{
 let now=0;const circuit=new QuotaCircuit(()=>now,()=>0);
 circuit.failure(1800000);now=10;circuit.failure(1000);now=2000;
 expect(circuit.enter()).toBe(false);expect(circuit.retryAfterMs()).toBe(1798000);
});

it('does not release a current half-open probe when an older operation completes or aborts',()=>{
 let now=0;const circuit=new QuotaCircuit(()=>now,()=>0);
 expect(circuit.enter()).toBe(true);const old=circuit.generation;
 circuit.failure(1000);now=1001;
 expect(circuit.enter()).toBe(true);const probe=circuit.generation;
 circuit.release(old);circuit.success(old);expect(circuit.enter()).toBe(false);
 circuit.success(probe);expect(circuit.enter()).toBe(true);
});

it('repairs the actual search parse failure once and keeps extraction inside the same logical allowance',async()=>{
 const captured=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-search-parse-failed-live.json','utf8'));
 const error=captured.searchResponses[0].error;
 const bodies:any[]=[];
 const client=new GroqClient('synthetic',undefined,async(_url,request)=>{
  bodies.push(JSON.parse(String(request?.body)));
  if(bodies.length===1)return Response.json({error},{status:error.status});
  if(bodies.length===2)return Response.json(fixture.response);
  return Response.json({choices:[{message:{content:JSON.stringify({options:[],comparison:'The returned sources require checking; no specific facility is established by this synthetic extraction.',limitations:['No facility suitability has been established.']})}}]});
 });
 const operation=new ProviderOperation(signal(),4,0.15);
 operation.reserve(0.012); // Already-failed Gemini attempt is still part of this operation.
 const result=await new GroqResourceDiscovery(client).discover(brief,operation);
 expect(bodies).toHaveLength(3);expect(operation.calls).toBe(4);expect(operation.outputRepairs).toBe(1);
 expect(bodies.slice(0,2).every(body=>body.tools[0].type==='browser_search')).toBe(true);
 expect(bodies[1].messages.at(-1).content).toContain('search repair/1');
 expect(JSON.stringify(bodies)).not.toContain('private-id');expect(bodies[2].tools).toBeUndefined();
 expect(result.execution).toMatchObject({searchOperationCalls:2,searchGenerationErrors:['output_parse_failed'],outputRepairs:1,extractionStatus:'completed'});
 expect(result.attribution.evidence.length).toBeGreaterThan(0);expect(result.execution.searchSteps).toBe(2);
 expect(result.status).toBe('no_matches'); // Recovery is not proof of useful named options.
});

it('cannot multiply search and extraction repairs and retains browser evidence when extraction remains invalid',async()=>{
 let dispatched=0;
 const client=new GroqClient('synthetic',undefined,async()=>{
  dispatched++;
  if(dispatched===1)return Response.json({error:{code:'output_parse_failed'}},{status:400});
  if(dispatched===2)return Response.json(fixture.response);
  return Response.json({choices:[{message:{content:'malformed generated JSON'}}]});
 });
 const operation=new ProviderOperation(signal(),6);
 const result=await new GroqResourceDiscovery(client).discover(brief,operation);
 expect(dispatched).toBe(3);expect(operation.outputRepairs).toBe(1);
 expect(result.status).toBe('partial_sourced');expect(result.attribution.evidence.length).toBeGreaterThan(0);
 expect(result.execution.extractionStatus).toBe('invalid_output');expect(result.comparison.options).toEqual([]);
});

it.each([
 {status:400,code:'output_parse_failed',message:'Invalid generated output',kind:'invalid_output',expected:2},
 {status:400,code:'unsupported_tool',message:'Unsupported capability',kind:'unsupported',expected:1},
 {status:401,code:'invalid_api_key',message:'Invalid credentials',kind:'configuration',expected:1},
 {status:429,code:'rate_limit_exceeded',message:'Daily token quota exhausted',kind:'quota_exhausted',expected:1},
])('bounds search recovery for $kind without treating a repair as retrieval',async row=>{
 let dispatched=0;const client=new GroqClient('synthetic',undefined,async()=>{dispatched++;return Response.json({error:{code:row.code,message:row.message}},{status:row.status,headers:{'retry-after':'1800'}});});
 const operation=new ProviderOperation(signal(),6);
 await expect(new GroqResourceDiscovery(client).discover(brief,operation)).rejects.toMatchObject({kind:row.kind});
 expect(dispatched).toBe(row.expected);expect(operation.calls).toBe(row.expected);expect(operation.outputRepairs).toBe(row.expected-1);
});

it('does not dispatch a search repair after cancellation or an exhausted shared operation allowance',async()=>{
 for(const cancelled of [true,false]){
  let dispatched=0;const controller=new AbortController();
  const client=new GroqClient('synthetic',undefined,async()=>{dispatched++;return Response.json({error:{code:'output_parse_failed'}},{status:400});},()=>{if(cancelled)controller.abort();});
  const operation=new ProviderOperation(controller.signal,1);
  await expect(new GroqResourceDiscovery(client).discover(brief,operation)).rejects.toBeDefined();
  expect(dispatched).toBe(1);expect(operation.calls).toBe(1);expect(operation.outputRepairs).toBe(0);
 }
});

it('does not publish invented transit and general-pharmacy claims from retained Albuquerque20B extraction',async()=>{
 const source=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-search-v5-live.json','utf8'));
 const captured=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-extraction-v5-live.json','utf8'));
 let calls=0;
 const client=new GroqClient('synthetic','openai/gpt-oss-20b',async()=>Response.json(captured.responses[Math.min(calls++,captured.responses.length-1)]));
 const result=await new GroqResourceDiscovery(client,()=>new Date(captured.sourceRetrievedAt)).formatEvidence(
  parseGroqResearch(source.searchResponses[0]),captured.result.brief,new ProviderOperation(signal()),
  {retrievedAt:source.result.retrievedAt,expiresAt:source.result.expiresAt});
 expect(calls).toBeLessThanOrEqual(2);
 expect(result.status).toBe('partial_sourced');expect(result.comparison.options).toEqual([]);
 expect(result.attribution.evidence.length).toBeGreaterThan(0);expect(result.execution.extractionStatus).toBe('invalid_output');
 // The retained source identifies a testing/vaccine clinic; neither its general prescription
 // service nor a usable transit approach follows from its name, address or opening hours.
 expect(JSON.stringify(result.comparison)).not.toMatch(/general pharmacy services|accessible by public transit|convenient pharmacy experience/iu);
});

it('can repair retained clinical category guessing into grounded program and contact-only leads without narrowing reasoning to a task catalog',async()=>{
 const source=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-search-v5-live.json','utf8'));
 const captured=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-extraction-v5-live.json','utf8'));
 // This correction is authored synthetic development evidence, not a successful live-model repair.
 const corrected=JSON.parse(await readFile('../../fixtures/ai/research-service-identity-repair.json','utf8')).syntheticRepair;
 let calls=0;
 const client=new GroqClient('synthetic','openai/gpt-oss-20b',async(_url,request)=>{
  const messages=JSON.parse(String(request?.body)).messages;
  const payload=JSON.parse(messages[1].content);
  if(calls===0)expect(payload.repair).toBeUndefined();
  else {
   expect(payload.repair.previousCandidate.options[0].documentedService).toBe('Pharmacy');
   expect(payload.repair.validationErrors.join(',')).toContain('unsupported_research_service_description');
   expect(payload.repair.validationErrors.join(',')).toContain('Public Health Pharmacy Clinic');
   expect(JSON.stringify(payload)).not.toContain('reasoning_content');
   expect(payload.brief).not.toHaveProperty('taskID');
  }
  return Response.json(calls++===0?captured.responses[0]:{choices:[{message:{content:JSON.stringify(corrected)}}]});
 });
 const operation=new ProviderOperation(signal());
 const result=await new GroqResourceDiscovery(client,()=>new Date(captured.sourceRetrievedAt)).formatEvidence(
  parseGroqResearch(source.searchResponses[0]),captured.result.brief,operation,{retrievedAt:source.result.retrievedAt,expiresAt:source.result.expiresAt});
 expect(calls).toBe(2);expect(operation.outputRepairs).toBe(1);expect(result.status).toBe('cached_sourced');
 expect(result.comparison.options).toHaveLength(2);
 expect(result.comparison.options[0]?.whyUseful).toContain('budget constraint');
 expect(result.comparison.options[0]?.sourceURLs).toEqual(['https://www.abqhch.org/services/pharmacy/']);
 expect(result.comparison.options[1]?.whyUseful).toContain('contact-only');
 expect(result.comparison.options[1]?.sourceURLs).toEqual(['https://www.phpcabq.net/']);
 expect(result.retrievedAt).toBe(source.result.retrievedAt);expect(result.expiresAt).toBe(source.result.expiresAt);
 expect(JSON.stringify(result.comparison)).not.toContain('ABQ RIDE Route 8');
});
