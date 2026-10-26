import {readFile} from 'node:fs/promises';
import {it,expect} from 'vitest';
import {directorContext,minimizedAssistance} from '../src/contracts.js';
import {compactPrivateText} from '../src/provider-fallback.js';
import {groqDirectorInstruction} from '../src/groq-director.js';

const fixture=JSON.parse(await readFile('../../fixtures/ai/current-assistance-context.json','utf8'));

it('keeps the current helper separate from the frozen household across both provider routes',()=>{
 expect(fixture.liveModelCalls).toBe(0);
 expect(fixture.cases).toHaveLength(6);
 for(const row of fixture.cases){
  const context=directorContext.parse(row.context);
  expect(context.assistance).toEqual(minimizedAssistance(row.receipt));
  expect(JSON.parse(compactPrivateText(JSON.stringify(context))).assistance).toEqual(context.assistance);
  for(const sent of row.providerInputs)expect(sent.assistance).toEqual(context.assistance);
  const current=context.assistance!.find(a=>a.personID==='p-oak-3')!;
  expect(context.household!.people.find(p=>p.id==='p-oak-3')!.helperPersonID).toBe(row.recordedHelperID);
  if(row.name!=='approach-blocked'){
   expect(current.helperID).toBe('p-oak-2');expect(current.helperID).not.toBe(row.recordedHelperID);
   expect(current.reachStatus).toBe('reachable');
  }
  if(row.name==='approach-reachable-exit-still-blocked')expect(context.experience!.feasibleCommands!.some(c=>c.kind==='accompanyEscape')).toBe(false);
  if(row.name==='reassigned-supported-escape'){
   expect(row.appliedReceipt.experience.escapeHelperByPersonID['p-oak-3']).toBe(current.helperID);
   expect(row.appliedReceipt.experience.outsidePersonIDs).toContain(current.helperID);
   expect(row.appliedSession.initial).toEqual(row.session.initial);
  }
 }
});

it('minimizes assistance without leaking local route geometry or arbitrary metadata',()=>{
 const actual=fixture.cases[0].receipt.assistance;
 const injected=actual.map((a:any)=>({...a,phone:'private',route:{spaceSequence:['private-room']},annotation:'private'}));
 expect(minimizedAssistance({assistance:injected})).toEqual(fixture.cases[0].context.assistance);
 expect(minimizedAssistance({})).toBeUndefined();expect(minimizedAssistance({assistance:[]})).toEqual([]);
 expect(()=>minimizedAssistance({assistance:[{...actual[0],reachStatus:'alreadyCarried'}]})).toThrow();
 expect(()=>directorContext.parse({...fixture.cases[0].context,assistance:injected})).toThrow();
});

it('keeps current-assignment and actual-completion distinctions in compact Groq instructions',()=>{
 const instruction=groqDirectorInstruction('DryRun RehearsalDirector test');
 expect(instruction).toContain('director/28');expect(instruction).toContain('context.assistance');
 expect(instruction).toContain('frozen recorded assignment');expect(instruction).toContain('Reachable is an approach only');
 expect(instruction).toContain('escapeHelperByPersonID');
});
