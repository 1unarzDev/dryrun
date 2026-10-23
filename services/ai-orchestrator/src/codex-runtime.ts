import {spawn,execFile, type ChildProcessWithoutNullStreams} from 'node:child_process';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createWriteStream} from 'node:fs';
import {promisify} from 'node:util';
import {protocolFailure} from './codex-errors.js';

export const codexRuntimeVersion='0.163.0';
const verifiedBinaries=new Set<string>();
export const codexEndpoint='https://codex.lunarz.dev/backend-api/codex';
export type RpcMessage={id?:number|string;method?:string;params?:any;result?:any;error?:unknown};
export interface CodexConnection {
 request(method:string,params:unknown):Promise<any>;
 notify(method:string,params?:unknown):void;
 respond(id:number|string,result:unknown):void;
 onMessage:(message:RpcMessage)=>void;
 onFailure:()=>void;
 close():Promise<void>;
}
/** Private stdio transport. Never logs or exposes provider errors/transcripts. */
export async function launchCodex(key:string,model:string,signal:AbortSignal,options:{webSearch?:'live'|'disabled'}={}):Promise<CodexConnection>{
 signal.throwIfAborted();
 const binary=process.env.DRYRUN_CODEX_BIN??'codex';
 // The pinned version is verified once per binary path, not on every operation.
 if(!verifiedBinaries.has(binary)){try{const version=await promisify(execFile)(binary,['--version'],{timeout:5000,maxBuffer:4096,signal});if(version.stdout.trim()!==`codex-cli ${codexRuntimeVersion}`)throw new Error('version');verifiedBinaries.add(binary);}catch{throw new Error('codex_runtime_version_mismatch');}}
 const root=await mkdtemp(join(tmpdir(),'dryrun-codex-'));
 const evidence=await mkdtemp(join(tmpdir(),'dryrun-protected-codex-'));
 const transcript=createWriteStream(join(evidence,'runtime.jsonl'),{mode:0o600});
 const errors=createWriteStream(join(evidence,'stderr'),{mode:0o600});
 const config=`model = ${JSON.stringify(model)}\nmodel_provider = "dryrun_lb"\napproval_policy = "never"\nsandbox_mode = "read-only"\nweb_search = ${JSON.stringify(options.webSearch??'disabled')}\nhistory.persistence = "none"\nfeatures.shell_tool = false\nfeatures.shell_snapshot = false\nfeatures.apply_patch_freeform = false\nfeatures.remote_plugin = false\n[model_providers.dryrun_lb]\nname = "DryRun LB"\nbase_url = ${JSON.stringify(codexEndpoint)}\nwire_api = "responses"\nenv_key = "CODEX_LB_API_KEY"\nrequires_openai_auth = false\nsupports_websockets = false\nrequest_max_retries = 0\nstream_max_retries = 0\n`;
 await writeFile(join(root,'config.toml'),config,{mode:0o600});
 // No owner HOME/config/auth, service credentials, inherited plugins or shell environment.
 const child:ChildProcessWithoutNullStreams=spawn(binary,['app-server','--stdio'],{cwd:root,env:{PATH:process.env.PATH,HOME:root,CODEX_HOME:root,CODEX_LB_API_KEY:key},stdio:'pipe'});
 let seq=0,buffer='',bytes=0,closed=false;
 const pending=new Map<number,{resolve:(value:any)=>void;reject:(error:Error)=>void}>();
 const send=(value:unknown)=>{if(closed)throw new Error('codex_closed');const line=JSON.stringify(value)+'\n';transcript.write(JSON.stringify({direction:'input',message:value})+'\n');child.stdin.write(line);};
 const fail=()=>{if(closed)return;for(const p of pending.values())p.reject(new Error('codex_runtime_unavailable'));pending.clear();connection.onFailure();void connection.close();};
 const connection:CodexConnection={onMessage:()=>{},onFailure:()=>{},request(method,params){return new Promise((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});try{send({id,method,params});}catch{pending.delete(id);reject(new Error('codex_runtime_unavailable'));}});},notify(method,params){send({method,params});},respond(id,result){send({id,result});},async close(){if(closed)return;closed=true;signal.removeEventListener('abort',fail);child.kill('SIGKILL');transcript.end();errors.end();for(const p of pending.values())p.reject(new Error('codex_runtime_unavailable'));pending.clear();await rm(root,{recursive:true,force:true});}};
 child.stdout.on('data',(data:Buffer)=>{transcript.write(JSON.stringify({direction:'output',chunk:data.toString()})+'\n');bytes+=data.length;if(bytes>4_000_000){fail();return;}buffer+=data.toString();let end;while((end=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,end);buffer=buffer.slice(end+1);try{const message=JSON.parse(line) as RpcMessage;if(message.id!==undefined&&!message.method&&typeof message.id==='number'){const p=pending.get(message.id);if(p){pending.delete(message.id);message.error?p.reject(protocolFailure(message.error)):p.resolve(message.result);}}else connection.onMessage(message);}catch{fail();return;}}});
 child.stderr.pipe(errors); // Reviewer-only; never attached to app errors or ordinary logs.
 transcript.on('error',fail);errors.on('error',fail);
 child.on('error',fail);child.on('exit',fail);signal.addEventListener('abort',fail,{once:true});
 return connection;
}
