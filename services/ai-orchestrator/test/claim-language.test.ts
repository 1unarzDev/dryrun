import {it,expect} from 'vitest';
import {rejectUnsupportedAssurances} from '../src/claim-language.js';
it('rejects observed numeric-load and future reliability assurances while retaining grounded proposals',()=>{
 for(const text of ['Verifying this ensures the available 1000Wh can reliably support essential loads.','This ensures the family reaches safety.','This guarantees continuity.'])expect(()=>rejectUnsupportedAssurances([text])).toThrow('unsupported_safety_assurance');
 for(const text of ['The recorded 1000Wh backup has unknown setup and documented compatibility. Review its instructions.','A recorded destination does not guarantee continuity.','The host computed a 0.25 liter draw; this is an exercise activity quantity.'])expect(()=>rejectUnsupportedAssurances([text])).not.toThrow();
});

it('rejects actual live drill-certification and clinical-supply claims without suppressing recorded equipment reasoning',()=>{
 expect(()=>rejectUnsupportedAssurances(['Accounting for each person officially confirms their safe escape and completes the evacuation procedure.'])).toThrow('unsupported_safety_assurance');
 expect(()=>rejectUnsupportedAssurances(['Allocating power from the portable battery station maintains the necessary oxygen supply for the duration of the outage.'])).toThrow('unsupported_clinical_assurance');
 expect(()=>rejectUnsupportedAssurances(['No backup is recorded, but this ensures safety.'])).toThrow('unsupported_safety_assurance');
 expect(()=>rejectUnsupportedAssurances(['The host records electricity to the oxygen concentrator now. Its documented runtime is limited; manufacturer and clinical continuity requirements remain unassessed.'])).not.toThrow();
 expect(()=>rejectUnsupportedAssurances(['Accounting records who was observed outside in this exercise; it does not certify structural safety or future evacuation.'])).not.toThrow();
});

it('scopes negation to an actual claim and catches the retained tornado wording',()=>{
 for(const text of [
  'No destination guarantees safety or equipment continuity.',
  'Relocating is a recorded arrangement; it does not ensure service reliability, equipment function, or comfort.',
  'The occupants are not safely sheltered.',
 ])expect(()=>rejectUnsupportedAssurances([text])).not.toThrow();
 for(const text of [
  'All household members have safely escaped and have been accounted for outside.',
  'As all occupants are safely sheltered for the duration of the current warning, end the exercise.',
  'Ensure everyone reaches the shelter safely.',
  'No backup is recorded and this ensures continuity.',
  'The route does not change, which ensures safety.',
  'No destination is available, this guarantees continuity.',
 ])expect(()=>rejectUnsupportedAssurances([text])).toThrow('unsupported_safety_assurance');
});
