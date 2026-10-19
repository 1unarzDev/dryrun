import {afterEach,describe,expect,it,vi} from 'vitest';
const sdk=vi.hoisted(()=>({create:vi.fn()}));
vi.mock('@google/genai',()=>({GoogleGenAI:class {interactions={create:sdk.create};}}));
import {GeminiProvider,SpendBudget,type AgentProvider} from '../src/provider.js';
const input=(signal:AbortSignal):Parameters<AgentProvider['turn']>[0]=>({history:[],instruction:'synthetic test',tools:[],signal});
const reply={steps:[],output_text:'{}',usage:{total_input_tokens:10,total_output_tokens:2}};
afterEach(()=>{vi.unstubAllEnvs();vi.useRealTimers();sdk.create.mockReset();});
describe('provider queue deadlines and cancellation',()=>{
 it('cancels a queued request promptly without allowing a successor past the active call',async()=>{
  vi.stubEnv('DRYRUN_CALL_SPACING_MS','0');
  let resolveActive!:(value:typeof reply)=>void;
  let markReady!:()=>void;const ready=new Promise<void>(resolve=>{markReady=resolve});
  sdk.create.mockImplementationOnce(()=>{markReady();return new Promise(resolve=>{resolveActive=resolve});}).mockResolvedValue(reply);
  const budget=new SpendBudget(1),provider=new GeminiProvider('synthetic-test-secret','gemini-3.1-flash-lite',budget);
  const first=provider.turn(input(new AbortController().signal));await ready;
  const abort=new AbortController();const second=provider.turn(input(abort.signal));
  const rejected=expect(second).rejects.toThrow('provider_timeout_or_cancelled');abort.abort();await rejected;
  const third=provider.turn(input(new AbortController().signal));
  await Promise.resolve();await Promise.resolve();
  expect(sdk.create).toHaveBeenCalledTimes(1);expect(budget.calls).toBe(1);
  resolveActive(reply);await first;await third;
  expect(sdk.create).toHaveBeenCalledTimes(2);expect(budget.calls).toBe(2);
 });
 it('clears the spacing timer and abort listener without spending on a cancelled wait',async()=>{
  vi.useFakeTimers();vi.stubEnv('DRYRUN_CALL_SPACING_MS','5000');sdk.create.mockResolvedValue(reply);
  const budget=new SpendBudget(1),provider=new GeminiProvider('synthetic-test-secret','gemini-3.1-flash-lite',budget);
  await provider.turn(input(new AbortController().signal));
  const abort=new AbortController(),remove=vi.spyOn(abort.signal,'removeEventListener');
  const second=provider.turn(input(abort.signal));
  await Promise.resolve();await Promise.resolve();await Promise.resolve();
  const rejected=expect(second).rejects.toThrow('provider_timeout_or_cancelled');abort.abort();await rejected;
  expect(sdk.create).toHaveBeenCalledTimes(1);expect(budget.calls).toBe(1);
  expect(remove).toHaveBeenCalled();expect(vi.getTimerCount()).toBe(0);
 });
 it('never calls the SDK or reserves spend for an already-aborted request',async()=>{
  const abort=new AbortController();abort.abort();const budget=new SpendBudget(1);
  const provider=new GeminiProvider('synthetic-test-secret','gemini-3.1-flash-lite',budget);
  await expect(provider.turn(input(abort.signal))).rejects.toThrow('provider_timeout_or_cancelled');
  expect(sdk.create).not.toHaveBeenCalled();expect(budget.calls).toBe(0);
 });
 it('rejects a late SDK reply after cancellation while retaining incurred usage accounting',async()=>{
  vi.stubEnv('DRYRUN_CALL_SPACING_MS','0');
  let release!:(value:typeof reply)=>void,started!:()=>void;
  const ready=new Promise<void>(resolve=>{started=resolve});
  sdk.create.mockImplementation(()=>{started();return new Promise(resolve=>{release=resolve});});
  const budget=new SpendBudget(1),provider=new GeminiProvider('synthetic-test-secret','gemini-3.1-flash-lite',budget);
  const abort=new AbortController(),pending=provider.turn(input(abort.signal));await ready;
  const rejected=expect(pending).rejects.toThrow('provider_timeout_or_cancelled');abort.abort();release(reply);await rejected;
  expect(budget.calls).toBe(1);expect(budget.spentUSD).toBeCloseTo((10*0.25+2*1.5)/1000000,10);
 });

});
