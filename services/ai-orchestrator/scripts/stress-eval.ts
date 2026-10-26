import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {Host} from './host.js';
const host=new Host();
try {
 const state=await host.request({op:'initialize',scenarioID:'water-outage'});
 const profileIDs=['evt.water-outage.well-pump-failure'];
 const result=await host.request({op:'stress',session:state.session,profileIDs,intervention:{actionID:'act.water.store-3day',parameters:{}}});
 const finding=result.stress;
 const depletion=(receipt:any)=>receipt.events.find((e:any)=>e.id.includes('water-depleted'))?.simMinute;
 assert.equal(depletion(finding.baseline),1800);assert.equal(depletion(finding.controlledRetest),4320);
 assert.equal(state.session.initial.household.supplies.storedWaterGallons.value,5);
 const replay=await host.request({op:'stress',session:state.session,profileIDs,intervention:{actionID:'act.water.store-3day',parameters:{}}});
 assert.equal(finding.baseline.contextDigest,replay.stress.baseline.contextDigest);
 assert.equal(finding.controlledRetest.contextDigest,replay.stress.controlledRetest.contextDigest);
 for(const kind of ['inspectScene','queryRoutes','evaluateResources','inspectDependencies']) {
  const query=await host.request({op:'tool',session:state.session,tool:{kind,baseRevision:0}});assert.equal(query.receipt.contextDigest,state.receipt.contextDigest);assert.ok(query.tool.receipt);
 }
 await writeFile('../../fixtures/ai/controlled-stress.json',JSON.stringify({synthetic:true,intervention:'Hypothetical water storage only; real profile unchanged',baselineDepletion:depletion(finding.baseline),retestDepletion:depletion(finding.controlledRetest),finding},null,2));
 console.log(JSON.stringify({passed:true,baselineDepletion:1800,retestDepletion:4320,readTools:4}));
}finally{host.close();}
