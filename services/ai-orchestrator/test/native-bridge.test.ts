import {readFileSync,readdirSync} from 'node:fs';
import {describe,expect,it} from 'vitest';
import {operationRequest,toolResult} from '../src/contracts.js';

// Written by packages/DryRunCore/Tests/DryRunCoreTests/DirectorGatewayBridgeTests.swift: exactly what the iPhone sends.
const dir=new URL('../../../fixtures/ai/native-bridge/',import.meta.url);
const files=readdirSync(dir).filter(f=>f.endsWith('.json')).sort();
const read=(f:string)=>JSON.parse(readFileSync(new URL(f,dir),'utf8'));

describe('native Swift bridge matches the strict gateway contract',()=>{
 it('has both request and every tool fixture',()=>{
  expect(files.filter(f=>f.startsWith('director-request-')).length).toBeGreaterThanOrEqual(2);
  for(const tool of ['evaluateCandidateAction','inspectScene','queryRoutes','evaluateResources','inspectDependencies','runCounterfactual','validateSuggestedActions'])expect(files).toContain(`tool-result-${tool}.json`);
 });
 it.each(files.filter(f=>f.startsWith('director-request-')))('%s parses as an operation request',f=>{
  const parsed=operationRequest.parse(read(f));
  expect(parsed.synthetic).toBe(true);
  expect(parsed.context.household?.revision).toBe(parsed.context.binding.householdRevision);
 });
 it.each(files.filter(f=>f.startsWith('tool-result-')))('%s parses as a tool result',f=>{
  const parsed=toolResult.parse(read(f));
  const name=f.slice('tool-result-'.length,-'.json'.length);
  if(name==='evaluateCandidateAction'){expect(parsed.preview).toBeDefined();expect(parsed.observation).toBeUndefined();}
  else if(name==='validateSuggestedActions'){expect(parsed.suggestionValidation?.length).toBeGreaterThan(0);expect(parsed.observation).toBeUndefined();expect(parsed.preview).toBeUndefined();}
  else {expect(parsed.observation?.kind).toBe(name);expect(parsed.preview).toBeUndefined();}
 });
});
