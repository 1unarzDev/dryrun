import {describe,it,expect} from 'vitest';
import {FeatureRunner,type Role} from '../src/features.js';
import type {ProviderReply} from '../src/provider.js';
const context={household:{revision:1,people:[],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[]},tasks:[],gaps:[],allowedActionIDs:[],allowedCriterionIDs:[]};
function deferred<T>(){let resolve!:(value:T)=>void;const promise=new Promise<T>(done=>{resolve=done});return {promise,resolve};}
describe('feature cancellation boundary',()=>{
 it('does not dispatch any role for an already-cancelled operation',async()=>{
  let calls=0;const runner=new FeatureRunner({async turn(){calls++;throw new Error('should_not_dispatch')}});
  const abort=new AbortController();abort.abort();
  await expect(runner.run('preparation',context,abort.signal)).rejects.toThrow();
  await expect(runner.council(context,abort.signal)).rejects.toThrow();
  expect(calls).toBe(0);expect(runner.calls).toBe(0);
 });
 it.each(['preparation','home','stress','coverage'] as Role[])('rejects late %s output without a repair and retains reported usage',async(role)=>{
  const started=deferred<void>(),reply=deferred<ProviderReply>();
  const runner=new FeatureRunner({async turn(){started.resolve();return reply.promise}});
  const abort=new AbortController(),pending=runner.run(role,context,abort.signal);
  await started.promise;
  const rejected=expect(pending).rejects.toThrow();abort.abort();
  // An adapter may ignore AbortSignal; its result still cannot publish or trigger repair/tools.
  reply.resolve({steps:[],calls:[],text:'untrusted late content',usage:{input:7,output:2}});
  await rejected;expect(runner.calls).toBe(1);expect(runner.usage).toEqual([{input:7,output:2}]);
 });
 it('stops a cancelled council without dispatching the remaining reviewers',async()=>{
  const abort=new AbortController();let calls=0;
  const runner=new FeatureRunner({async turn(){calls++;abort.abort();return {steps:[],calls:[],text:JSON.stringify({assessments:[],question:null}),usage:{input:5}}}});
  await expect(runner.council(context,abort.signal)).rejects.toThrow();expect(calls).toBe(1);expect(runner.usage).toEqual([{input:5}]);
 });
});
