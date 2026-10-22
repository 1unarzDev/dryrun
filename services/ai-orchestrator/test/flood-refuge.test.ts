import {readFile} from 'node:fs/promises';
import {it,expect} from 'vitest';
import {hazardExperience,directorContext,minimizedSnapshot} from '../src/contracts.js';
import {directorProviderSchemas} from '../src/director-provider-schema.js';
import {userCommand} from '../src/user-commands.js';
const fixture=JSON.parse(await readFile('../../fixtures/ai/flood-refuge-trace.json','utf8'));
it('preserves actual versioned person-specific refuge approaches, arrivals and carried stock through the gateway contract',()=>{
 const trace=fixture.traces[0],initial=trace.initial;
 const experience=hazardExperience.parse(initial.receipt.experience);
 expect(['dryrun.hazard-mechanics/4','dryrun.hazard-mechanics/5']).toContain(experience.mechanicsVersion);
 expect(experience).toHaveProperty('refugeRoomID','sp-bed1');
 expect(experience.openGapIDs).toContain('higherRefuge.'+fixture.partialHouseholdAccess);
 expect(experience.feasibleCommands?.some(c=>c.kind==='reachHigherRefuge'&&'target'in c&&c.target===fixture.partialHouseholdAccess)).toBe(false);
 for(const branch of trace.acceptedOptions){
  const after=hazardExperience.parse(branch.result.receipt.experience);
  expect(after).toHaveProperty('refugedPersonIDs');
  expect(branch.result.session.inventory).toEqual(initial.session.inventory);
  expect(branch.action.commands.every((c:unknown)=>userCommand.safeParse(c).success)).toBe(true);
 }
 expect(trace.acceptedOptions[0].result.receipt.inventory.items[0].locationID).toBe('sp-bed1');
 expect(trace.acceptedOptions[1].result.receipt.inventory.items[0].locationID).toBe('sp-hall');
 const context=directorContext.parse({binding:trace.proposal.binding,snapshot:minimizedSnapshot(initial.receipt),experience,household:initial.householdContext,homeScene:initial.homeScene,profiles:initial.directorProfiles,learningObjectives:[]});
 const schema=JSON.stringify(directorProviderSchemas(context).output);
 expect(schema).toContain('reachHigherRefuge');expect(schema).toContain('takeSupply');
});
it('keeps refuge fields unavailable on historical mechanics contracts and rejects fabricated destination effects',()=>{
 const experience=fixture.traces[0].initial.receipt.experience;
 expect(hazardExperience.safeParse({...experience,mechanicsVersion:'dryrun.hazard-mechanics/3'}).success).toBe(false);
 expect(userCommand.safeParse({kind:'reachHigherRefuge',target:'resident',value:'sp-bed1',safety:'certified'}).success).toBe(false);
 expect(userCommand.safeParse({kind:'reachHigherRefuge',target:'resident'}).success).toBe(false);
});
