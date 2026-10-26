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

 it('returns promptly when the transport ignores cancellation and accounts a later reply only once',async()=>{
  vi.stubEnv('DRYRUN_CALL_SPACING_MS','0');
  let release!:(value:typeof reply)=>void,started!:()=>void;
  const ready=new Promise<void>(resolve=>{started=resolve});
  sdk.create.mockImplementation((_body,options)=>{started();expect(options.retries).toEqual({strategy:'none'});return new Promise(resolve=>{release=resolve});});
  const budget=new SpendBudget(1),provider=new GeminiProvider('synthetic-test-secret','gemini-3.1-flash-lite',budget);
  const abort=new AbortController(),pending=provider.turn(input(abort.signal));await ready;
  abort.abort();
  try {
   await expect(Promise.race([pending,new Promise((_,reject)=>setTimeout(()=>reject(new Error('deadline_not_enforced')),25))])).rejects.toThrow('provider_timeout_or_cancelled');
  } finally {release(reply);}
  await Promise.resolve();await Promise.resolve();
  expect(budget.calls).toBe(1);expect(budget.spentUSD).toBeCloseTo((10*0.25+2*1.5)/1000000,10);
 });

});

it('distinguishes provider overload from validation and performs no hidden retries',async()=>{
 vi.stubEnv('DRYRUN_CALL_SPACING_MS','0');sdk.create.mockRejectedValue({status:503});
 const provider=new GeminiProvider('synthetic-test-secret','gemini-3.1-flash-lite',new SpendBudget(1));
 await expect(provider.turn(input(new AbortController().signal))).rejects.toThrow('provider_overloaded');
 expect(sdk.create).toHaveBeenCalledTimes(1);
 expect(sdk.create.mock.calls[0]?.[1]?.retries).toEqual({strategy:'none'});
});

it('allows opt-in legacy research without downgrading the director or sending Gemini 3 thinking controls',async()=>{
 vi.stubEnv('DRYRUN_CALL_SPACING_MS','0');sdk.create.mockResolvedValue(reply);
 expect(()=>new GeminiProvider('synthetic','gemini-2.5-flash')).toThrow('unsupported_model');
 expect(()=>new GeminiProvider('synthetic','gemini-3.1-flash-lite',new SpendBudget(1),{home:'gemini-2.5-flash'})).toThrow('unsupported_model');
 const budget=new SpendBudget(1),provider=new GeminiProvider('synthetic','gemini-3.1-flash-lite',budget,{research:'gemini-2.5-flash'});
 await provider.turn({...input(new AbortController().signal),modelRole:'research',tools:[{type:'google_search'},{type:'url_context'}]});
 expect(sdk.create.mock.calls[0]?.[0]).toMatchObject({model:'gemini-2.5-flash',store:false,tools:[{type:'google_search'},{type:'url_context'}]});
 expect(sdk.create.mock.calls[0]?.[0]?.generation_config.thinking_level).toBeUndefined();
 expect(budget.spentUSD).toBeCloseTo((10*0.30+2*2.50)/1000000,10);
 await provider.turn(input(new AbortController().signal));
 expect(sdk.create.mock.calls[1]?.[0]).toMatchObject({model:'gemini-3.1-flash-lite',generation_config:{thinking_level:'high'}});
});

it.each([[400,'provider_request_rejected'],[403,'provider_access_denied'],[404,'provider_model_unavailable'],[429,'provider_rate_limited']] as const)('reports HTTP %s without conflating quota, eligibility or request compatibility',async(status,reason)=>{
 vi.stubEnv('DRYRUN_CALL_SPACING_MS','0');sdk.create.mockRejectedValue({status,message:'sensitive provider diagnostic omitted'});
 await expect(new GeminiProvider('synthetic').turn(input(new AbortController().signal))).rejects.toThrow(reason);
 expect(sdk.create).toHaveBeenCalledTimes(1);
});

it('preserves quota retry metadata, redacts private diagnostics, and prevents queued callers probing an exhausted model',async()=>{
 vi.useFakeTimers();vi.stubEnv('DRYRUN_CALL_SPACING_MS','0');
 sdk.create.mockRejectedValueOnce({status:429,headers:new Headers({'retry-after':'90'}),error:{status:'RESOURCE_EXHAUSTED',message:'private medication echoed',details:[{'@type':'type.googleapis.com/google.rpc.RetryInfo',retryDelay:'120s'},{'@type':'type.googleapis.com/google.rpc.QuotaFailure',violations:[{quotaId:'GenerateRequestsPerDayPerProjectPerModel-FreeTier'}]}]}}).mockResolvedValue(reply);
 const provider=new GeminiProvider('synthetic','gemini-3.1-flash-lite',new SpendBudget(1),{research:'gemini-3.8-flash'}),signal=new AbortController().signal;
 let observed:unknown;try{await provider.turn(input(signal));}catch(error){observed=error;}
 expect(observed).toMatchObject({kind:'quota_exhausted',provider:'gemini',retryAfterMs:120000,diagnostic:'RESOURCE_EXHAUSTED'});
 expect(JSON.stringify(observed)).not.toContain('medication');
 await expect(provider.turn(input(signal))).rejects.toMatchObject({kind:'rate_limit',diagnostic:'CIRCUIT_OPEN'});expect(sdk.create).toHaveBeenCalledTimes(1);
 // An exhausted model does not disable an independently configured model.
 await provider.turn({...input(signal),modelRole:'research'});expect(sdk.create).toHaveBeenCalledTimes(2);
 await vi.advanceTimersByTimeAsync(121100);await provider.turn(input(signal));expect(sdk.create).toHaveBeenCalledTimes(3);
});
