import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {Host} from './host.js';
import {Gateway} from '../src/gateway.js';
import {executeDirectorTool} from './director-tools.js';
import {hazardExperience,minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
import {directorProviderSchemas} from '../src/director-provider-schema.js';
const host=new Host(),ev=(value:unknown)=>({value,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]});
const traces:any[]=[];
const commit=(s:any,id:string,commands:any[],actor='user')=>host.request({op:'commit',session:s.session,commit:{id,actor,baseRevision:s.receipt.revision,commands}});
try{
 const original=await host.request({op:'initialize',scenarioID:'flash-flood'}),input=structuredClone(original.session.initial);
 input.home=JSON.parse(await readFile('../../fixtures/homes/home-sample-twostory.json','utf8'));
 for(const f of input.home.floors)f.exteriorGrade=f.level===0?'ground':'aboveGround';
 input.home.spaces.find((r:any)=>r.id==='sp-bed1').higherRefugeConfirmed=ev(true);
 // This is an explicit synthetic functional restriction, never inferred from limitedMobility alone.
 const stairRestricted=input.household.people.find((p:any)=>p.needs.includes('limitedMobility'));if(stairRestricted)stairRestricted.needs.push('cannotUseStairs');
 input.spatialOptions={floodIsHouseholdLeak:false,floodAffectedSpaceIDs:['sp-living'],refugeSpaceID:'sp-bed1',startingSpaceIDs:Object.fromEntries(input.household.people.map((p:any)=>[p.id,'sp-hall']))};
 const start=await host.request({op:'initialize',input});
 const stocked=await host.request({op:'confirmInventory',session:start.session,inventoryItems:[{id:'kit-water',physicalID:'synthetic-case',category:'water',quantity:ev(2),usableQuantity:ev(2),accessible:ev(true),unit:'liter',locationID:'sp-hall',subjectIDs:[],evidenceIDs:['typed-case']}]});
 const warned=await commit(stocked,'warning',[{kind:'schedule',target:'evt.flash-flood.warning',minute:0},{kind:'advance',minute:0}],'director');
 const experience=hazardExperience.parse(warned.receipt.experience);
 assert.equal(experience.mechanicsVersion,'dryrun.hazard-mechanics/5');
 assert('refugeRoomID'in experience&&experience.refugeRoomID==='sp-bed1');
 const mobile=input.household.people.find((p:any)=>p.needs.length===0)??input.household.people[0],person=mobile.id;
 const reach={kind:'reachHigherRefuge',target:person,value:'sp-bed1'};
 assert(experience.feasibleCommands?.some(c=>JSON.stringify(c)===JSON.stringify(reach)));
 let providerCalls=0;
 const gateway=new Gateway({async turn(){providerCalls++;
  if(providerCalls===1){const call={type:'function_call' as const,id:'preview-current',name:'evaluateCandidateAction',arguments:{command:{kind:'requestDecision'}}};return {text:'',steps:[call],calls:[call],usage:{}};}
  return {steps:[],calls:[],usage:{},text:JSON.stringify({commands:[{kind:'requestDecision'}],purpose:'The warning excludes the recorded living room. The host supports this resident reaching the confirmed upper refuge via the hall and stairs. The recorded case is currently with them in the hall; carrying it changes its actual exercise location. Other household approaches remain person-specific.',evidenceIDs:[person,'sp-bed1'],suggestedActions:[{id:'carry-case',label:'Carry the hall case to the recorded upper refuge',fact:'The case is recorded with the resident in the hall and has two usable liters.',implication:'Carrying it moves this recorded stock with the person; no quantity or safety is created.',commands:[{kind:'takeSupply',target:'kit-water',value:person},reach]},{id:'reach-without-case',label:'Reach the upper refuge without moving the case',fact:'The same computed approach is available for this resident.',implication:'The case remains at its recorded hall location; this action only records the person arriving.',commands:[reach]}]})};
 }});
 const binding={sessionID:warned.receipt.sessionID,revision:warned.receipt.revision,eventSequence:warned.receipt.eventSequence,contextDigest:warned.receipt.contextDigest,householdRevision:warned.session.initial.household.revision,homeRevision:warned.session.initial.home.revision};
 const context={binding,snapshot:minimizedSnapshot(warned.receipt),assistance:minimizedAssistance(warned.receipt),experience,household:warned.householdContext,homeScene:warned.homeScene,profiles:warned.directorProfiles,directorPolicy:warned.session.directorPolicy,directorState:warned.receipt.directorState,pending:warned.receipt.pending,learningObjectives:['Use actual computed refuge approaches and recorded stock.']};
 let proposal:any=await gateway.start('synthetic',{contractVersion:'dryrun.ai/1',requestID:'flood-refuge-current',role:'director',synthetic:true,context});
 while(proposal.status==='needs_client_tools'){
  const call=proposal.calls[0],tool=await executeDirectorTool(host,warned,binding,call);
  proposal=await gateway.resume('synthetic',{token:proposal.token,binding,callID:call.id,result:tool.result});
 }
 assert.equal(proposal.status,'completed');
 const directed=await host.request({op:'directorCommit',session:warned.session,proposal:proposal.proposal,binding});
 const acceptedOptions=[];
 for(const a of proposal.proposal.suggestedActions){const result=await commit(directed,'offered-'+a.id,a.commands);acceptedOptions.push({action:a,result});}
 assert.equal(acceptedOptions.length,2);assert(acceptedOptions.every(({result})=>result.receipt.experience.refugedPersonIDs.includes(person)));
 traces.push({gateway:'actual Gateway/host tools with synthetic model replies',initial:warned,proposal:proposal.proposal,directed,acceptedOptions});
 const carried=await commit(warned,'carry-then-ascend',[{kind:'takeSupply',target:'kit-water',value:person},reach]);
 const empty=await commit(warned,'ascend-without-case',[reach]);
 assert.equal(carried.receipt.inventory.items[0].locationID,'sp-bed1');assert.equal(empty.receipt.inventory.items[0].locationID,'sp-hall');
 assert.equal(carried.receipt.inventory.items[0].remaining,2);assert.equal(carried.receipt.inventory.items[0].consumed,0);
 assert.deepEqual(carried.session.inventory,empty.session.inventory);
 const scoped=directorProviderSchemas({binding:{sessionID:warned.receipt.sessionID,revision:warned.receipt.revision,eventSequence:warned.receipt.eventSequence,contextDigest:warned.receipt.contextDigest,householdRevision:warned.session.initial.household.revision,homeRevision:warned.session.initial.home.revision},snapshot:{simMinute:0,resources:{},services:{},unmetRequirements:[],unknowns:[]},experience,profiles:[],learningObjectives:[]});
 assert(JSON.stringify(scoped.output).includes('reachHigherRefuge'));assert(JSON.stringify(scoped.output).includes('takeSupply'));
 assert(experience.feasibleCommands?.some(c=>c.kind==='takeSupply'&&'target'in c&&c.target==='kit-water'));
 assert(carried.receipt.experience.feasibleCommands.some((c:any)=>c.kind==='transferSupply'&&c.target==='kit-water'&&c.value==='sp-bed1'));
 for(const branch of [carried,empty]){const replay=await host.request({op:'query',session:JSON.parse(JSON.stringify(branch.session))});assert.deepEqual(replay.receipt,branch.receipt);}
 const first={label:'Carry the recorded hall case to the supported upper refuge',commands:[{kind:'takeSupply',target:'kit-water',value:person},reach]},second={label:'Reach the supported upper refuge without moving the case',commands:[reach]};
 traces.push({decision:'Case stays below versus moves with the actual person',initial:warned,branches:[{...first,result:carried},{...second,result:empty}]});
 // Sharing the case in the upper room versus retaining it with its carrier changes ownership/location only, never invents water.
 const deposited=await commit(carried,'set-case-down',[{kind:'transferSupply',target:'kit-water',value:'sp-bed1'}]);
 assert.equal(deposited.receipt.inventory.items[0].carrierPersonID,undefined);assert.equal(deposited.receipt.inventory.items[0].remaining,2);
 traces.push({decision:'Put the carried case down at the recorded refuge versus retain it with the carrier',initial:carried,branches:[{commands:[{kind:'transferSupply',target:'kit-water',value:'sp-bed1'}],result:deposited},{commands:[],result:carried}]});
 const wheelchair=input.household.people.find((p:any)=>p.needs.includes('cannotUseStairs'));
 if(wheelchair){assert(!experience.feasibleCommands?.some(c=>c.kind==='reachHigherRefuge'&&'target'in c&&c.target===wheelchair.id));assert(experience.openGapIDs.includes('higherRefuge.'+wheelchair.id));}
 const source=await host.request({op:'query',session:stocked.session});assert.deepEqual(source.receipt,stocked.receipt);
 const report={synthetic:true,liveModelCalls:0,mode:'actual Core host and gateway contracts',passed:true,syntheticProviderCalls:providerCalls,mechanicsVersion:experience.mechanicsVersion,traces,sourceUnchanged:true,recordedLedgerUnchanged:true,partialHouseholdAccess:wheelchair?.id??null,native:'pending',humanReview:'pending',limits:'Recorded exercise approach/arrival only; no structural safety, assistance carry, travel or delay recommendation.'};
 await mkdir('../../artifacts/ai/flood-refuge',{recursive:true});await writeFile('../../artifacts/ai/flood-refuge/result.json',JSON.stringify(report,null,2)+'\n');
 await writeFile('../../fixtures/ai/flood-refuge-trace.json',JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({passed:true,liveModelCalls:0,syntheticProviderCalls:providerCalls,allOfferedActionsExecutable:true,computedRefugeArrival:true,carriedCaseFollowsPerson:true,recordedLedgerUnchanged:true,partialHouseholdAccess:!!wheelchair,native:'pending'}));
}finally{host.close();}
