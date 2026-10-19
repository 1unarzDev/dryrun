import {writeFile} from 'node:fs/promises';
import {Host} from './host.js';
const host=new Host();
try{
 let state=await host.request({op:'initialize',sample:'oak',scenarioID:'home-fire'});
 const input=state.session.initial;input.household.people[1].sleepingSpaceID='sp-bed2';input.variants=['hallway-smoke'];
 state=await host.request({op:'initialize',input});const original=JSON.stringify(state.session.initial);
 state=await host.request({op:'commit',session:state.session,commit:{id:'smoke',actor:'director',baseRevision:0,commands:[{kind:'startIncident',target:'evt.home-fire.fire-origin',hazard:'homeFire',value:'sp-hall',minute:0},{kind:'advance',minute:0}]}});
 const receipts=[];
 for(const helper of ['p-oak-1','p-oak-2']){
  state=await host.request({op:'commit',session:state.session,commit:{id:'assign-'+helper,actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'assignHelper',target:'p-oak-3',value:helper}]}});
  const inspected=await host.request({op:'query',session:state.session,tool:{kind:'inspectDependencies',baseRevision:state.receipt.revision}});
  receipts.push({receipt:state.receipt,dependencies:inspected.tool.dependencies});
 }
 if(receipts[0]!.receipt.assistance.find((a:any)=>a.personID==='p-oak-3').reachStatus!=='unreachable'||receipts[1]!.receipt.assistance.find((a:any)=>a.personID==='p-oak-3').reachStatus!=='reachable')throw new Error('assignment_not_applied');
 if(JSON.stringify(state.session.initial)!==original)throw new Error('facts_changed');
 const replay=await host.request({op:'query',session:state.session});if(JSON.stringify(replay.receipt)!==JSON.stringify(state.receipt))throw new Error('replay_mismatch');
 await writeFile('../../fixtures/ai/helper-reassignment.json',JSON.stringify({synthetic:true,receipts,session:state.session,receipt:state.receipt},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',reach:['unreachable','reachable'],capacity:'unknown',sourceUnchanged:true,replay:true}));
}finally{host.close();}
