import {readFile} from 'node:fs/promises';
import {z} from 'zod';
const record=z.object({id:z.string(),regionID:z.string(),kind:z.string(),name:z.string(),sourceIDs:z.array(z.string()).default([])}).passthrough();
/** Only independently shipped public records. No URL/network input, no private cache. */
export class PublicEvidenceTools {
 constructor(private records:Record<string,unknown>[],private sources:Record<string,unknown>[]){ }
 static async bundled(root:string){const pack=JSON.parse(await readFile(root+'/content/regions/tx-25-counties.json','utf8'));const sources=JSON.parse(await readFile(root+'/content/sources/sources.json','utf8'));return new PublicEvidenceTools(pack.resources??[],sources.sources??[]);}
 find_official_resources(regionID:string,serviceType:string):Record<string,unknown>[]{if(!/^[a-zA-Z0-9-]{2,32}$/.test(regionID)||serviceType.length>60)throw new Error('invalid_query');return this.records.filter(r=>Array.isArray(r.regionIDs)&&r.regionIDs.includes(regionID)&&(serviceType==='all'||r.serviceType===serviceType)).slice(0,10).map(r=>({...r,reviewState:'needsReview',activation:'unknown',capabilitiesVerified:false}));}
 read_resource_evidence(resourceID:string){const r=this.records.find(r=>r.id===resourceID);if(!r)throw new Error('unknown_resource');return {...r,reviewState:'needsReview',activation:'unknown',capabilitiesVerified:false};}
 get_preparation_guidance(sourceIDs:string[]){if(sourceIDs.length>8)throw new Error('budget');return sourceIDs.map(id=>{const r=this.sources.find(s=>s.id===id);if(!r)throw new Error('unknown_source');return r;});}
}
export function validateOfficialCapability(claim:{resourceID:string;field:string;value:unknown},records:Record<string,unknown>[]){const r=records.find(r=>r.id===claim.resourceID);return !!r&&Object.hasOwn(r,claim.field)&&r[claim.field]===claim.value;}
export {record as publicResourceSchema};
