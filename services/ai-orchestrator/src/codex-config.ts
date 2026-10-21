import {readFile} from 'node:fs/promises';
import {parseEnv} from 'node:util';
import {CodexProvider,type CodexCapabilities} from './codex-provider.js';

/** Explicit local-demo deployment only. No implicit provider switch or retry layer. */
export async function configuredCodexProvider():Promise<CodexProvider>{
 if(process.env.NODE_ENV==='production')throw new Error('codex_experimental_not_production');
 const evidenceFile=process.env.DRYRUN_CODEX_CAPABILITIES_FILE;
 if(!evidenceFile)throw new Error('codex_capability_gate');
 const capability:CodexCapabilities=JSON.parse(await readFile(evidenceFile,'utf8'));
 // Only the named service secret is loaded, never owner Codex auth/config.
 let key=process.env.CODEX_LB_API_KEY;
 if(!key){try{const env=parseEnv(await readFile(new URL('../.env',import.meta.url),'utf8'));key=env.CODEX_LB_API_KEY;}catch{throw new Error('missing_provider_secret');}}
 return new CodexProvider(key??'',capability);
}
