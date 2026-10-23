import {z} from 'zod';
// Local native/portable persistence contract. Never send the whole local state to Gemini.
const id=z.string().min(1).max(120);
export const practiceSource=z.object({contractVersion:z.literal('dryrun.practice-capture/1'),sessionID:id,initialDigest:z.string().min(1).max(128),startingRevision:z.number().int().min(0).max(128),startingEventSequence:z.number().int().nonnegative(),evaluatorVersion:z.enum(['dryrun.practice-anchors/1','dryrun.practice-anchors/2','dryrun.practice-anchors/3','dryrun.hazard-checks/1','dryrun.hazard-checks/2']).optional(),startingReceiptDigest:z.string().min(1).max(128).optional()}).strict();
export const practiceObservation=z.object({competencyID:z.enum(['initialResponse','adaptation','communication','continuity']),actionID:id,acceptedRevision:z.number().int().min(1).max(128),receiptDigest:z.string().min(1).max(128),credit:z.union([z.literal(0),z.literal(0.5),z.literal(1)]).optional(),feedbackRevealed:z.boolean()}).strict();
// Local-only projection of a version-1 PracticeAttempt, frozen before any question is displayed.
export const practicePhasePlan=z.union([
 z.object({variantID:z.enum(['practice-check-a/1','practice-check-b/1']),phaseSources:z.array(practiceSource.extend({evaluatorVersion:z.literal('dryrun.practice-anchors/2')})).length(4)}).strict(),
 z.object({variantID:z.enum(['practice-check-a/2','practice-check-b/2']),phaseSources:z.array(practiceSource.extend({evaluatorVersion:z.literal('dryrun.practice-anchors/3')})).length(4)}).strict(),
 // practice-phases/3: same anchors, situations chosen up front from Core candidates (plan stays local to the phone).
 z.object({variantID:z.enum(['practice-check-a/3','practice-check-b/3']),phaseSources:z.array(practiceSource.extend({evaluatorVersion:z.literal('dryrun.practice-anchors/3')})).length(4)}).strict(),
]).superRefine((value,ctx)=>{
 if(new Set(value.phaseSources.map(source=>source.sessionID)).size!==4)ctx.addIssue({code:'custom',path:['phaseSources'],message:'distinct_frozen_sessions_required'});
});

export const hazardCheck=z.object({id,scenarioID:z.enum(['home-fire','tornado','flash-flood','freeze-power-loss','heat-grid-strain','water-outage']),competencyID:practiceObservation.shape.competencyID,actionKind:id,prompt:z.string().min(1).max(500)}).strict();
