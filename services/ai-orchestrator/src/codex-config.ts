import {readFile} from 'node:fs/promises';
import {parseEnv} from 'node:util';
import {CodexProvider,codexSpeedFromEnv,type CodexCapabilities} from './codex-provider.js';
import {launchCodex} from './codex-runtime.js';

/** The service-owned .env. DRYRUN_SERVICE_ENV_FILE names it by absolute path when this checkout is a worktree;
 * the file itself is never copied into the repository. */
export function serviceEnvFile(env:Record<string,string|undefined>=process.env){return env.DRYRUN_SERVICE_ENV_FILE||new URL('../.env',import.meta.url);}

/** Explicit local-demo deployment only. Fallback ownership stays in the provider router, not here. */
export async function configuredCodexProvider(env:Record<string,string|undefined>=process.env):Promise<CodexProvider>{
 if(env.NODE_ENV==='production')throw new Error('codex_experimental_not_production');
 const evidenceFile=env.DRYRUN_CODEX_CAPABILITIES_FILE;
 if(!evidenceFile)throw new Error('codex_capability_gate');
 const capability:CodexCapabilities=JSON.parse(await readFile(evidenceFile,'utf8'));
 // Only the named service secret is loaded, never owner Codex auth/config.
 let key=env.CODEX_LB_API_KEY;
 if(!key){try{const service=parseEnv(await readFile(serviceEnvFile(env),'utf8'));key=service.CODEX_LB_API_KEY;}catch{throw new Error('missing_provider_secret');}}
 return new CodexProvider(key??'',capability,launchCodex,undefined,codexSpeedFromEnv(env));
}
