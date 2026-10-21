/** Reviewer-only fault injection. Synthetic protocol errors, never provider answers. */
import {CodexProvider} from '../../services/ai-orchestrator/src/codex-provider.js';
import {codexEndpoint,codexRuntimeVersion,type CodexConnection,type RpcMessage} from '../../services/ai-orchestrator/src/codex-runtime.js';
const capabilities={runtimeVersion:codexRuntimeVersion,endpoint:codexEndpoint,model:'synthetic-model',reviewReportID:'report-synthetic-review-only',streaming:true,tools:true,continuation:true,structuredOutput:true,lifecycle:true,images:false,research:false};
class Fault implements CodexConnection{
 onMessage=(_m:RpcMessage)=>{};onFailure=()=>{};closed=false;
 async request(method:string){return method==='thread/start'?{thread:{id:'synthetic-thread'}}:{};}
 notify(){} respond(){} async close(){this.closed=true;}
}
for(const mode of ['timeout','429','malformed_schema']){
 const connection=new Fault();
 const provider=new CodexProvider('synthetic-key',capabilities,async()=>connection,mode==='timeout'?30:5000);
 const pending=provider.turn({history:[{type:'user_input',content:[{type:'text',text:'Authored synthetic fault test'}]}],instruction:'Authored synthetic fault test',tools:[],signal:new AbortController().signal});
 let hold=setInterval(()=>{},50);
 if(mode!=='timeout')setTimeout(()=>connection.onMessage({method:'error',params:{threadId:'synthetic-thread',error:{codexErrorInfo:mode==='429'?{httpConnectionFailed:{httpStatusCode:429}}:'other',message:mode==='429'?'Synthetic rate limit':'Synthetic schema rejection'},willRetry:false}}),10);
 try{await pending;console.log(JSON.stringify({mode,result:'unexpected_success'}));process.exitCode=1;}
 catch(error){console.log(JSON.stringify({mode,typedReason:error instanceof Error?error.message:'non_error',closed:connection.closed}));}
 finally{clearInterval(hold);await connection.close();}
}
