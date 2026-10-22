/** Deterministic host checks that make fallback-served (Gemini/Groq) feature answers as safe as Codex-served ones.
 * Authored from cleared reviewer reports only (2026-10-22): report-v7-debrief-resources-director-six-run-review,
 * report-resources6-two-tool-turns-en-es-review, report-groq-compact-debrief-restart-review and
 * report-codex-deadline-restart-gemini-debrief-director-review. Every check throws an allowlisted machine code; the
 * feature loop turns it into one bounded repair and then an honest provider_validation_failure. */

type ReceiptEvent={id:string;severity:string;title?:string|undefined};
type Receipt={events:readonly ReceiptEvent[]};
type Equipment={id:string;purpose?:string|undefined;requiresColdStorage?:boolean|undefined;powerRequired:boolean;storageInstructions?:string|undefined};
type Person={id:string;needs:readonly string[];essentialMedication?:string|undefined;recordedConditions?:string|undefined;communicationInstructions?:string|undefined};

/** A receipt consequence the debrief must name: a critical resource running out, or an essential device or
 * medication whose continuity was lost or left unknown. Events of one device (or one resource) form one group; naming
 * any event of the group covers it. */
export type MustAddress={key:string;kind:'depletion'|'deviceContinuity';eventIDs:string[]};
const deviceEvent=/^evt\.[a-z0-9-]+\.svc\.device\.(.+)\.(unavailable|unknown)$/;
const depletionEvent=/^evt\.[a-z0-9-]+\.res\.([a-z0-9-]+)-depleted(?:\.(.+))?$/;
export function debriefMustAddress(receipt:Receipt|undefined):MustAddress[]{
 const groups=new Map<string,MustAddress>();
 for(const event of receipt?.events??[]){
  const device=event.id.match(deviceEvent);
  const depleted=event.severity==='critical'?event.id.match(depletionEvent):null;
  const key=device?'device:'+device[1]:depleted?'resource:'+depleted[1]+(depleted[2]?'.'+depleted[2]:''):undefined;
  if(!key)continue;
  const group=groups.get(key)??{key,kind:device?'deviceContinuity' as const:'depletion' as const,eventIDs:[]};
  group.eventIDs.push(event.id);groups.set(key,group);
 }
 return [...groups.values()];
}
/** addressedEventIDs must be receipt events and cover every mustAddress group. */
export function requireDebriefCoverage(addressed:readonly string[]|undefined,mustAddress:readonly MustAddress[],receipt:Receipt|undefined){
 const known=new Set((receipt?.events??[]).map(e=>e.id));
 if((addressed??[]).some(id=>!known.has(id)))throw new Error('unknown_event');
 const covered=new Set(addressed??[]);
 if(mustAddress.some(group=>!group.eventIDs.some(id=>covered.has(id))))throw new Error('unaddressed_critical_event');
}

/** Refrigerated medication that needs no electricity: the next step is the pharmacist or manufacturer, never a power,
 * backup or cooler plan (Groq lake debriefs suggested backup power and a powered cooler for it). */
const coldWorkaround=/\b(?:coolers?|ice(?:\s+packs?)?|ice\s*box|refrigerators?|fridges?|freezers?|generators?|backup\s+power|power\s+(?:station|bank|backup)|batter(?:y|ies)|keep\s+(?:it|them|the\s+\w+)\s+(?:cold|cool)|another\s+household'?s?\s+(?:fridge|refrigerator))\b/i;
const professionalPointer=/\b(?:pharmacists?|pharmacy|manufacturer'?s?)\b/i;
export function rejectColdStorageWorkaround(texts:readonly string[],equipment:readonly Equipment[]){
 if(!equipment.some(e=>e.requiresColdStorage===true&&e.powerRequired===false))return;
 const joined=texts.join(' ');
 if(coldWorkaround.test(joined)&&!professionalPointer.test(joined))throw new Error('cold_storage_workaround');
}

/** Words read from an internal identifier (eq-insulin -> insulin) that appear in no family-facing record are names
 * the model inferred from an ID (Gemini/Groq lake debriefs). Recorded kinds, needs, labels and notes stay allowed. */
const identifierPrefix=/^(?:p|eq|sp|pt|bk|ct|hh)$/;
function words(text:string){return text.replace(/([a-z])([A-Z])/g,'$1 $2').toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);}
export function rejectIdentifierDerivedNames(texts:readonly string[],household:{people:readonly Person[];equipment:readonly Equipment[];backupPower?:readonly {id:string;kind:string}[]|undefined},receipt?:{events:readonly ReceiptEvent[];choices?:readonly {label?:string|undefined}[]}){
 const allowed=new Set<string>();
 const allow=(text:string|undefined)=>{if(text)for(const w of words(text))allowed.add(w);};
 for(const e of household.equipment){allow(e.purpose);allow(e.storageInstructions);}
 for(const b of household.backupPower??[])allow(b.kind);
 for(const p of household.people){for(const n of p.needs)allow(n);allow(p.essentialMedication);allow(p.recordedConditions);allow(p.communicationInstructions);}
 for(const e of receipt?.events??[])allow(e.title);for(const c of receipt?.choices??[])allow(c.label);
 const derived=new Set<string>();
 for(const id of [...household.equipment.map(e=>e.id),...(household.backupPower??[]).map(b=>b.id)]){
  const parts=id.toLowerCase().split(/[-_.]+/);if(!identifierPrefix.test(parts[0]??''))continue;
  for(const part of parts.slice(1))if(/^[a-z]{4,}$/.test(part)&&!allowed.has(part))derived.add(part);
 }
 if(!derived.size)return;
 const said=new Set(texts.flatMap(words));
 for(const part of derived)if(said.has(part))throw new Error('identifier_derived_name');
}
/** A camelCase or snake_case token inside family prose (refrigeratedMedication, eq_insulin) is machine text. */
const embeddedMachineToken=/\b[a-z]{2,}[A-Z][A-Za-z0-9]*\b|\b[a-z0-9]+_[a-z0-9_]+\b/;
export function rejectEmbeddedMachineTokens(texts:readonly string[]){if(texts.some(t=>embeddedMachineToken.test(t)))throw new Error('machine_token');}

/** English or Spanish written for the other selected locale (function-word count; names and units do not count). */
const englishWords=new Set(['the','and','to','of','for','with','your','you','is','are','before','when','if','this','that','what','first','it','in','on']);
const spanishWords=new Set(['el','la','los','las','de','del','para','con','su','sus','es','son','antes','cuando','si','esta','este','que','primero','una','un','y','en','por']);
export function requireEnglishOrSpanish(texts:readonly string[],locale:string|undefined){
 if(locale!=='es'&&locale!==undefined&&locale!=='en')return;
 const tokens=texts.flatMap(t=>t.toLowerCase().split(/[^a-záéíóúñü]+/).filter(Boolean));
 const en=tokens.filter(t=>englishWords.has(t)&&!spanishWords.has(t)).length,es=tokens.filter(t=>spanishWords.has(t)&&!englishWords.has(t)).length;
 if((locale??'en')==='en'?es>=4&&es>en*2:en>=4&&en>es*2)throw new Error('wrong_locale');
}

/** A warming or cooling plan whose required equipment needs the utility the hazard removes (Groq resources plan:
 * electric space heaters during a power-loss freeze). A powered option counts only when it names its own backup. */
const powerLossHazards=new Set(['freeze-power-loss','heat-grid-strain']);
const gridDevice=/\b(?:electric\s+(?:space\s+)?heaters?|space\s+heaters?|plug-?in\s+heaters?|electric\s+blankets?|heated\s+blankets?|portable\s+air\s+conditioners?|window\s+air\s+conditioners?|air\s+conditioners?|air\s+conditioning\s+units?|a\/?c\s+units?|electric\s+fans?|plug-?in\s+fans?|box\s+fans?)\b/i;
const ownPower=/\b(?:battery|batteries|battery-powered|generator|power\s+station|backup\s+power|solar)\b/i;
export function rejectUtilityDependentPlans<P extends {category:string;hazardIDs:readonly string[];purpose:string;mandatoryCapabilities:readonly string[]}>(plans:readonly P[],taskHazards:(plan:P)=>readonly string[]=p=>p.hazardIDs){
 for(const plan of plans){
  if(!['warmingCooling','hardware','equipmentSupplier'].includes(plan.category))continue;
  if(!taskHazards(plan).some(h=>powerLossHazards.has(h)))continue;
  const text=[plan.purpose,...plan.mandatoryCapabilities].join(' ');
  if(gridDevice.test(text)&&!ownPower.test(text))throw new Error('utility_dependent_plan');
 }
}
