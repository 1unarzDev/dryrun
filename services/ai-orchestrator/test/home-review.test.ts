import {it,expect} from 'vitest';
import {normalizeHomeReview} from '../src/home-review.js';
const manifest={id:'image',homeRevision:1,roomID:'room',digest:'a'.repeat(64),capturedAt:'2026-10-19T00:00:00Z',width:640,height:480,orientation:'up',transforms:[],calibration:'none',redactedRegions:[]};
const context={household:{revision:1,people:[],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[]},tasks:[],gaps:[],allowedActionIDs:['prep.clearExits'],allowedCriterionIDs:[],images:[manifest],scene:{schemaVersion:'dryrun.home-scene/1',homeRevision:1,units:'meter',coordinateConvention:'per-floor',floors:[],rooms:[{id:'room',floorID:'floor',polygon:[],use:'livingRoom',confirmed:true}],portals:[],walls:[],connectors:[],obstacles:[],objects:[],unknowns:[]}};
const output={concerns:[{id:'concern',category:'possibleObstruction',roomID:'room',imageID:'image',box:[0.1,0.1,0.4,0.4],visibleEvidence:'Object near opening',concern:'Possible restricted clearance',alternatives:['Could be beside the opening'],urgency:'review',confirmationPrompt:'Is the opening clear?',sourceIDs:['S19'],actionID:'prep.clearExits',scenarioIDs:['home-fire']}],limitations:['Image has no aligned depth']};
it('normalizes the exact source image identity without confirming or projecting it',()=>{
 const [proposal]=normalizeHomeReview(output,context);expect(proposal?.homeRevision).toBe(1);expect(proposal?.imageDigest).toBe(manifest.digest);expect(proposal?.unknowns).toContain('Image has no aligned depth');expect(proposal).not.toHaveProperty('decision');expect(proposal).not.toHaveProperty('portalIDs');
});
it('rejects stale home, wrong room, redacted evidence and unknown task identities',()=>{
 expect(()=>normalizeHomeReview(output,{...context,scene:{...context.scene,homeRevision:2}})).toThrow('stale_or_unbound_concern');
 expect(()=>normalizeHomeReview(output,{...context,scene:{...context.scene,rooms:[]}})).toThrow('stale_or_unbound_concern');
 expect(()=>normalizeHomeReview(output,{...context,images:[{...manifest,redactedRegions:[[0,0,1,1]]}]})).toThrow('redacted_evidence');
 expect(()=>normalizeHomeReview(output,{...context,allowedActionIDs:[]})).toThrow('stale_or_unbound_concern');
});
