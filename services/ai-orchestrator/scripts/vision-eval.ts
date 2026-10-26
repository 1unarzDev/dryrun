import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {FeatureRunner,homeOutput} from '../src/features.js';
import {GeminiProvider} from '../src/provider.js';
const fixtures=JSON.parse(await readFile('../../fixtures/ai/images/annotations.json','utf8'));const host=new Host();const model=process.env.DRYRUN_MODEL??'gemini-3.1-flash-lite';const runner=new FeatureRunner(new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??'',model));
const results=[];
try{const state=await host.request({op:'initialize'});for(const c of fixtures.cases){const output=homeOutput.parse(await runner.run('home',{household:state.householdContext,tasks:[],gaps:[],allowedActionIDs:state.preparationActions,allowedCriterionIDs:[],scene:state.homeScene,images:[c.manifest]},AbortSignal.timeout(60000),[{id:c.manifest.id,mimeType:'image/png',data:(await readFile('../../'+c.path)).toString('base64')}]));results.push({fixture:c.name,expected:c.expected,output,matchedCategory:c.expected.length?output.concerns.some(x=>c.expected.includes(x.category)):output.concerns.length===0});}
await writeFile(process.env.DRYRUN_MODEL?`../../fixtures/ai/vision-evaluation-${model}.json`:'../../fixtures/ai/vision-evaluation.json',JSON.stringify({synthetic:true,model,sdk:'2.30.0',calls:runner.calls,usage:runner.usage,results},null,2));console.log(JSON.stringify({syntheticImages:results.length,matched:results.filter(r=>r.matchedCategory).length,calls:runner.calls}));}finally{host.close();}
