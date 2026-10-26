import {directorToolSchemas,minimizedSnapshot,toolResult} from '../src/contracts.js';
import type {Host} from './host.js';

/** Native integration must implement the same whitelist. Never forward raw host responses. */
export async function executeDirectorTool(host:Host,state:any,binding:any,call:{name:string;arguments:unknown}){
 if(!Object.hasOwn(directorToolSchemas,call.name))throw new Error('forbidden_tool');
 const args=directorToolSchemas[call.name as keyof typeof directorToolSchemas].parse(call.arguments);
 const response=await host.request({op:'query',session:state.session,tool:{kind:call.name,baseRevision:binding.revision,...args}});
 const tool=response.tool;
 const path=(p:any)=>p?{spaceSequence:p.spaceSequence,portalSequence:p.portalSequence,connectorSequence:p.connectorSequence,verificationNeeded:p.verificationNeeded}:undefined;
 const routes=tool.receipt.routes.map((r:any)=>({personID:r.request.personID,primary:path(r.primary),alternative:path(r.alternative),alternativeStatus:r.alternativeStatus,sharedChokepoints:r.sharedChokepoints,noRouteReason:r.noRouteReason}));
 const result:any={binding,snapshot:minimizedSnapshot(tool.receipt),contextDigest:tool.receipt.contextDigest};
 switch(call.name){
 case 'evaluateCandidateAction':{const s=tool.receipt.snapshot.spatialState;result.preview={routes,directorState:tool.receipt.directorState,...(s?{spatial:{hazard:s.hazard,stageID:s.stageID,originSpaceID:s.originSpaceID,affectedSpaceIDs:s.affectedSpaceIDs,affectedPortalIDs:s.affectedPortalIDs,destinationSpaceID:s.destinationSpaceID,assumptionKey:s.assumptionKey}}:{})};break;}
 case 'inspectScene':result.observation={kind:call.name,...(tool.scene?{scene:tool.scene}:{})};break;
 case 'evaluateResources':result.observation={kind:call.name};break;
 case 'queryRoutes':result.observation={kind:call.name,routes};break;
 case 'inspectDependencies':result.observation={kind:call.name,dependencies:tool.dependencies};break;
 case 'runCounterfactual':result.observation={kind:call.name,scope:'initial_household_with_selected_profiles',failed:tool.counterfactual.failed,criterionID:tool.counterfactual.criterionID,dependencyIDs:tool.counterfactual.dependencyIDs,baseline:minimizedSnapshot(tool.counterfactual.baseline)};break;
 }
 return {result:toolResult.parse(result),receipt:tool.receipt};
}
