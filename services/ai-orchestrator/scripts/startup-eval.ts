import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const base={...process.env,GOOGLE_AI_STUDIO_KEY:'',DRYRUN_DEV_TOKEN:'synthetic-token-for-startup-test'};
for(const [environment,expected] of [['production','production_authorization_provider_required'],['development','missing_provider_secret']] as const){
 const result=spawnSync(process.execPath,['--import','tsx','src/server.ts'],{env:{...base,NODE_ENV:environment},encoding:'utf8',timeout:10000});
 assert.notEqual(result.status,0);assert.ok(result.stderr.includes(expected));
 console.log(JSON.stringify({environment,rejected:true,reason:expected}));
}
