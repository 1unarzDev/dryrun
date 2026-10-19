import {z} from 'zod';
// Local native/portable persistence contract. Never send the whole local state to Gemini.
const id=z.string().min(1).max(120);
export const practiceSource=z.object({contractVersion:z.literal('dryrun.practice-capture/1'),sessionID:id,initialDigest:z.string().min(1).max(128),startingRevision:z.number().int().min(0).max(128),startingEventSequence:z.number().int().nonnegative(),evaluatorVersion:z.enum(['dryrun.practice-anchors/1','dryrun.practice-anchors/2']).optional()}).strict();
export const practiceObservation=z.object({competencyID:z.enum(['initialResponse','adaptation','communication','continuity']),actionID:id,acceptedRevision:z.number().int().min(1).max(128),receiptDigest:z.string().min(1).max(128),credit:z.union([z.literal(0),z.literal(0.5),z.literal(1)]).optional(),feedbackRevealed:z.boolean()}).strict();
