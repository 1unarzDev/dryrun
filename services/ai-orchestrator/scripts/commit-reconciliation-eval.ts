import assert from 'node:assert/strict';
import {Host} from './host.js';
const host=new Host();try{
 let state=await host.request({op:'initialize',scenarioID:'water-outage'});
 const command=state.receipt.experience.feasibleCommands.find((c:any)=>c.kind==='useWater');assert(command);
 const commit={id:'synthetic-lost-ack',actor:'user',baseRevision:state.receipt.revision,commands:[command]};
 const before=await host.request({op:'reconcileCommit',session:state.session,commit});assert.equal(before.commitResolution.status,'absent');
 // Treat this return as a lost acknowledgement; native would reload its authoritative durable snapshot.
 state=await host.request({op:'commit',session:state.session,commit});const durable=JSON.parse(JSON.stringify(state.session));
 const reconciled=await host.request({op:'reconcileCommit',session:durable,commit});assert.equal(reconciled.commitResolution.status,'committed');assert.equal(reconciled.commitResolution.acceptedRevision,1);assert.deepEqual(reconciled.receipt,state.receipt);
 await assert.rejects(host.request({op:'commit',session:durable,commit}),/duplicate/);
 await assert.rejects(host.request({op:'reconcileCommit',session:durable,commit:{...commit,commands:[{kind:'unsupported'}]}}),/duplicate/);
 const replay=await host.request({op:'query',session:durable});assert.deepEqual(replay.receipt,state.receipt);
 console.log(JSON.stringify({synthetic:true,passed:true,modelCalls:0,lostAcknowledgement:'reconciled',resourceEffects:1,conflictingID:'rejected',duplicate:'rejected',durableStorage:'synthetic serialized snapshot; native pending'}));
}finally{host.close();}
