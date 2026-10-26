/** Reviewer-controlled local phone session; never emits token values. No owner/cloud consent. */
import {randomBytes,randomUUID} from 'node:crypto';
import {mkdir,writeFile,rm} from 'node:fs/promises';
const sessionID=randomUUID();
const publicURL=process.env.DRYRUN_SYNTHETIC_PUBLIC_URL;
if(!publicURL)throw new Error('explicit_local_phone_url_required');
const parsed=new URL(publicURL);
if(parsed.protocol!=='http:'||!parsed.hostname.endsWith('.local')||!parsed.port||parsed.username||parsed.password||parsed.pathname!=='/'||parsed.search||parsed.hash)throw new Error('local_phone_url_required');
const directory='/private/tmp/dryrun-protected/gateway-'+sessionID;await mkdir(directory,{recursive:true,mode:0o700});
const token=randomBytes(32).toString('base64url');
process.env.DRYRUN_DEV_TOKEN=token;process.env.DRYRUN_PROVIDER='codex';process.env.DRYRUN_LISTEN_HOST='0.0.0.0';process.env.PORT=parsed.port||'8788';
process.env.DRYRUN_CODEX_CAPABILITIES_FILE??=new URL('../profiles/codex-local-synthetic.json',import.meta.url).pathname;
// Native reviewer passes this protected JSON directly through device launch tooling.
await writeFile(directory+'/native-environment.json',JSON.stringify({DRYRUN_SYNTHETIC_GATEWAY_URL:publicURL,DRYRUN_SYNTHETIC_GATEWAY_TOKEN:token}),{mode:0o600});
try{await import('../src/server.js');console.log(JSON.stringify({sessionID,status:'server_imported',scope:'synthetic-only',nativeEnvironmentHandle:directory+'/native-environment.json'}));}
catch{await rm(directory,{recursive:true,force:true});console.log(JSON.stringify({sessionID,status:'startup_failed'}));process.exitCode=1;}
