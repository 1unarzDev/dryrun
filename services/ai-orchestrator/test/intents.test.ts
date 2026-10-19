import {it,expect} from 'vitest';
import {IntentInterpreter,inputDigest,intentRequest} from '../src/intents.js';
import type {AgentProvider} from '../src/provider.js';
const binding={sessionID:'s',revision:0,eventSequence:0,contextDigest:'x',householdRevision:0,homeRevision:0};
const request={contractVersion:'dryrun.ai/1',requestID:'r',synthetic:true,submission:{id:'input',text:'Use water for drinking.',inputDigest:inputDigest('Use water for drinking.'),binding},context:{people:[{id:'person',selected:true}],rooms:[{id:'kitchen',use:'kitchen'}],portals:[],equipment:[],contacts:[],supplies:[],choices:[]}};
function provider(output:unknown):AgentProvider{return {async turn(){return {steps:[],text:JSON.stringify(output),calls:[],usage:{}}}};}
it('binds the interpretation to actual submitted input without accepting caller arithmetic',async()=>{
 const result=await new IntentInterpreter(provider({status:'proposed',commands:[{kind:'useStoredWater',value:'essential'}]})).interpret(request);
 expect(result.submittedInputID).toBe('input');expect(result.inputDigest).toBe(request.submission.inputDigest);expect(result.binding).toEqual(binding);
 expect(()=>intentRequest.parse({...request,submission:{...request.submission,text:'   '}})).toThrow();
 await expect(new IntentInterpreter(provider({status:'unsupported'})).interpret({...request,submission:{...request.submission,inputDigest:'0'}})).rejects.toThrow('input_identity');
});
it.each([{status:'proposed',commands:[{kind:'advance',minute:30}]},{status:'proposed',commands:[{kind:'moveTo',target:'person',value:'invented'}]},{status:'proposed',commands:[{kind:'useStoredWater',value:'essential',remaining:50}]}])('rejects forbidden effects/IDs/patches with bounded repair',async output=>{
 const runner=new IntentInterpreter(provider(output));await expect(runner.interpret(request)).rejects.toThrow('invalid_intent_output');expect(runner.calls).toBe(2);
});
it('returns a clarification without an action and respects cancellation',async()=>{
 const clarified=await new IntentInterpreter(provider({status:'needsClarification',question:'Which person?'})).interpret(request);expect('commands' in clarified).toBe(false);
 const abort=new AbortController();abort.abort();const p:AgentProvider={async turn(input){input.signal.throwIfAborted();throw new Error('unexpected')}};
 await expect(new IntentInterpreter(p).interpret(request,abort.signal)).rejects.toThrow();
});

it('discards a late interpretation after cancellation even if an adapter returns it',async()=>{
 const abort=new AbortController();const p:AgentProvider={async turn(){abort.abort();return {steps:[],calls:[],usage:{},text:JSON.stringify({status:'unsupported'})}}};
 await expect(new IntentInterpreter(p).interpret(request,abort.signal)).rejects.toThrow();
});
