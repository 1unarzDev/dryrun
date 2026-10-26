import {describe,it,expect} from 'vitest';
import {z} from 'zod';
import {command,directorToolSchemas} from '../src/contracts.js';
import {providerSchema} from '../src/provider.js';
describe('provider schema preserves typed command alternatives',()=>{
 it('keeps discriminated union branches and each required command field',()=>{
  const schema:any=providerSchema(z.toJSONSchema(command));
  expect(schema.anyOf).toHaveLength(7);
  const start=schema.anyOf.find((s:any)=>s.properties.kind.enum.includes('startIncident'));
  expect(start.required).toEqual(expect.arrayContaining(['kind','target','hazard','minute']));
  expect(start.properties.hazard.enum).toContain('homeFire');
  const wait=schema.anyOf.find((s:any)=>s.properties.kind.enum.includes('waitUntil'));
  expect(wait.required).toEqual(expect.arrayContaining(['target','durationMinutes']));
 });
 it('does not turn batch preview items into an unconstrained or numeric array',()=>{
  const schema:any=providerSchema(z.toJSONSchema(directorToolSchemas.evaluateCandidateAction));
  expect(schema.properties.commands.type).toBe('array');
  expect(schema.properties.commands.items.anyOf.every((s:any)=>s.type==='object')).toBe(true);
  expect(()=>directorToolSchemas.evaluateCandidateAction.parse({commands:[1,2,3]})).toThrow();
 });
});
