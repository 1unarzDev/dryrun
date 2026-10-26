import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {Host} from './host.js';
import {Gateway} from '../src/gateway.js';
import {directorContext,minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
import {GeminiPrimaryFallback} from '../src/provider-fallback.js';
import {GroqClient} from '../src/groq.js';
import {executeDirectorTool} from './director-tools.js';
import type {AgentProvider} from '../src/provider.js';

const host=new Host(),cases:any[]=[];
let primaryRequests=0,syntheticHTTP=0;
try {
 const fixture=JSON.parse(await readFile('../../fixtures/ai/helper-reassignment.json','utf8'));
 const inputs=fixture.receipts.map((row:any,index:number)=>({name:index?'approach-reachable-exit-still-blocked':'approach-blocked',session:{...fixture.session,commits:fixture.session.commits.slice(0,row.receipt.revision)}}));
 const initial=await host.request({op:'initialize',scenarioID:'home-fire'});
 for(const person of initial.session.initial.household.people)person.sleepingSpaceID='sp-bed1';
 const fresh=await host.request({op:'initialize',input:initial.session.initial});
 const personID='p-oak-3',newHelper='p-oak-2';
 const reassigned=await host.request({op:'commit',session:fresh.session,commit:{id:'current-helper',actor:'user',baseRevision:0,commands:[{kind:'assignHelper',target:personID,value:newHelper}]}});
 inputs.push({name:'reassigned-supported-escape',session:reassigned.session});
 for(const input of inputs){
  const state=await host.request({op:'query',session:input.session});
  const frozen=JSON.stringify(state.session),recorded=state.householdContext.people.find((p:any)=>p.id===personID)?.helperPersonID;
  const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home.revision};
  const context=directorContext.parse({binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),experience:state.receipt.experience,household:state.householdContext,homeScene:state.homeScene,profiles:state.directorProfiles,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending,lastAction:state.lastAction,recentActions:state.recentActions});
  const actual=context.assistance!.find(a=>a.personID===personID)!;assert(actual);
  assert(!JSON.stringify(context.assistance).includes('spaceSequence'));
  if(input.name!=='approach-blocked'){assert.equal(actual.helperID,newHelper);assert.equal(actual.reachStatus,'reachable');assert.notEqual(actual.helperID,recorded);}
  const escape=state.receipt.experience.feasibleCommands.find((c:any)=>c.kind==='accompanyEscape'&&c.target===personID);
  if(input.name==='approach-reachable-exit-still-blocked')assert(!escape,'an approach is not an exit');
  const action=escape??state.receipt.experience.feasibleCommands.find((c:any)=>c.kind==='identifyGap');assert(action);
  const output={commands:[{kind:'requestDecision'}],purpose:escape?'The current reassigned helper has a computed approach and both exit routes. Offer that actual accompaniment; outside accounting remains separate.':`The current helper approach is ${actual.reachStatus}. No paired exit is available; recognize the actual remaining planning gap without claiming arrival or a usable route.`,evidenceIDs:[personID,actual.helperID!],suggestedActions:[{id:'current-assistance-action',label:escape?'Use the currently assigned helper and computed exit':'Recognize the actual unresolved route gap',fact:`The current exercise helper is ${actual.helperID}, approach ${actual.reachStatus}; the frozen household assignment remains separate.`,implication:escape?'The selected command moves both actual people outside, without recording outside accounting.':'An approach status alone cannot establish a complete exit or physical assistance.',commands:[action]}]};
  for(const route of ['gemini','groq-fallback'] as const){
   let turns=0;const seen:any[]=[];
   const call={type:'function_call' as const,id:'preview-assistance',name:'evaluateCandidateAction',arguments:{command:{kind:'requestDecision'}}};
   const primary:AgentProvider={async turn(request){
    primaryRequests++;
    const sent=JSON.parse((request.history[0] as any).content[0].text);seen.push({provider:'gemini',assistance:sent.assistance});assert.deepEqual(sent.assistance,context.assistance);
    if(route==='groq-fallback')throw new Error('provider_rate_limited');
    return ++turns===1?{steps:[call],calls:[call],text:'',usage:{}}:{steps:[],calls:[],text:JSON.stringify(output),usage:{}};
   }};
   const router=new GeminiPrimaryFallback(primary,new GroqClient('synthetic',undefined,async(_url,request)=>{
    syntheticHTTP++;const body=JSON.parse(String(request?.body));assert(!body.tools?.some((t:any)=>t.type==='browser_search'));
    const sent=JSON.parse(body.messages.find((m:any)=>m.role==='user').content);assert.deepEqual(sent.assistance,context.assistance);seen.push({provider:'groq',assistance:sent.assistance});
    const message=++turns===1?{tool_calls:[{id:call.id,type:'function',function:{name:call.name,arguments:JSON.stringify(call.arguments)}}]}:{content:JSON.stringify(output)};
    return Response.json({choices:[{message}],usage:{prompt_tokens:1,completion_tokens:1}});
   }));
   const gateway=new Gateway(router);
   let result:any=await gateway.start('synthetic',{contractVersion:'dryrun.ai/1',requestID:input.name+'-'+route,role:'director',synthetic:true,providerConsent:['gemini','groq'],context});
   while(result.status==='needs_client_tools'){
    const tool=await executeDirectorTool(host,state,binding,result.calls[0]);
    if(result.calls[0].name==='evaluateCandidateAction')assert.deepEqual(tool.result.preview?.assistance,context.assistance);
    else {assert.equal(result.calls[0].name,'validateSuggestedActions');assert.equal(tool.result.contextDigest,binding.contextDigest);}
    result=await gateway.resume('synthetic',{token:result.token,binding,callID:result.calls[0].id,result:tool.result});
   }
   assert.equal(result.status,'completed');assert.equal(JSON.stringify(state.session),frozen);
   const directed=await host.request({op:'directorCommit',session:state.session,proposal:result.proposal,binding});
   const applied=await host.request({op:'commit',session:directed.session,commit:{id:'selected-current-action',actor:'user',baseRevision:directed.receipt.revision,commands:[action]}});
   if(escape){assert.equal(applied.receipt.experience.escapeHelperByPersonID[personID],newHelper);assert(applied.receipt.experience.outsidePersonIDs.includes(newHelper));}
   assert.deepEqual(applied.session.initial,state.session.initial);
   const replay=await host.request({op:'query',session:JSON.parse(JSON.stringify(applied.session))});assert.deepEqual(replay.receipt,applied.receipt);
   cases.push({name:input.name,providerRoute:route,session:state.session,receipt:state.receipt,context,recordedHelperID:recorded,currentHelper:actual,providerInputs:seen,proposal:result.proposal,appliedSession:applied.session,appliedReceipt:applied.receipt});
  }
 }
 const report={synthetic:true,liveModelCalls:0,primaryRequests,syntheticHTTP,passed:true,cases,native:'pending',humanReview:'pending',limits:'Actual Core state and gateway transport with synthetic provider responses; not live model quality or native verification.'};
 await mkdir('../../artifacts/ai/current-assistance',{recursive:true});await writeFile('../../artifacts/ai/current-assistance/result.json',JSON.stringify(report,null,2)+'\n');
 await writeFile('../../fixtures/ai/current-assistance-context.json',JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({passed:true,liveModelCalls:0,providerPaths:2,contextVariants:3,syntheticHTTP,recordedHouseholdPreserved:true,approachDoesNotImplyExit:true,currentHelperActuallyEscapes:true,replay:'exact',native:'pending'}));
} finally {host.close();}
