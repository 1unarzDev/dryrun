import {z} from 'zod';
import {suggestedAction} from './user-commands.js';
import {binding,command,directorOutput} from './contracts.js';
export const nextBoundary=z.object({kind:z.enum(['pauseForDecision','finishExercise','advanceUntilHostBoundary','scheduledIncident','noAdvance']),requestedMinute:z.number().int().nonnegative().max(4320).optional(),maximumDurationMinutes:z.number().int().min(1).max(4320).optional()}).strict();
export const presentationIntent=z.object({focus:z.enum(['decision','summary','scene','resources']),sceneFirst:z.literal(true),renderFrom:z.literal('committedReceipt'),narration:z.literal('unverifiedProposal')}).strict();
export const directorProposalEnvelope=z.object({contractVersion:z.literal('dryrun.director-proposal/1'),id:z.string().min(1).max(120),requestID:z.string().min(1).max(120),actor:z.literal('director'),baseRevision:z.number().int().nonnegative(),binding,suggestedActions:z.array(suggestedAction).max(4).optional(),commands:z.array(command).min(1).max(8),purpose:z.string().min(1).max(900),evidenceIDs:z.array(z.string().max(120)).max(20),assumptionIDs:z.array(z.string().max(120)).max(20),nextBoundary,presentationIntent}).strict();
/** Metadata describes the requested transition; actual time/effects always come from Core's receipt. */
export function compileDirectorEnvelope(requestID:string,contextBinding:z.infer<typeof binding>,proposal:z.infer<typeof directorOutput>){
 const commands=proposal.commands;
 const terminal=commands.at(-1)!;
 const pacing=commands.find(c=>c.kind==='advance'||c.kind==='waitUntil');
 const incident=commands.find(c=>c.kind==='schedule'||c.kind==='startIncident'||c.kind==='advanceIncident');
 const spatial=commands.some(c=>c.kind==='startIncident'||c.kind==='advanceIncident');
 const kind=terminal.kind==='requestDecision'?'pauseForDecision':terminal.kind==='finish'?'finishExercise':pacing?'advanceUntilHostBoundary':incident?'scheduledIncident':'noAdvance';
 const focus=terminal.kind==='requestDecision'?'decision':terminal.kind==='finish'?'summary':spatial?'scene':'resources';
 return directorProposalEnvelope.parse({contractVersion:'dryrun.director-proposal/1',id:requestID,requestID,actor:'director',baseRevision:contextBinding.revision,binding:contextBinding,...proposal,
  assumptionIDs:['assumption.educational-incident-profiles/1'],nextBoundary:{kind,...(pacing?.kind==='advance'?{requestedMinute:pacing.minute}:pacing?.kind==='waitUntil'?{maximumDurationMinutes:pacing.durationMinutes}:incident&&'minute'in incident?{requestedMinute:incident.minute}:{})},
  presentationIntent:{focus,sceneFirst:true,renderFrom:'committedReceipt',narration:'unverifiedProposal'}});
}
