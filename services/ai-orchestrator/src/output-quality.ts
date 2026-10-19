/** Presentation guidance is role/field specific. Advisory word bands diagnose verbosity;
 * they never truncate safety information or promote semantic correctness from word count. */
export const outputStyleVersion='dryrun.output-style/1';
export const outputStyle=`Use plain, direct language suited to a phone. For each task give one concrete next action and its household-specific reason, usually 12–45 words; do not merely restate a title. Resource purposes usually need 12–40 words and a missing requirement or verification limit. Home findings need the visible evidence, a possible concern, a plausible alternative and one short confirmation question in separate fields; avoid repeating the same paragraph across fields. Do not say a new incident forced or changed a route unless a host-computed before/after comparison establishes that change; otherwise describe the current route and dependency only. Director purpose usually needs 30–90 words: explain the computed consequence of the last committed action, what changes next, and one useful decision; mark unknowns and hypothetical effects. Council explanations usually need 15–45 words naming the relevant confirmed and missing predicates, never broad readiness claims from ownership alone. These are flexible guides, not targets to pad. Use “no supported route is recorded” rather than declaring no real exit exists or movement impossible. A modeled route does not prove an actual path is clear or safe. Avoid greetings, repeated disclaimers, jargon, long lists and generic encouragement. Use question:null unless a missing answer materially changes the next useful action; never ask users to reprioritize an already prioritized list or approve an ordinary search. Keep sources and detailed evidence in their structured fields. Narration remains an unverified proposal; UI renders actual effects from the committed host receipt.`;
export type OutputQualityField={path:string;words:number;band:[number,number];flags:string[];text:string};
export function inspectOutput(role:string,value:unknown):OutputQualityField[]{
 const output:OutputQualityField[]=[];
 function walk(item:unknown,path:string){
  if(Array.isArray(item)){item.forEach((v,i)=>walk(v,path+'['+i+']'));return;}
  if(!item||typeof item!=='object')return;
  for(const [key,v] of Object.entries(item)){
   const p=path?path+'.'+key:key;
   if(typeof v==='string'&&['why','purpose','visibleEvidence','concern','confirmationPrompt','improvement','reason','question'].includes(key)){
    const words=v.trim().split(/\s+/u).filter(Boolean).length;
    const band:[number,number]=key==='question'||key==='confirmationPrompt'?[6,30]:key==='purpose'&&role==='director'?[30,90]:[12,45];
    const flags:string[]=[];if(words<band[0])flags.push('review_depth');if(words>band[1])flags.push('review_length');
    if(/would you like|could you please/i.test(v))flags.push('review_unnecessary_permission_or_padding');
    if(/safe|confirmed|verified|uninterrupted/i.test(v))flags.push('check_claim_against_host_evidence');
    output.push({path:p,words,band,flags,text:v});
   } else walk(v,p);
  }
 }
 walk(value,'');return output;
}
