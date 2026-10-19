import {it,expect} from 'vitest';
import {practiceSource} from '../src/practice-contracts.js';
const source={contractVersion:'dryrun.practice-capture/1',sessionID:'session',initialDigest:'digest',startingRevision:0,startingEventSequence:0};
it('preserves a missing legacy anchor version and admits only published evaluator versions',()=>{
 expect(practiceSource.parse(source)).not.toHaveProperty('evaluatorVersion');
 for(const evaluatorVersion of ['dryrun.practice-anchors/1','dryrun.practice-anchors/2'])expect(practiceSource.parse({...source,evaluatorVersion}).evaluatorVersion).toBe(evaluatorVersion);
 expect(()=>practiceSource.parse({...source,evaluatorVersion:'future'})).toThrow();
});
