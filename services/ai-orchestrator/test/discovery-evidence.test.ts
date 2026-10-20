import {expect,it} from 'vitest';
import {assertExtractiveOption,assertSourceBoundOption,researchPassages,supportedPublicationDate} from '../src/discovery-evidence.js';
import {readFile} from 'node:fs/promises';

it('keeps only explicitly published dates bound to the facility/service scope',()=>{
 const option={name:'Civic Center',documentedService:'Seasonal cooling',publishedOrUpdatedAt:'2026-09-18'};
 const identity={sourceID:'directory',scopeID:'center',quote:'Civic Center. Seasonal cooling.'};
 const date={...identity,quote:'Last updated: 2026-09-18'};
 expect(supportedPublicationDate(option,[identity,date])).toBe('2026-09-18');
 for(const quote of ['Retrieved: 2026-09-18','Copyright 2026-09-18','Seasonal service ends 2026-09-18','Last updated: 2026-09-180'])expect(supportedPublicationDate(option,[identity,{...date,quote}])).toBeNull();
 expect(supportedPublicationDate(option,[identity,{...date,scopeID:'other-facility'}])).toBeNull();
 expect(supportedPublicationDate(option,[identity,{...date,sourceID:'other-page'}])).toBeNull();
 expect(supportedPublicationDate({...option,publishedOrUpdatedAt:'2026'},[identity,date])).toBeNull();
 expect(supportedPublicationDate({...option,publishedOrUpdatedAt:null},[identity,date])).toBeNull();
 expect(supportedPublicationDate({...option,publishedOrUpdatedAt:'September 18, 2026'},[identity,{...date,quote:'Published on September 18, 2026 (program page)'}])).toBe('September 18, 2026');
});

it('does not promote dates invented in the actual quota-interrupted Albuquerque answer',async()=>{
 const fixture=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-search-quota-live.json','utf8'));
 const passages=researchPassages(fixture.result.attribution.evidence,['pharmacy']);
 expect(fixture.result.attribution.answer).toContain('2023');
 for(const publishedOrUpdatedAt of ['2023-02-15','2023-12-01'])expect(supportedPublicationDate({name:'UNM',documentedService:'Pharmacy',publishedOrUpdatedAt},passages)).toBeNull();
});

it('rejects invented names and services even when a real source ID is supplied',()=>{
 const passages=['Civic Center. Published seasonal heat relief; check activation before travel.'];
 expect(()=>assertExtractiveOption({name:'Civic Center',documentedService:'Published seasonal heat relief'},passages)).not.toThrow();
 expect(()=>assertExtractiveOption({name:'Library Cooling',documentedService:'Published seasonal heat relief'},passages)).toThrow('unsupported_research_name');
 expect(()=>assertExtractiveOption({name:'Civic Center',documentedService:'Step-free access, water and Wi-Fi'},passages)).toThrow('unsupported_research_service');
 expect(()=>assertExtractiveOption({name:'Civic Center',documentedService:'Published seasonal heat relief guarantees activation'},passages)).toThrow('unsupported_research_service');
});
it('permits display-only whitespace/emphasis normalization without constructing new claims across passages',()=>{
 expect(()=>assertExtractiveOption({name:'Civic Center',documentedService:'Published seasonal heat relief'},['L4: **Civic Center**\nL5: Published seasonal\nL6: heat relief'])).not.toThrow();
 expect(()=>assertExtractiveOption({name:'Civic Center',documentedService:'heat relief guarantees access'},['Civic Center offers heat relief','guarantees access'])).toThrow('unsupported_research_service');
});
it('keeps page identity and relevant evidence below long navigation within the extraction budget',()=>{
 const content='L0: Civic Center\n'+('Navigation activities registration calendar. '.repeat(160))+'\nL200: During heat advisories the center offers cooling during business hours.\nL201: Confirm current activation.';
 const passages=researchPassages([{id:'source-1',content}],['cooling']);
 expect(passages).toHaveLength(4);expect(passages[0]?.quote).toContain('Civic Center');
 expect(passages.some(p=>p.quote.includes('offers cooling'))).toBe(true);
 expect(passages.every(p=>p.quote.length<=1500)).toBe(true);
});
it('rejects the actual source-bound but unsupported names from live20B Denver extraction',async()=>{
 const fixture=JSON.parse(await readFile('../../fixtures/ai/groq-extraction-rejected-live.json','utf8'));
 const output=JSON.parse(fixture.response.choices[0].message.content);
 expect(output.options).toHaveLength(2);
 for(const option of output.options){
  const selected=option.support.map((id:string)=>fixture.passages.find((p:any)=>p.id===id)?.quote);
  expect(selected.every(Boolean)).toBe(true); // Genuine source IDs still do not establish the claim.
  expect(()=>assertExtractiveOption(option,selected)).toThrow('unsupported_research_name');
 }
});

it('rejects transferring another facility service while allowing identity and service passages on one page',()=>{
 const option={name:'Civic Center',documentedService:'Seasonal heat relief during staffed hours'};
 const identity={sourceID:'center-page',quote:'Civic Center. Local community activities.'};
 const other={sourceID:'other-library',quote:'Library program: Seasonal heat relief during staffed hours'};
 expect(()=>assertSourceBoundOption(option,[identity,other])).toThrow('unsupported_research_identity_service_binding');
 expect(()=>assertSourceBoundOption(option,[identity,{...other,sourceID:'center-page'}])).not.toThrow();
});

it('keeps actual Albuquerque facility records intact and rejects service borrowing within the same directory',async()=>{
 const {source}=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-directory.json','utf8'));
 const passages=researchPassages([source],['pharmacy','delivery','equipmentSupport','stepFree']);
 const highland=passages.find(p=>p.quote.includes('### Highland Pharmacy'));
 expect(highland?.quote).toContain('Compounding, Delivery, Drive-Up Window');
 expect(highland?.quote).not.toContain('### UNM');
 const city=passages.find(p=>p.quote.includes('### Albuquerque City Drug'));
 expect(city).toBeDefined();expect(city?.scopeID).not.toBe(highland?.scopeID);
 expect(()=>assertSourceBoundOption({name:'Albuquerque City Drug',documentedService:'Compounding, Delivery, Drive-Up Window'},passages)).toThrow('unsupported_research_identity_service_binding');
 expect(()=>assertSourceBoundOption({name:'Highland Pharmacy',documentedService:'Compounding, Delivery, Drive-Up Window'},passages)).not.toThrow();
 expect(passages.length).toBeLessThanOrEqual(4);
 expect(passages.every(p=>p.quote.length<=1500)).toBe(true);
});

it('accepts typographic hyphens in actual supported Albuquerque extraction while preserving record identity',async()=>{
 const {source}=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-directory.json','utf8'));
 const passages=researchPassages([source],['pharmacy']);
 expect(()=>assertSourceBoundOption({name:'Highland Pharmacy',documentedService:'Compounding, Delivery, Drive‑Up Window, Durable Medical Equipment'},passages)).not.toThrow();
 expect(()=>assertSourceBoundOption({name:'Albuquerque City Drug',documentedService:'Compounding, Delivery, Drive‑Up Window, Durable Medical Equipment'},passages)).toThrow();
});

it('does not treat a service word inside the facility name as evidence of that service',()=>{
 const passages=[{sourceID:'clinic',scopeID:'header',quote:'Public Health Pharmacy Clinic. Call Us 505.832.7162. Monday - Friday 9 am to 5pm.'}];
 for(const documentedService of ['Pharmacy','pharmacy','Public Health Pharmacy Clinic'])
  expect(()=>assertSourceBoundOption({name:'Public Health Pharmacy Clinic',documentedService},passages)).toThrow('unsupported_research_service_description');
 // Contact-only evidence can remain a qualified lead; the name never establishes dispensing.
 expect(()=>assertSourceBoundOption({name:'Public Health Pharmacy Clinic',documentedService:'Call Us 505.832.7162'},passages)).not.toThrow();
 expect(()=>assertSourceBoundOption({name:'Public Health Pharmacy Clinic',documentedService:'Rapid and PCR tests available'},[...passages,{sourceID:'clinic',scopeID:'header',quote:'Rapid and PCR tests available'}])).not.toThrow();
});

it('preserves the actual named AHCH prescription program without inventing a composite facility name',async()=>{
 const captured=JSON.parse(await readFile('../../fixtures/ai/groq-albuquerque-extraction-v5-live.json','utf8'));
 const source=captured.result.attribution.evidence.find((s:any)=>s.id==='source-5');
 const passages=researchPassages([source],['pharmacy']);
 const service='Our on-site pharmacy fills prescriptions from our providers at AHCH, as well as provides medication for uninsured individuals regardless of ability to pay.';
 expect(()=>assertSourceBoundOption({name:'Increasing Access to Prescriptions',documentedService:service},passages)).not.toThrow();
 expect(()=>assertSourceBoundOption({name:'Albuquerque Health Care for the Homeless Pharmacy',documentedService:service},passages)).toThrow('unsupported_research_identity_service_binding');
});
