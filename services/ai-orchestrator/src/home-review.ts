import {z} from 'zod';
import {featureContext,homeOutput} from './features.js';
const id=z.string().min(1).max(120);
export const homeConcernReviewProposal=z.object({id,homeRevision:z.number().int().nonnegative(),imageID:id,imageDigest:z.string().regex(/^[a-f0-9]{64}$/),
 box:z.tuple([z.number().min(0).max(1),z.number().min(0).max(1),z.number().min(0).max(1),z.number().min(0).max(1)]),roomID:id.nullable().optional(),
 category:z.enum(['possibleObstruction','tripHazard','supplyAccess']),visibleEvidence:z.string().min(1).max(600),unknowns:z.array(z.string().min(1).max(600)).min(1).max(12),actionID:id,scenarioIDs:z.array(id).min(1).max(6)}).strict();
/** Transport normalization, not confirmation or image-to-world projection. Core validates again. */
export function normalizeHomeReview(raw:unknown,rawContext:unknown){
 const output=homeOutput.parse(raw),context=featureContext.parse(rawContext);
 if(!context.scene)throw new Error('home_scene_required');
 return output.concerns.map(concern=>{
  const manifest=context.images?.find(i=>i.id===concern.imageID);
  if(!manifest||manifest.homeRevision!==context.scene!.homeRevision||concern.roomID!==manifest.roomID||concern.roomID!==null&&!context.scene!.rooms.some(r=>r.id===concern.roomID)||!context.allowedActionIDs.includes(concern.actionID))throw new Error('stale_or_unbound_concern');
  if(manifest.redactedRegions.some(a=>Math.max(0,Math.min(a[2],concern.box[2])-Math.max(a[0],concern.box[0]))*Math.max(0,Math.min(a[3],concern.box[3])-Math.max(a[1],concern.box[1]))>0))throw new Error('redacted_evidence');
  return homeConcernReviewProposal.parse({id:concern.id,homeRevision:manifest.homeRevision,imageID:manifest.id,imageDigest:manifest.digest,box:concern.box,roomID:concern.roomID,category:concern.category,
   visibleEvidence:concern.visibleEvidence,unknowns:[...concern.alternatives,...output.limitations].slice(0,12),actionID:concern.actionID,scenarioIDs:concern.scenarioIDs});
 });
}
