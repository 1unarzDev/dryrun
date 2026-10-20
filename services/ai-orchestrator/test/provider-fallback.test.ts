import {it,expect} from 'vitest';
import {GeminiPrimaryFallback,privateMessages} from '../src/provider-fallback.js';
import {GroqClient,strictGroqSchema,hostStructuredValue} from '../src/groq.js';
import {Gateway} from '../src/gateway.js';
import type {AgentProvider} from '../src/provider.js';
const input={history:[{type:'user_input' as const,content:[{type:'text' as const,text:JSON.stringify({people:[{id:'member',disability:'Synthetic ADHD',assistance:'written two-step list',medication:'Synthetic medicine',storage:'pharmacist sheet and carrier'}],equipment:[{id:'cold',requiresColdStorage:true,requiresPower:false}],housing:{type:'apartment'},inventory:[{id:'water',liters:2}]})}]}],instruction:'Grounded private reasoning',tools:[],outputSchema:{type:'object',properties:{action:{type:'string'}},required:['action'],additionalProperties:false},signal:AbortSignal.timeout(10000)};
it('defaults to Gemini-only consent and never sends an image to a text-only fallback',async()=>{
 let calls=0;const router=new GeminiPrimaryFallback({async turn(){throw new Error('provider_rate_limited');}},new GroqClient('synthetic',undefined,async()=>{calls++;return Response.json({});}));
 for(const options of [{providers:['gemini'],capability:'privateText' as const},{providers:['gemini','groq'],capability:'image' as const}])await expect(router.scope({...options,signal:input.signal}).turn(input)).rejects.toThrow('provider_rate_limited');expect(calls).toBe(0);
});
it('preserves linked private facts and disables all public tools on actual fallback request',async()=>{
 let body:any,primary=0;
 const router=new GeminiPrimaryFallback({async turn(i){primary++;expect(i.history).toEqual(input.history);throw new Error('provider_rate_limited');}},new GroqClient('synthetic',undefined,async(_url,r)=>{body=JSON.parse(String(r?.body));return Response.json({choices:[{message:{content:'{"action":"Review the recorded pharmacist sheet with the named carrier"}'}}]});}));
 const scoped=router.scope({signal:input.signal,providers:['gemini','groq'],capability:'privateText'});const reply=await scoped.turn(input);expect(reply.text).toContain('pharmacist');expect(scoped.attemptGeneration).toBe(1);expect(body.tools).toBeUndefined();expect(body.tool_choice).toBe('none');
 for(const fact of ['Synthetic ADHD','written two-step list','Synthetic medicine','pharmacist sheet and carrier','requiresColdStorage','requiresPower','apartment','liters'])expect(JSON.stringify(body)).toContain(fact);
 expect(body.reasoning_effort).toBe('medium');expect(body.include_reasoning).toBe(false);
 await scoped.turn(input);expect(primary).toBe(1);
});
it('does not transfer Gemini thought signatures or raw continuation objects',()=>{
 const projected=privateMessages([...input.history,{type:'thought',signature:'secret-signature'},{type:'function_call',id:'read-1',name:'evaluateResources',arguments:{}},{type:'function_result',call_id:'read-1',name:'evaluateResources',result:[{type:'text',text:'Authoritative read-only receipt'}]}]);
 expect(JSON.stringify(projected)).not.toContain('secret-signature');expect(projected[1]?.tool_calls?.[0]?.function.name).toBe('evaluateResources');expect(projected[2]?.role).toBe('tool');
});
it('strict transport makes optional fields nullable, then removes only optional transport nulls',()=>{
 const schema={type:'object',properties:{optional:{type:'string'},requiredNullable:{anyOf:[{type:'string'},{type:'null'}]}},required:['requiredNullable'],additionalProperties:false};
 expect(strictGroqSchema(schema).required).toEqual(['optional','requiredNullable']);expect(hostStructuredValue({optional:null,requiredNullable:null},schema)).toEqual({requiredNullable:null});
});
it('fences a late native callback even when the host revision is unchanged',async()=>{
 let generation=0;
 const call={type:'function_call' as const,id:'preview',name:'evaluateCandidateAction',arguments:{command:{kind:'requestDecision'}}};
 const provider:AgentProvider={get attemptGeneration(){return generation;},async turn(){return {steps:[call],text:'',calls:[call],usage:{}};}};
 const gateway=new Gateway(provider),binding={sessionID:'s',revision:1,eventSequence:1,contextDigest:'abc',householdRevision:1,homeRevision:1},snapshot={simMinute:0,resources:{},services:{},unmetRequirements:[],unknowns:[]};
 const started:any=await gateway.start('owner',{contractVersion:'dryrun.ai/1',requestID:'late-tool',role:'director',synthetic:true,context:{binding,snapshot,profiles:[]}});
 generation=1;await expect(gateway.resume('owner',{token:started.token,binding,callID:'preview',result:{binding,snapshot,contextDigest:'preview'}})).rejects.toThrow('stale_provider_attempt');gateway.cancel('owner',started.token);
});
it('does not ping-pong or reset shared budget when both providers are rate limited',async()=>{
 let primary=0,secondary=0;const router=new GeminiPrimaryFallback({async turn(){primary++;throw new Error('provider_rate_limited');}},new GroqClient('synthetic',undefined,async()=>{secondary++;return new Response('{}',{status:429});}));
 const scoped=router.scope({signal:input.signal,providers:['gemini','groq'],capability:'privateText',maximumCalls:3});await expect(scoped.turn(input)).rejects.toMatchObject({kind:'rate_limit'});await expect(scoped.turn(input)).rejects.toMatchObject({kind:'rate_limit'});await expect(scoped.turn(input)).rejects.toMatchObject({kind:'rate_limit'});expect(primary).toBe(1);expect(secondary).toBe(1);
});
it('propagates connection cancellation to private Groq request and rejects a late proposal',async()=>{
 const controller=new AbortController();let sent!:()=>void;const ready=new Promise<void>(r=>sent=r);let release!:(r:Response)=>void;
 const router=new GeminiPrimaryFallback({async turn(){throw new Error('provider_rate_limited');}},new GroqClient('synthetic',undefined,async(_url,request)=>{expect(request?.signal).toBeDefined();sent();return new Promise<Response>(r=>release=r);}));
 const scoped=router.scope({signal:AbortSignal.timeout(10000),providers:['gemini','groq'],capability:'privateText'});
 const pending=scoped.turn({...input,signal:controller.signal});await ready;controller.abort();await expect(pending).rejects.toMatchObject({kind:'cancelled'});release(Response.json({choices:[{message:{content:'{"action":"late"}'}}]}));
});
it('compacts only geometry, keeping all recorded care fields and scene topology',async()=>{
 const {compactPrivateText}=await import('../src/provider-fallback.js');
 const data={household:{medication:{position:'Keep upright',normal:'Recorded regimen',storage:'Synthetic carrier'}},homeScene:{version:'dryrun.home-scene/2',rooms:[{id:'r',polygon:[{x:0,y:0}],use:'bedroom'}],portals:[{id:'p',fromRoomID:'r',toRoomID:'out',kind:'door',verified:true}],walls:[{polygon:[{x:0,y:0}]}],planningRoutes:[{personID:'member',primaryPortalIDs:['p'],sharedChokepointIDs:['r']}]}};
 const parsed=JSON.parse(compactPrivateText(JSON.stringify(data)));expect(parsed.household).toEqual(data.household);expect(parsed.homeScene.rooms[0]).toEqual({id:'r',use:'bedroom'});expect(parsed.homeScene.portals).toEqual(data.homeScene.portals);expect(parsed.homeScene.planningRoutes).toEqual(data.homeScene.planningRoutes);expect(parsed.homeScene.walls).toBeUndefined();
});
it('keeps director/user commands distinct and compacts only irrelevant suggestion variants',async()=>{
 const {groqDirectorInstruction,groqDirectorSchema}=await import('../src/groq-director.js');
 const instruction=groqDirectorInstruction('DryRun RehearsalDirector prompt/15. FINALIZATION: Keep exact commands. dryrun.output-style/1: details');
 expect(instruction).toContain('DIRECTOR commands only');expect(instruction).toContain('never user commands');expect(instruction).toContain('Keep exact commands');expect(instruction).toContain('cold storage alone');
 expect(instruction).toContain('accompanyEscape');expect(instruction).toContain('escapeHelperByPersonID');
 expect(instruction).toContain('relocated true');expect(instruction).toContain('preview finish only for the home boundary');
 expect(instruction).toContain('Electrical service is not clinical treatment');
 const schema={type:'object',properties:{suggestedActions:{type:'array',items:{type:'object',properties:{commands:{type:'array',items:{oneOf:[{type:'object',properties:{kind:{const:'useWater'}}},{type:'object',properties:{kind:{const:'escape'}}}]}}}}}}};
 const scoped=groqDirectorSchema(schema,[{type:'user_input',content:[{type:'text',text:JSON.stringify({experience:{feasibleCommands:[{kind:'useWater'}]}})}]}]);expect(JSON.stringify(scoped)).toContain('useWater');expect(JSON.stringify(scoped)).not.toContain('escape');expect(JSON.stringify(schema)).toContain('escape');
});
it('never sends private context to a provider excluded from operation consent',async()=>{
 let primary=0,secondary=0;const router=new GeminiPrimaryFallback({async turn(){primary++;throw new Error('unauthorized');}},new GroqClient('synthetic',undefined,async()=>{secondary++;return Response.json({choices:[{message:{content:'{"action":"Review the recorded sheet"}'}}]});}));
 await router.scope({signal:input.signal,providers:['groq'],capability:'privateText'}).turn(input);expect(primary).toBe(0);expect(secondary).toBe(1);
 expect(()=>router.scope({signal:input.signal,providers:[],capability:'privateText'})).toThrow('operation_unsupported');
 expect(()=>router.scope({signal:input.signal,providers:['groq'],capability:'image'})).toThrow('operation_unsupported');
});
it('groups identical baseline routes without losing person links or distinct accessibility constraints',async()=>{
 const {compactPrivateText}=await import('../src/provider-fallback.js');
 const common={primaryPortalIDs:['door','stair'],alternativeStatus:'sharesChokepoint',sharedChokepointIDs:['stair'],scope:'Baseline only, not incident clearance',exclusions:[{elementID:'window',reason:'upperFloor'}]};
 const data={homeScene:{planningRoutes:[{...common,personID:'a'},{...common,personID:'b'},{...common,personID:'c',stepFreeRequired:true}]}};
 const projected=JSON.parse(compactPrivateText(JSON.stringify(data))).homeScene.planningRoutes;
 expect(projected).toEqual([{...common,personIDs:['a','b']},{...common,stepFreeRequired:true,personID:'c'}]);
 expect(data.homeScene.planningRoutes[0]?.personID).toBe('a');
});
it('reserves time for fallback and fences an ignored-abort late primary at unchanged host revision',async()=>{
 let primarySignal:AbortSignal|undefined,release!:(reply:any)=>void,secondary=0;
 const primary:AgentProvider={async turn(i){primarySignal=i.signal;return new Promise(resolve=>release=resolve);}};
 const router=new GeminiPrimaryFallback(primary,new GroqClient('synthetic',undefined,async()=>{secondary++;return Response.json({choices:[{message:{content:'{"action":"Use current authoritative context"}'}}]});}),20);
 const scoped=router.scope({signal:input.signal,providers:['gemini','groq'],capability:'privateText'});
 const result=await scoped.turn(input);expect(result.text).toContain('authoritative');expect(primarySignal?.aborted).toBe(true);expect(scoped.attemptGeneration).toBe(1);expect(secondary).toBe(1);
 release({steps:[],calls:[],usage:{},text:'late primary output'});await Promise.resolve();await Promise.resolve();
 expect(result.text).not.toContain('late');expect(scoped.attemptGeneration).toBe(1);
});
