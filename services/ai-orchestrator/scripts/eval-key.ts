import {readFile} from 'node:fs/promises';
import {homedir} from 'node:os';
/** Development/server evaluations only. Never bundle this module into the native app. */
export async function evaluationKey(){
 if(process.env.DRYRUN_USE_BACKUP_KEY!=='1')return process.env.GOOGLE_AI_STUDIO_KEY??'';
 if(process.env.BACKUP_GOOGLE_AI_STUDIO_KEY)return process.env.BACKUP_GOOGLE_AI_STUDIO_KEY;
 const text=await readFile(homedir()+'/.config/caelestia/.env.secrets','utf8');
 const line=text.split('\n').find(l=>/\bBACKUP_GOOGLE_AI_STUDIO_KEY\b/.test(l)&&!l.trimStart().startsWith('#'))??'';
 const value=line.match(/^\s*set\s+-(?:gx|xg)\s+BACKUP_GOOGLE_AI_STUDIO_KEY\s+"([^"\r\n]+)"\s*$/)?.[1]
  ??line.match(/^\s*(?:export\s+)?BACKUP_GOOGLE_AI_STUDIO_KEY=['"]?([^'"\s]+)['"]?\s*$/)?.[1];
 if(!value)throw new Error('backup_secret_format');return value;
}

export async function groqEvaluationKey(){
 if(process.env.GROQ_API_KEY)return process.env.GROQ_API_KEY;
 const text=await readFile(homedir()+'/.config/caelestia/.env.secrets','utf8');
 const line=text.split('\n').find(l=>/^\s*(?:set\s+-(?:gx|xg)\s+|(?:export\s+)?)GROQ_API_KEY(?:\s|=)/.test(l))??'';
 const value=line.match(/^\s*set\s+-(?:gx|xg)\s+GROQ_API_KEY\s+"([^"\r\n]+)"\s*$/)?.[1]??line.match(/^\s*(?:export\s+)?GROQ_API_KEY=['"]?([^'"\s]+)['"]?\s*$/)?.[1];
 if(!value)throw new Error('groq_secret_format');return value;
}
