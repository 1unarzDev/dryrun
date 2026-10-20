import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {Host} from './host.js';
import {Gateway} from '../src/gateway.js';
import {executeDirectorTool} from './director-tools.js';
import {hazardExperience,minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
const host=new Host();let providerCalls=0;
const commit=(s:any,id:string,commands:any[],actor='user')=>host.request({op:'commit',session:s.session,commit:{id,actor,baseRevision:s.receipt.revision,commands}});
try {
 const common=JSON.parse(await readFile('../../fixtures/ai/six-hazard-mechanics.json','utf8'));
 const original=await host.request({op:'initialize',scenarioID:'home-fire'});
 const input={...original.session.initial,household:structuredClone(common.household),home:structuredClone(common.home)};
 const person=input.household.people.find((p:any)=>p.ageBand==='child'),helperID=person?.helperPersonID;
 assert(person&&helperID);
 // Explicit synthetic functional-need mutation, never inferred from an age or diagnosis.
 if(!person.needs.includes('needsHelperToEvacuate'))person.needs.push('needsHelperToEvacuate');
 const initialized=await host.request({op:'initialize',input});
 const active=await commit(initialized,'fire-bed2',[{kind:'startIncident',target:'evt.home-fire.alarm',hazard:'homeFire',value:'sp-bed2',minute:0},{kind:'advance',minute:0}],'director');
 const experience=hazardExperience.parse(active.receipt.experience);
 assert.equal(experience.mechanicsVersion,'dryrun.hazard-mechanics/5');
 const options=experience.feasibleCommands!.filter(c=>c.kind==='accompanyEscape'&&'target'in c&&c.target===person.id).slice(0,2);
 assert.equal(options.length,2,'two computed exits must survive this bedroom ignition variant');
 const binding={sessionID:active.receipt.sessionID,revision:active.receipt.revision,eventSequence:active.receipt.eventSequence,contextDigest:active.receipt.contextDigest,householdRevision:input.household.revision,homeRevision:input.home.revision};
 const gateway=new Gateway({async turn(){
  providerCalls++;
  if(providerCalls===1){const call={type:'function_call' as const,id:'preview-paired-exits',name:'evaluateCandidateAction',arguments:{command:{kind:'requestDecision'}}};return {text:'',steps:[call],calls:[call],usage:{}};}
  return {steps:[],calls:[],usage:{},text:JSON.stringify({commands:[{kind:'requestDecision'}],purpose:'The bedroom incident is active. The recorded helper has a computed approach to this member, and both can traverse either selected exit. Choose their supported path; outside accounting remains a separate household action.',evidenceIDs:[person.id,helperID,'sp-bed2'],suggestedActions:options.map((command,index)=>({id:'paired-exit-'+index,label:'Accompany the member through '+('value'in command?command.value:''),fact:'This member explicitly has needsHelperToEvacuate and a recorded helper.',implication:'The host computes the helper approach and both exits; selecting this moves both people outside without accounting for them.',commands:[command]}))})};
 }});
 const context={binding,snapshot:minimizedSnapshot(active.receipt),assistance:minimizedAssistance(active.receipt),experience,household:active.householdContext,homeScene:active.homeScene,profiles:active.directorProfiles,directorPolicy:active.session.directorPolicy,directorState:active.receipt.directorState,pending:active.receipt.pending};
 let result:any=await gateway.start('synthetic',{contractVersion:'dryrun.ai/1',requestID:'paired-fire',role:'director',synthetic:true,context});
 while(result.status==='needs_client_tools'){
  const call=result.calls[0],tool=await executeDirectorTool(host,active,binding,call);
  result=await gateway.resume('synthetic',{token:result.token,binding,callID:call.id,result:tool.result});
 }
 assert.equal(result.status,'completed');
 const directed=await host.request({op:'directorCommit',session:active.session,proposal:result.proposal,binding});
 const branches=[];
 for(const action of result.proposal.suggestedActions){
  const state=await commit(directed,action.id,action.commands);
  assert.deepEqual(state.receipt.experience.outsidePersonIDs,[person.id,helperID].sort());
  assert.deepEqual(state.receipt.experience.accountedPersonIDs,[]);
  assert.equal(state.receipt.experience.escapeHelperByPersonID[person.id],helperID);
  const replay=await host.request({op:'query',session:JSON.parse(JSON.stringify(state.session))});assert.deepEqual(replay.receipt,state.receipt);
  branches.push({action,result:state});
 }
 assert.notDeepEqual(branches[0]!.result.receipt.routes,branches[1]!.result.receipt.routes);
 const helperAlone=active.receipt.experience.feasibleCommands.find((c:any)=>c.kind==='escape'&&c.target===helperID);assert(helperAlone);
 const left=await commit(directed,'helper-left-alone',[helperAlone]);
 assert(left.receipt.experience.openGapIDs.includes('escapeAssistance.'+person.id));
 assert(!left.receipt.experience.feasibleCommands.some((c:any)=>c.kind==='accompanyEscape'&&c.target===person.id));
 assert.equal(left.receipt.assistance.find((a:any)=>a.personID===person.id).reachStatus,'unreachable');
 await assert.rejects(commit(left,'no-reentry',options.slice(0,1)),/invalidCommand/);
 const accounted=[];
 for(const target of [person.id,helperID])accounted.push(await commit(branches[0]!.result,'roster-'+target,[{kind:'accountOutside',target}]));
 assert.notDeepEqual(accounted[0].receipt.experience.accountedPersonIDs,accounted[1].receipt.experience.accountedPersonIDs);
 const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
 const begun=await host.request({op:'practiceHazardBegin',session:directed.session,attemptID:'paired-initial-response',checkID:'fire.escape/1'});
 const answer={id:'paired-practice',actor:'user',baseRevision:directed.receipt.revision,commands:[options[0]]};
 const scored=await host.request({op:'practiceHazardSubmit',session:begun.session,aiState:begun.aiState,attemptID:'paired-initial-response',commit:answer,rubric,assessments:[]});
 assert.equal(scored.scorecard.practice,25/3);assert(!scored.pendingHazardChecks.some((c:any)=>c.id==='fire.escape/1'));
 const restored=await host.request({op:'assess',session:scored.session,aiState:JSON.parse(JSON.stringify(scored.aiState)),rubric,assessments:[]});assert.equal(restored.scorecard.practice,scored.scorecard.practice);
 await assert.rejects(host.request({op:'practiceHazardSubmit',session:scored.session,aiState:scored.aiState,attemptID:'paired-initial-response',commit:answer,rubric,assessments:[]}),/invalidCommand/);
 const report={synthetic:true,liveModelCalls:0,syntheticProviderCalls:providerCalls,passed:true,mechanicsVersion:experience.mechanicsVersion,mode:'actual Core host, gateway/tool/proposal and score operations',initial:active,proposal:result.proposal,branches,helperLeftAlone:left,accountingBranches:accounted,practice:{scored,restored},native:'pending',humanReview:'pending',limits:'Recorded exercise accompaniment, not a lift/carry technique, rescue, certification or native verification.'};
 await mkdir('../../artifacts/ai/fire-accompaniment',{recursive:true});await writeFile('../../artifacts/ai/fire-accompaniment/result.json',JSON.stringify(report,null,2)+'\n');
 await writeFile('../../fixtures/ai/fire-accompaniment-trace.json',JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({passed:true,liveModelCalls:0,syntheticProviderCalls:providerCalls,twoComputedExits:true,separateRosterChoices:true,noReentry:true,replay:'exact',practiceCredit:'existing anchor once',relaunch:'passed',native:'pending'}));
} finally {host.close();}
