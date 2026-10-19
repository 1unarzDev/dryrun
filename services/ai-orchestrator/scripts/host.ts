import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {resolve} from 'node:path';
export class Host {
 private child=spawn('docker',['run','--rm','-i','-v',`${resolve('../..')}:/repo`,'-w','/repo','swift:6.2','/repo/.build-linux/default/packages_DryRunCore/x86_64-unknown-linux-gnu/debug/dryrun-host'],{stdio:['pipe','pipe','inherit']});
 private waiting:{resolve:(value:any)=>void;reject:(error:Error)=>void;timer:NodeJS.Timeout}[]=[];
 private closed=false;
 constructor(){
  createInterface({input:this.child.stdout}).on('line',line=>{
   const pending=this.waiting.shift();if(!pending)return;clearTimeout(pending.timer);
   try{const result=JSON.parse(line);if(result.error)pending.reject(new Error(result.error));else pending.resolve(result);}catch{pending.reject(new Error('invalid_host_response'));this.close();}
  });
  this.child.on('error',()=>this.fail('host_unavailable'));
  this.child.on('exit',()=>this.fail('host_exited'));
 }
 private fail(reason:string){this.closed=true;for(const p of this.waiting){clearTimeout(p.timer);p.reject(new Error(reason));}this.waiting=[];}
 request(value:unknown):Promise<any>{
  if(this.closed)return Promise.reject(new Error('host_closed'));
  if(this.waiting.length>=16)return Promise.reject(new Error('host_queue_budget'));
  return new Promise((resolve,reject)=>{
   const timer=setTimeout(()=>{this.fail('host_timeout');this.child.kill();},60000);
   this.waiting.push({resolve,reject,timer});this.child.stdin.write(JSON.stringify(value)+'\n');
  });
 }
 close(){this.fail('host_closed');this.child.stdin.end();}
}
