import {it,expect} from 'vitest';
import {compileDirectorEnvelope,directorProposalEnvelope} from '../src/director-envelope.js';
const binding={sessionID:'session',revision:3,eventSequence:7,contextDigest:'source-digest',householdRevision:2,homeRevision:4};
it('carries the complete source binding and marks presentation as unverified until the host commits',()=>{
 const envelope=compileDirectorEnvelope('request',binding,{commands:[{kind:'advance',minute:60},{kind:'requestDecision'}],purpose:'Inspect the actual host result',evidenceIDs:[]});
 expect(envelope.requestID).toBe('request');expect(envelope.binding).toEqual(binding);expect(envelope.baseRevision).toBe(3);
 expect(envelope.nextBoundary).toEqual({kind:'pauseForDecision',requestedMinute:60});
 expect(envelope.presentationIntent).toEqual({focus:'decision',sceneFirst:true,renderFrom:'committedReceipt',narration:'unverifiedProposal'});
 expect(envelope.assumptionIDs).toEqual(['assumption.educational-incident-profiles/1']);
 expect(()=>directorProposalEnvelope.parse({...envelope,binding:undefined})).toThrow();
});
it('labels a bounded wait as requested duration rather than a promised arrival time',()=>{
 const envelope=compileDirectorEnvelope('wait',binding,{commands:[{kind:'waitUntil',target:'nextIncident',durationMinutes:15}],purpose:'Wait to the next host boundary',evidenceIDs:[]});
 expect(envelope.nextBoundary).toEqual({kind:'advanceUntilHostBoundary',maximumDurationMinutes:15});
});
