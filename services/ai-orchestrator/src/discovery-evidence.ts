/** A source binding is not entailment. Keep the two factual display fields extractive:
 * the provider can reason about usefulness separately, but cannot invent a facility or
 * paraphrase an unsupported service merely by citing an otherwise genuine passage. */
export function normalizeSourceText(value:string):string {
 return value.normalize('NFKC').replace(/^L\d+:\s*/gm,'').replace(/[*_`]/g,'').replace(/[‘’]/g,"'").replace(/[‐‑‒–—]/g,'-').replace(/[“”]/g,'"').replace(/\s+/g,' ').trim();
}
function assertServiceDescription(option:{name:string;documentedService:string}):void {
 // An organization can contain a service/category word in its name without offering
 // the activity the brief needs. "Pharmacy" in "Public Health Pharmacy Clinic"
 // is identity evidence, not evidence of general prescription dispensing.
 // Keep independent contact/hour excerpts usable as qualified planning leads.
 const words=(value:string)=>normalizeSourceText(value).toLocaleLowerCase('en-US').match(/[\p{L}\p{N}]+/gu)??[];
 const identity=new Set(words(option.name)),service=words(option.documentedService);
 if(service.length&&service.every(word=>identity.has(word)))throw new Error('unsupported_research_service_description');

}
export function assertExtractiveOption(option:{name:string;documentedService:string},passages:readonly string[]):void {
 const text=passages.map(normalizeSourceText);
 assertServiceDescription(option);
 for(const [field,value] of [['name',option.name],['service',option.documentedService]] as const){
  const quote=normalizeSourceText(value);
  // Do not join passages: a new statement assembled across unrelated excerpts is not a quote.
  if(!quote||!text.some(p=>p.includes(quote)))throw new Error(`unsupported_research_${field}`);
 }
}

/** A service quote from another page cannot be attributed to this facility merely
 * because both pages were returned by the same search. Identity and service must
 * be supported together by at least one actual source. */
export function assertSourceBoundOption(option:{name:string;documentedService:string},passages:readonly {sourceID:string;quote:string;scopeID?:string}[]):void {
 assertServiceDescription(option);
 const groups=new Map<string,string[]>();
 for(const p of passages){
  // A page can be a directory: never borrow another heading/record's service.
  const key=JSON.stringify([p.sourceID,p.scopeID??'legacy-page']);
  groups.set(key,[...(groups.get(key)??[]),p.quote]);
 }
 for(const quotes of groups.values()){
  try{assertExtractiveOption(option,quotes);return;}catch{/* Try another complete source binding. */}
 }
 throw new Error('unsupported_research_identity_service_binding');
}

/** A retrieval date, service period, copyright year or another directory record's
 * date cannot become this option's publication/update date. Keep useful identity
 * and service evidence even when the proposed date is unsupported. The public
 * contract intentionally permits verbatim localized dates rather than forcing
 * an inferred ISO conversion. */
export function supportedPublicationDate(option:{name:string;documentedService:string;publishedOrUpdatedAt:string|null},passages:readonly {sourceID:string;quote:string;scopeID?:string}[]):string|null {
 if(option.publishedOrUpdatedAt===null)return null;
 const date=normalizeSourceText(option.publishedOrUpdatedAt);
 if(!date)return null;
 const groups=new Map<string,string[]>();
 for(const p of passages){
  const key=JSON.stringify([p.sourceID,p.scopeID??'legacy-page']);
  groups.set(key,[...(groups.get(key)??[]),p.quote]);
 }
 for(const quotes of groups.values()){
  try{assertExtractiveOption(option,quotes);}catch{continue;}
  for(const quote of quotes){
   const text=normalizeSourceText(quote);
   // Dates must be copied exactly from an explicit publication/review label.
   // Do not match a date embedded inside another date or a longer numeric value.
   const labels=text.matchAll(/\b(?:published|last updated|updated|last reviewed|reviewed|publication date)\b(?:\s+(?:on|at))?\s*[:\-]?\s*/gi);
   for(const label of labels){
    const after=text.slice(label.index!+label[0].length);
    if(after.startsWith(date)&&!/[\p{L}\p{N}\-/.]/u.test(after[date.length]??''))return option.publishedOrUpdatedAt;
   }
  }
 }
 return null;
}

/** Preserve heading-delimited directory records before whitespace normalization.
 * For unstructured pages use one page scope; this is extractive attribution, not
 * proof that a directory's claims are current or that a service suits a person. */
export function researchPassages(sources:readonly {id:string;content:string}[],capabilities:readonly string[]) {
 const terms:Record<string,string[]>={cooling:['cool','heat','air condition'],warming:['warm','cold','heated'],drinkingWater:['water','bottle','distribution'],foodAssistance:['food','meal','pantry'],pharmacy:['pharmac','prescription','compound'],equipmentSupport:['equipment','medical','power'],stepFree:['accessib','step-free','wheelchair'],delivery:['deliver'],extinguisher:['extinguisher'],shelter:['shelter'],hardware:['hardware','supplies'],warmClothing:['cloth','coat','blanket']};
 const words=[...new Set(capabilities.flatMap(c=>terms[c]??[c.toLowerCase()]))];
 return sources.flatMap(source=>{
  const raw=source.content.replace(/^L\d+: ?/gm,'');
  const blocks=raw.split(/(?=^#{1,6}\s+\S)/m).filter(s=>s.trim());
  const hasHeadings=blocks.length>1;
  const chunks=blocks.flatMap((block,scope)=>{
   const text=normalizeSourceText(block);
   // Short directory records stay intact, including the name and service sentence.
   // Long pages retain bounded windows with a shared heading scope, never across records.
   const quotes=text.length<=1500?[text]:text.match(/.{1,700}(?:\s|$)/g)??[];
   return quotes.map(quote=>({quote:quote.trim(),scopeID:`${source.id}.scope-${hasHeadings?scope+1:1}`}));
  });
  const frequency=words.map(word=>chunks.filter(c=>c.quote.toLowerCase().includes(word)).length);
  const ranked=chunks.map((p,index)=>({...p,id:`${source.id}.passage-${index+1}`,sourceID:source.id,index,rank:words.reduce((score,word,i)=>score+(p.quote.toLowerCase().includes(word)?1+1/(frequency[i]||1):0),0)}));
  // Keep identity and several useful records; rare requested services break keyword ties.
  const identity=hasHeadings?ranked.find(p=>/^#{1,6}\s/.test(p.quote))??ranked[0]:ranked[0];
  const selected=[identity,...ranked.filter(p=>p!==identity).sort((a,b)=>b.rank-a.rank||a.index-b.index).slice(0,3)];
  return selected.filter((p):p is NonNullable<typeof p>=>!!p).sort((a,b)=>a.index-b.index).map(({rank,index,...p})=>p);
 }).slice(0,24);
}
