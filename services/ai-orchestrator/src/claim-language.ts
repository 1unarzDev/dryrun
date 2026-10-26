/** Narrow checks for observed unsupported assurances, not a semantic grounding classifier.
 * Negation belongs to the matched claim, never to an entire sentence. */
export function rejectUnsupportedAssurances(fields:string[]){
 const patterns:[RegExp,string][]=[
  [/\b(?:confirms?|establishes?|certifies?|proves?)\s+[^.!?;]{0,50}\b(?:safe escape|safe evacuation|structural safety)\b/gi,'unsupported_safety_assurance'],
  [/\bmaintain(?:s|ing)?\s+[^.!?;]{0,60}\boxygen supply\b/gi,'unsupported_clinical_assurance'],
  [/\b(?:reached|reaching|achieved|arrived at)\s+(?:complete\s+)?safety\b/gi,'unsupported_safety_assurance'],
  [/\b(?:ensures?|guarantees?|ensuring|guaranteeing)\s+[^.!?;]{0,90}?(?:safe(?:ty)?|survival|hydration needs|protection|comfort|(?:equipment\s+)?reliab(?:ility|ly)|continuity)\b/gi,'unsupported_safety_assurance'],
  [/\b(?:safely\s+(?:sheltered|escaped|evacuated)|(?:reaches?|reached|reaching)\s+(?:the\s+)?shelter\s+safely)\b/gi,'unsupported_safety_assurance'],
 ];
 for(const field of fields)for(const clause of field.split(/[.!?;]|\b(?:but|however|yet|and|while)\b/i)){
  for(const [pattern,reason] of patterns)for(const match of clause.matchAll(pattern)){
   const prefix=clause.slice(0,match.index);
   // Permit direct verb negation and a locally negated subject ("no destination guarantees").
   // An earlier unrelated negative must not excuse a later positive claim.
   const negated=/\b(?:cannot|can\s+not|does\s+not|do\s+not|did\s+not|will\s+not|never|not|nothing)\s+(?:\w+ly\s+)?$/i.test(prefix)
    ||/\bno\s+(?:[\w-]+\s+){1,4}$/i.test(prefix);
   if(!negated)throw new Error(reason);
  }
 }
}
