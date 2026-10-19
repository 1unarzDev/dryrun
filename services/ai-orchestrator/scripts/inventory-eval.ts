import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {GeminiProvider} from '../src/provider.js';
import {FeatureRunner,preparationOutput} from '../src/features.js';
const host=new Host(),runner=new FeatureRunner(new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??''));
const cases=[{id:'typed-water',text:'I have one sealed water bottle. Its printed volume is 2 liters. This describes one physical bottle, not a shopping request.',expected:2},{id:'unknown-water',text:'I have one water container. The volume label is unreadable and I do not know how full it is. Do not estimate the quantity.',expected:null}];
const results=[];
try{const state=await host.request({op:'initialize'});for(const c of cases){
 const output=preparationOutput.parse(await runner.run('preparation',{household:state.householdContext,tasks:[],gaps:[],allowedActionIDs:[],allowedCriterionIDs:[],intake:[{id:c.id,text:c.text}]}));
 const observations=output.inventoryObservations.filter(i=>i.category==='water');
 const matched=observations.length===1&&observations[0]!.quantity===c.expected&&(c.expected===null||observations[0]!.unit==='liter');
 results.push({id:c.id,intake:c.text,expected:c.expected,output,matched});
}
 await writeFile('../../fixtures/ai/inventory-evaluation.json',JSON.stringify({synthetic:true,model:'gemini-3.1-flash-lite',sdk:'2.30.0',prompt:'preparation/2',schema:'preparation-v1',inventoryCategoryVersion:'dryrun.inventory-categories/1',calls:runner.calls,usage:runner.usage,results},null,2));console.log(JSON.stringify({fixtures:2,matched:results.filter(r=>r.matched).length}));
 assert.equal(results.filter(r=>r.matched).length,cases.length,'inventory_expectations_failed');
}finally{host.close();}
