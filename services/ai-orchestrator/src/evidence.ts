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
/** Equality with an unreviewed directory field is not verification of a facility capability. */
export function validateOfficialCapability(claim:{resourceID:string;field:string;value:unknown},records:Record<string,unknown>[],at=new Date()){
 const r=records.find(r=>r.id===claim.resourceID);
 if(!Number.isFinite(at.getTime())||!r||r.reviewState!=='reviewed'||r.capabilitiesVerified!==true||!Array.isArray(r.sourceIDs)||!r.sourceIDs.length||!r.sourceIDs.every(id=>typeof id==='string'&&id.length>0)||!Object.hasOwn(r,claim.field)||claim.value===null||claim.value==='unknown'||r[claim.field]!==claim.value)return false;
 if(typeof r.checkedAt!=='string'||!Number.isFinite(Date.parse(r.checkedAt))||Date.parse(r.checkedAt)>at.getTime())return false;
 if(r.expiresAt!==undefined&&(typeof r.expiresAt!=='string'||!Number.isFinite(Date.parse(r.expiresAt))||Date.parse(r.expiresAt)<=at.getTime()))return false;
 // Activation is time-sensitive; an undated/no-expiry record cannot establish it now.
 return claim.field!=='activation'||typeof r.expiresAt==='string';
}
/** Renderable explanation uses bounded record fields, never free-form model capability claims. */
export function officialResourceReason(record:Record<string,unknown>,task:{actionID:string;criterionID:string}):string {
 const serviceLabels:Record<string,string>={emergencyManagement:'emergency-management',publicHealth:'public-health',waterProvider:'water-provider',electricUtility:'electric-utility',transportation:'transportation',assistanceLine:'assistance-line',assistanceRegistry:'assistance-registry',disasterAssistance:'disaster-assistance',warmingCenter:'warming-center',coolingCenter:'cooling-center',shelter:'shelter',alertEnrollment:'alert-enrollment'};
 const taskLabels:Record<string,string>={'prep.alerts':'official alert-enrollment preparation','prep.waterUtility':'water-utility contact plan','prep.water':'drinking-water preparation','prep.food':'food preparation','prep.flashlight':'flashlight preparation','prep.firstAid':'first-aid preparation','prep.nearMeetup':'nearby meeting-place plan','prep.backupMeetup':'backup meeting-place plan','prep.medicalBackup':'documented equipment-backup plan'};
 const criterionLabels:Record<string,string>={water:'drinking-water preparation',food:'food preparation',essentials:'essential-supplies preparation',contact:'communication plan',meetups:'meeting-place plan',device:'documented equipment-backup plan',assistance:'assistance plan',care:'recorded care-supply plan',pets:'pet preparation',shelter:'shelter planning',escape:'escape planning',alarms:'alarm preparation',review:'plan review'};
 const service=typeof record.serviceType==='string'?serviceLabels[record.serviceType]:undefined;
 const need=taskLabels[task.actionID]??criterionLabels[task.criterionID]??'preparation task';
 const checked=typeof record.checkedAt==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(record.checkedAt)&&Number.isFinite(Date.parse(record.checkedAt))?` Record last checked ${record.checkedAt}.`:'';
 return `This official ${service??'service'} listing may help you investigate your ${need}. Its current service, activation, access and suitability need confirmation; this is not a confirmed destination.${checked}`;
}
export {record as publicResourceSchema};
