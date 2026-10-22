import {readFile} from 'node:fs/promises';
import {it,expect} from 'vitest';
import {hazardExperience,directorContext,minimizedSnapshot} from '../src/contracts.js';
import {directorProviderSchemas} from '../src/director-provider-schema.js';
import {practiceSource} from '../src/practice-contracts.js';
import {userCommand} from '../src/user-commands.js';
const fixture=JSON.parse(await readFile('../../fixtures/ai/fire-accompaniment-trace.json','utf8'));

it('retains actual paired exits, helper identity and remaining roster through the gateway transport',()=>{
 const initial=fixture.initial,experience=hazardExperience.parse(initial.receipt.experience);
 expect(experience.mechanicsVersion).toBe('dryrun.hazard-mechanics/5');
 const context=directorContext.parse({binding:fixture.proposal.binding,snapshot:minimizedSnapshot(initial.receipt),experience,household:initial.householdContext,homeScene:initial.homeScene,profiles:initial.directorProfiles,learningObjectives:[]});
 expect(JSON.stringify(directorProviderSchemas(context).output)).toContain('accompanyEscape');
 for(const branch of fixture.branches){
  expect(userCommand.safeParse(branch.action.commands[0]).success).toBe(true);
  const after=hazardExperience.parse(branch.result.receipt.experience);
  expect(after).toHaveProperty('escapeHelperByPersonID');
  expect(after.outsidePersonIDs).toHaveLength(2);expect(after.accountedPersonIDs).toEqual([]);
 }
 expect(fixture.helperLeftAlone.receipt.experience.openGapIDs.some((id:string)=>id.startsWith('escapeAssistance.'))).toBe(true);
 expect(hazardExperience.safeParse({...fixture.branches[0].result.receipt.experience,mechanicsVersion:'dryrun.hazard-mechanics/4'}).success).toBe(false);
 expect(userCommand.safeParse({kind:'accompanyEscape',target:'person',value:'exit',helperID:'invented'}).success).toBe(false);
});

it('round-trips the actual versioned practice source and one retired fixed-budget anchor',()=>{
 const attempt=fixture.practice.scored.aiState.practiceAttempts[0];
 expect(practiceSource.parse(attempt.source).evaluatorVersion).toBe('dryrun.hazard-checks/2');
 expect(attempt.checkID).toBe('fire.escape/1');expect(attempt.observations[0].credit).toBe(1);
 expect(fixture.practice.scored.scorecard.practice).toBe(25/3);
 expect(fixture.practice.restored.scorecard.practice).toBe(25/3);
 expect(fixture.practice.scored.pendingHazardChecks.some((c:any)=>c.id==='fire.escape/1')).toBe(false);
});
