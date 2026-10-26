import {readFileSync} from 'node:fs';
import {it,expect} from 'vitest';
import {hazardExperience} from '../src/contracts.js';
const retained=JSON.parse(readFileSync(new URL('../../../fixtures/ai/corrective-live-v1.json',import.meta.url),'utf8'));
const legacy=retained.scenarios.find((row:{hazard:string})=>row.hazard==='heat-grid-strain').experience;
it('retains the actual v1 heat receipt and rejects mixing v2 fields into it',()=>{
 expect(hazardExperience.parse(legacy)).toEqual(legacy);
 expect(hazardExperience.safeParse({...legacy,shadedRoomIDs:['sp-living']}).success).toBe(false);
 expect(hazardExperience.safeParse({...legacy,mechanicsVersion:'dryrun.hazard-mechanics/99'}).success).toBe(false);
});
it('round trips qualified room-level v2 heat without accepting inverted ranges',()=>{
 const room={lowerC:28,upperC:30,model:'illustrative-room-range/2',assumption:'Synthetic room range; not measured or a medical threshold'};
 const current={...legacy,mechanicsVersion:'dryrun.hazard-mechanics/2',temperature:room,roomTemperatures:{'sp-bed1':room},shadedRoomIDs:['sp-bed1'],conditioningService:'degraded'};
 expect(hazardExperience.parse(JSON.parse(JSON.stringify(current)))).toEqual(current);
 expect(hazardExperience.safeParse({...current,roomTemperatures:{'sp-bed1':{...room,lowerC:31}}}).success).toBe(false);
});
