import {z} from 'zod';
import {command,directorOutput,type DirectorContext} from './contracts.js';
import {requireCompletedFireActions,completedHomeDeparture} from './director-boundaries.js';
import {suggestedAction,userCommand} from './user-commands.js';

/** Shape the provider's effect language to recorded affordances, never its prose or task ideas.
 * The ordinary parser, policy and actual host preview remain the acceptance authorities.
 */
export function directorProviderSchemas(context:DirectorContext,previewExperience?:DirectorContext['experience'],previewCommands?:z.infer<typeof command>[]){
 const unused=context.profiles.filter(p=>!context.snapshot.firedEventIDs?.includes(p.id)&&!context.pending?.some(c=>'target'in c&&c.target===p.id));
 const minute=z.number().int().min(context.snapshot.simMinute).max(context.directorPolicy?.schedulingHorizonMinutes??4320);
 let canFinish=true;
 try{requireCompletedFireActions([{kind:'finish'}],previewExperience??context.experience);}catch{canFinish=false;}
 const options:z.ZodType[]=[...command.options.filter(s=>['advance','waitUntil','requestDecision',...(canFinish?['finish']:[])].includes(s.shape.kind.value))];
 if(unused.length)options.push(z.object({kind:z.literal('schedule'),target:z.enum(unused.map(p=>p.id)),minute}).strict());
 const rooms=context.homeScene?.rooms.map(r=>r.id)??[];
 for(const family of context.directorPolicy?.permittedHazardFamilies??[]){
  const profiles=unused.filter(p=>p.spatial&&p.hazard===family);
  const starts=profiles.filter(p=>p.canStart);
  if(starts.length&&!context.directorState?.activeIncidentCount){
   for(const roomRequired of [true,false]){
    const ids=starts.filter(p=>Boolean(p.roomRequired)===roomRequired).map(p=>p.id);
    if(ids.length&&(!roomRequired||rooms.length))options.push(z.object({kind:z.literal('startIncident'),target:z.enum(ids),hazard:z.literal(family),minute,...(roomRequired?{value:z.enum(rooms)}:{})}).strict());
   }
  }
  // A later spatial stage can follow a start in this same proposal; the host checks transitions.
  const stages=profiles.filter(p=>!p.canStart).map(p=>p.id);
  if(stages.length)options.push(z.object({kind:z.literal('advanceIncident'),target:z.enum(stages),hazard:z.literal(family),minute}).strict());
 }
 // A completed modeled departure has no supported destination geometry or new
 // trapped-home objective. Debrief that action instead of generating home failures.
 if(completedHomeDeparture(context.experience))options.splice(0,options.length,command.options.find(s=>s.shape.kind.value==='finish')!);
 const scoped=options.length===1?options[0]!:z.union(options as [z.ZodType,z.ZodType,...z.ZodType[]]);
 // Once preview succeeds, effect fields are a receipt to repeat, not a new incident
 // composition opportunity. Narrative and whole user-action sequences remain open below.
 const finalOptions:z.ZodType[]=previewCommands===undefined?options:[
  ...previewCommands.filter(c=>!['requestDecision','finish'].includes(c.kind)).map(c=>
   z.object(Object.fromEntries(Object.entries(c).filter(([,value])=>value!==undefined).map(([key,value])=>[key,z.literal(value as string|number)]))).strict()),
  ...(completedHomeDeparture(context.experience)?[]:[command.options.find(s=>s.shape.kind.value==='requestDecision')!]),
  ...(canFinish?[command.options.find(s=>s.shape.kind.value==='finish')!]:[]),
 ];
 const finalCommand=finalOptions.length===1?finalOptions[0]!:z.union(finalOptions as [z.ZodType,z.ZodType,...z.ZodType[]]);
 const experience=previewExperience??context.experience;
 let suggestions:z.ZodType=suggestedAction;
 if(experience){
  const gaps=experience.openGapIDs.filter(id=>!experience.identifiedGapIDs.includes(id));
  const feasibleKinds=experience.feasibleCommands?.map(c=>c.kind);
  const userOptions:z.ZodType[]=userCommand.options.filter(s=>(!feasibleKinds||feasibleKinds.includes(s.shape.kind.value))&&s.shape.kind.value!=='identifyGap'&&(!context.household||s.shape.kind.value!=='allocatePower'));
  if(context.household&&(!feasibleKinds||feasibleKinds.includes('allocatePower')))for(const equipment of context.household.equipment){
   const sources=[...(equipment.compatibleBackupIDs??[]),...(equipment.essential?[]:['none'])];
   if(sources.length)userOptions.push(z.object({kind:z.literal('allocatePower'),target:z.literal(equipment.id),value:z.enum(sources)}).strict());
  }
  if(gaps.length)userOptions.push(z.object({kind:z.literal('identifyGap'),target:z.enum(gaps)}).strict());
  const scopedUser=userOptions.length?z.union(userOptions as [z.ZodType,z.ZodType,...z.ZodType[]]):z.union(userCommand.options.filter(s=>s.shape.kind.value!=='identifyGap') as unknown as [z.ZodType,z.ZodType,...z.ZodType[]]);
  suggestions=suggestedAction.extend({commands:z.array(scopedUser).min(1).max(8)});
 }
 return {
  preview:z.toJSONSchema(z.object({command:scoped.optional(),commands:z.array(scoped).min(1).max(8).optional()}).strict()),
  output:z.toJSONSchema(directorOutput.extend({commands:z.array(finalCommand).min(1).max(8).describe("Repeat each previewed effect once, in its previewed order, then optionally request a decision or finish. No new effects or changed fields."),suggestedActions:z.array(suggestions).max(4).optional()})),
 };
}
