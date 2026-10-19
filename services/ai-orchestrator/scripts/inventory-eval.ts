import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {GeminiProvider} from '../src/provider.js';
import {FeatureRunner,preparationOutput} from '../src/features.js';
const host=new Host(),runner=new FeatureRunner(new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??''));
const cases=[{id:'typed-water',text:'I have one sealed water bottle. Its printed volume is 2 liters. This describes one physical bottle, not a shopping request.',expected:2,category:'water',unit:'liter'},{id:'unknown-water',text:'I have one water container. The volume label is unreadable and I do not know how full it is. Do not estimate the quantity.',expected:null,category:'water',unit:null},{id:'whole-household-food-days',text:'I own nonperishable, easy-to-prepare food. I have reviewed it and know it covers my entire household for exactly three days. This is recorded household coverage, not a package count.',expected:3,category:'food',unit:'day'},{id:'food-package-count',text:'I own six cans of beans, all six are one recorded batch. I do not know how many days they cover my household. Preserve the package count; do not estimate days.',expected:6,category:'food',unit:'count'}];
const results=[];
try{const state=await host.request({op:'initialize'});for(const c of cases){
 const output=preparationOutput.parse(await runner.run('preparation',{household:state.householdContext,tasks:[],gaps:[],allowedActionIDs:[],allowedCriterionIDs:[],intake:[{id:c.id,text:c.text}]}));
 const observations=output.inventoryObservations.filter(i=>i.category===c.category);
 const matched=observations.length===1&&observations[0]!.quantity===c.expected&&(c.unit===null||observations[0]!.unit===c.unit);
 results.push({id:c.id,intake:c.text,expected:c.expected,expectedCategory:c.category,expectedUnit:c.unit,output,matched});
}
 await writeFile('../../fixtures/ai/inventory-evaluation.json',JSON.stringify({synthetic:true,model:'gemini-3.1-flash-lite',sdk:'2.30.0',prompt:'preparation/3',schema:'preparation-v1',inventoryCategoryVersion:'dryrun.inventory-categories/1',calls:runner.calls,usage:runner.usage,results},null,2));console.log(JSON.stringify({fixtures:cases.length,matched:results.filter(r=>r.matched).length}));
 assert.equal(results.filter(r=>r.matched).length,cases.length,'inventory_expectations_failed');
}finally{host.close();}
