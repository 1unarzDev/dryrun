import {createHash} from 'node:crypto';
import {evaluationKey} from './eval-key.js';
import {Host} from './host.js';
import {FeatureRunner,featureContext,rubricSchema} from '../src/features.js';
import {ProviderFailure} from '../src/provider-failure.js';
import {GeminiProvider,SpendBudget} from '../src/provider.js';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
const host=new Host(),budget=new SpendBudget(Number(process.env.DRYRUN_MAX_USD??1));
const model=process.env.DRYRUN_PREPARATION_MODEL??'gemini-3.1-flash-lite';
const deadlineMs=Number(process.env.DRYRUN_PERSONALIZATION_DEADLINE_MS??60000);
if(!Number.isInteger(deadlineMs)||deadlineMs<1000||deadlineMs>120000)throw new Error('invalid_evaluation_deadline');
const promptRuns:{sha256:string;version:string}[]=[];
const provider=new GeminiProvider(await evaluationKey(),model,budget);
const providerTurns:unknown[]=[];
const runner=new FeatureRunner({async turn(input){promptRuns.push({version:'preparation/13',sha256:createHash('sha256').update(input.instruction).digest('hex')});try{const reply=await provider.turn(input);providerTurns.push({text:reply.text,calls:reply.calls.map(c=>({name:c.name,arguments:c.arguments})),usage:reply.usage});return reply;}catch(error){providerTurns.push({error:error instanceof Error?error.message:'provider_error',...(error instanceof ProviderFailure?{kind:error.kind,status:error.status,retryAfterMs:error.retryAfterMs,diagnostic:error.diagnostic}:{})});throw error;}}},20);
const rubric=rubricSchema.parse(JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8')));
const cases:any[]=[];
const runID=new Date().toISOString().replace(/[:.]/g,'-');
await mkdir('../../artifacts/ai/personalization',{recursive:true});
try {
 const baseline=await host.request({op:'initialize',sample:'lake',scenarioID:'heat-grid-strain'});
 const original=baseline.session.initial;
 original.household.people=original.household.people.slice(0,2).map((p:any)=>({...p,ageBand:'adult',needs:[],emergencyInformation:undefined,communicationNotes:undefined}));
 original.household.equipment=[];original.household.pets=[];
 for(const mutation of ['baseline','recorded-communication','medication-storage','upper-apartment','absent-extinguisher','accessible-inventory','inaccessible-inventory'].filter(m=>!process.env.DRYRUN_PERSONALIZATION_CASE||process.env.DRYRUN_PERSONALIZATION_CASE.split(',').includes(m))){
  const input=structuredClone(original),h=input.household;
  if(mutation==='recorded-communication'){h.people[0].needs=['communicationSupport'];h.people[0].emergencyInformation={criticalConditions:'Synthetic recorded ADHD',severeAllergies:'',essentialMedication:'',responderInstructions:''};h.people[0].communicationNotes='Use a short written two-step list; ask the person to choose the reminder format.';}
  if(mutation==='medication-storage'){h.people[0].emergencyInformation={criticalConditions:'',severeAllergies:'',essentialMedication:'Synthetic recorded medicine, with pharmacy travel instructions',responderInstructions:''};h.equipment=[{...baseline.session.initial.household.equipment[0],id:'synthetic-cold',personID:h.people[0].id,purpose:'refrigeratedMedication',label:'',isEssential:true,requiresElectricalPower:false,requiresColdStorage:true,storageInstructions:'Synthetic recorded instruction: retain in its labeled insulated carrier and check the pharmacist-provided storage sheet. No temperature or duration recorded.',compatibleBackupIDs:[]}];}
  if(mutation==='upper-apartment'){h.housing.homeType='apartment';h.housing.floorCount=3;}
  if(mutation==='absent-extinguisher'){h.supplies.fireExtinguisher={value:false,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]};}
  const turnStart=providerTurns.length;
  let item:any={mutation};
  try{
   let state=await host.request({op:'initialize',input,rubric});
   if(mutation.endsWith('-inventory')){const ev=(value:unknown)=>({value,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]});state=await host.request({op:'confirmInventory',session:state.session,rubric,inventoryItems:[{id:'synthetic-recorded-water',physicalID:'synthetic-private-stock-label',category:'water',quantity:ev(12),usableQuantity:ev(12),unit:'liter',accessible:ev(mutation==='accessible-inventory'),locationID:'sp-closet',subjectIDs:[],evidenceIDs:['typed-water']}]});}
   const context=featureContext.parse({household:state.householdContext,taskCatalog:state.taskCatalog,tasks:[],gaps:state.gaps??[],allowedActionIDs:state.preparationActions,allowedCriterionIDs:rubric.criteria.map(c=>c.id),rubric,scene:state.homeScene});
   item.serializedRoleInput=context;
   const accepted=await runner.run('preparation',context,AbortSignal.timeout(deadlineMs));
   item={mutation,status:'accepted',serializedRoleInput:context,accepted};
  }catch(error){item={...item,mutation,status:'failed',error:error instanceof Error?error.message:'unknown'};process.exitCode=1;}
  item.providerTurns=providerTurns.slice(turnStart);
  cases.push(item);console.log(JSON.stringify({mutation,status:item.status}));
  const report={synthetic:true,liveModelTested:true,model,sdk:'2.30.0',deadlineMs,promptRuns,runID,keySlot:process.env.DRYRUN_USE_BACKUP_KEY==='1'?'backup':'primary',thinking:'high',cases,calls:runner.calls,usage:runner.usage,accountedUSD:budget.spentUSD,qualityReview:'pending: inspect fact -> implication -> action changes; accepted JSON alone is not a quality pass',native:'pending'};
  await writeFile('../../artifacts/ai/personalization/paired-live.json',JSON.stringify(report,null,2)+'\n');
  await mkdir('../../artifacts/ai/personalization/runs/'+runID,{recursive:true});
  await writeFile('../../artifacts/ai/personalization/runs/'+runID+'/paired-live.json',JSON.stringify(report,null,2)+'\n');
 }
}finally{host.close();}
