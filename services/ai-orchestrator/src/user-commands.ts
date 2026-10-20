import {z} from 'zod';
const id=z.string().min(1).max(120);
const pair=(kind:string)=>z.object({kind:z.literal(kind),target:id,value:id}).strict();
/** Suggestions remain user-only commands; the host previews and commits only after explicit selection. */
export const userCommand=z.union([
 ...['moveTo','takeSupply','transferSupply','assignHelper','allocatePower','closeDoor','choose','escape','reachHigherRefuge','reachShelter','accompanyEscape','accompanyShelter'].map(pair),
 ...['identifyGap','contact','accountOutside','leaveEarly','heatedAlternative','cooledAlternative','reduceSolarGain'].map(kind=>z.object({kind:z.literal(kind),target:id}).strict()),
 z.object({kind:z.literal('warmLayers')}).strict(),
 z.object({kind:z.literal('useWater'),target:id,value:z.enum(['drink','prepareFood','hygiene','boiledDrink']),quantityLiters:z.number().positive().max(20)}).strict(),
 z.object({kind:z.literal('useStoredWater'),value:z.enum(['essential','all'])}).strict(),
 z.object({kind:z.literal('finish')}).strict(),
]);
export const suggestedAction=z.object({id,label:z.string().min(1).max(160),fact:z.string().min(1).max(400),implication:z.string().min(1).max(400),commands:z.array(userCommand).min(1).max(8)}).strict();
