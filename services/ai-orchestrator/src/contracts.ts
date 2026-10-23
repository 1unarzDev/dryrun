import {privateContext,contextBinding} from './private-context.js';
import {anonymousHousehold,scene} from './features.js';
import { z } from 'zod';
import {suggestedAction,userCommand} from './user-commands.js';
export const version='dryrun.ai/1';
export const hazard=z.enum(['freezePowerLoss','heatGridStrain','tornado','flashFlood','homeFire','waterOutage']);
export const directorPolicy=z.object({version:z.literal('dryrun.director-policy/1'),permittedHazardFamilies:z.array(hazard).min(1).max(6),maximumActiveIncidents:z.number().int().min(0).max(1),schedulingHorizonMinutes:z.number().int().min(0).max(4320),eventBudget:z.number().int().min(0).max(32),maximumPendingEvents:z.number().int().min(1).max(8),allowedStageTransitions:z.array(z.object({from:z.string().max(120),to:z.string().max(120)}).strict()).max(820)}).strict();
export const waitPredicate=z.enum(['nextIncident','storedWaterUnavailable','primaryContactChannelUnavailable']);
export const waitOutcome=z.object({predicate:waitPredicate,startedMinute:z.number().int().nonnegative(),maximumDurationMinutes:z.number().int().min(1).max(4320),stoppedMinute:z.number().int().nonnegative(),satisfied:z.boolean(),reason:z.enum(['predicate','mandatoryBoundary','policyHorizon','durationLimit'])}).strict();
export const directorState=z.object({activeIncidentCount:z.number().int().min(0).max(1),scheduledEventCount:z.number().int().nonnegative().max(32),awaitingUserAction:z.boolean().optional(),stageID:z.string().max(120).optional(),originSpaceID:z.string().max(120).optional(),lastWait:waitOutcome.optional()}).strict();
const commandID=z.string().min(1).max(120);
const minute=z.number().int().nonnegative().max(4320);
export const command=z.discriminatedUnion('kind',[
 z.object({kind:z.literal('schedule'),target:commandID,minute}).strict(),
 z.object({kind:z.literal('startIncident'),target:commandID,value:commandID.optional(),hazard,minute}).strict(),
 z.object({kind:z.literal('advanceIncident'),target:commandID,hazard,minute}).strict(),
 z.object({kind:z.literal('advance'),minute}).strict(),
 z.object({kind:z.literal('waitUntil'),target:waitPredicate,durationMinutes:z.number().int().min(1).max(4320)}).strict(),
 z.object({kind:z.literal('requestDecision')}).strict(),
 z.object({kind:z.literal('finish')}).strict(),
]);
export const directorOutput=z.object({suggestedActions:z.array(suggestedAction).max(4).optional(),commands:z.array(command).min(1).max(8),purpose:z.string().min(1).max(900),evidenceIDs:z.array(z.string().max(120)).max(20)}).strict();
export const binding=z.object({sessionID:z.string().min(1).max(120),revision:z.number().int().nonnegative(),eventSequence:z.number().int().nonnegative(),contextDigest:z.string().min(1).max(128),householdRevision:z.number().int().nonnegative(),homeRevision:z.number().int().nonnegative()}).strict();
export const snapshot=z.object({firedEventIDs:z.array(z.string().max(200)).max(5000).optional(),simMinute:z.number().int().nonnegative(),resources:z.record(z.string(),z.object({amount:z.number().nonnegative().nullable().optional(),unit:z.enum(['gal','Wh','h','charges','day'])}).strict()),services:z.record(z.string(),z.enum(['operational','degraded','unavailable','unknown'])),unmetRequirements:z.array(z.string()).max(100),unknowns:z.array(z.string()).max(100)}).strict();
export const committedActionContext=z.object({contractVersion:z.literal('dryrun.committed-action-context/1').optional(),id:z.string().min(1).max(120),kind:z.string().min(1).max(120),target:z.string().max(120).optional(),value:z.string().max(120).optional(),commitRevision:z.number().int().positive().optional(),commandIndex:z.number().int().min(0).max(7).optional(),quantityLiters:z.number().positive().max(20).optional()}).strict();
const legacyHazardExperience=z.object({mechanicsVersion:z.literal('dryrun.hazard-mechanics/1'),hazard,scene:z.enum(['smoke-egress-accounting','warning-shelter-exposure','rising-water-access','cold-continuity-energy','heat-cooling-access','service-advisory-water-use']),objective:z.string().max(300),supportedActions:z.array(commandID).max(15),feasibleCommands:z.array(userCommand).max(1000).optional(),outsidePersonIDs:z.array(commandID).max(20),accountedPersonIDs:z.array(commandID).max(20),shelteredPersonIDs:z.array(commandID).max(20),destinationIDs:z.array(commandID).max(20),occupantRoomIDs:z.record(commandID,commandID),shelterRoomID:commandID.optional(),relocated:z.boolean(),temperature:z.object({lowerC:z.number(),upperC:z.number(),model:z.literal('illustrative-room-range/1'),assumption:z.string().max(600)}).strict().optional(),waterAdvisory:z.enum(['quantityUnavailable','unknownQuality','boilWater','doNotDrink','doNotUse']).optional(),waterService:z.enum(['operational','degraded','unavailable','unknown']).optional(),availableWaterGallons:z.number().nonnegative().optional(),selectedProtection:z.string().max(200).optional(),openGapIDs:z.array(commandID).max(10),identifiedGapIDs:z.array(commandID).max(10),debrief:z.array(z.object({kind:commandID,subjectIDs:z.array(commandID).max(20),eventIDs:z.array(z.string().max(200)).max(5000),nextActionID:commandID}).strict()).max(100)}).strict();
const roomTemperature=z.object({lowerC:z.number(),upperC:z.number(),model:z.literal('illustrative-room-range/2'),assumption:z.string().max(600)}).strict().refine(range=>range.lowerC<=range.upperC,'invalid_temperature_range');
const roomHazardExperience=legacyHazardExperience.extend({
 mechanicsVersion:z.literal('dryrun.hazard-mechanics/2'),
 temperature:z.union([legacyHazardExperience.shape.temperature.unwrap(),roomTemperature]).optional(),
 roomTemperatures:z.record(commandID,roomTemperature).refine(rooms=>Object.keys(rooms).length<=100,'room_budget').optional(),
 shadedRoomIDs:z.array(commandID).max(100).optional(),
 conditioningService:z.enum(['operational','degraded','unavailable','unknown']).optional(),
 roomCoolingCoverageUnknown:z.literal(true).optional(),
});
const currentHazardExperience=roomHazardExperience.extend({mechanicsVersion:z.literal('dryrun.hazard-mechanics/3'),openGapIDs:z.array(commandID).max(100),identifiedGapIDs:z.array(commandID).max(100)});
const refugeHazardExperience=currentHazardExperience.extend({mechanicsVersion:z.literal('dryrun.hazard-mechanics/4'),refugeRoomID:commandID.optional(),refugedPersonIDs:z.array(commandID).max(20).optional()});
const assistedHazardExperience=refugeHazardExperience.extend({mechanicsVersion:z.literal('dryrun.hazard-mechanics/5'),escapeHelperByPersonID:z.record(commandID,commandID).optional()});
// mechanics/6 is field-identical to /5: origin exclusion at the alarm, outage-readiness debrief facts and an explicit user wait are host-side.
const originHazardExperience=assistedHazardExperience.extend({mechanicsVersion:z.literal('dryrun.hazard-mechanics/6')});
// mechanics/7 is field-identical to /6: freeze gathering (moveTo into the room of the person hardest to move) is host-side.
const gatheringHazardExperience=assistedHazardExperience.extend({mechanicsVersion:z.literal('dryrun.hazard-mechanics/7')});
export const hazardExperience=z.discriminatedUnion('mechanicsVersion',[legacyHazardExperience,roomHazardExperience,currentHazardExperience,refugeHazardExperience,assistedHazardExperience,originHazardExperience,gatheringHazardExperience]);
export const exerciseAssistance=z.object({personID:commandID,helperID:commandID.optional(),reachStatus:z.enum(['reachable','unreachable','unknown','missingHelper']),sharedWithPersonIDs:z.array(commandID).max(20),simultaneousCapacity:z.enum(['notAssessed','unknown'])}).strict();
export const directorContext=z.object({binding,snapshot,locale:z.enum(['en','es','vi']).optional(),privateContext:privateContext.optional(),contextBinding:contextBinding.optional(),experience:hazardExperience.optional(),assistance:z.array(exerciseAssistance).max(20).optional(),initialInventoryItemIDs:z.array(commandID).max(100).optional(),directorPolicy:directorPolicy.optional(),directorState:directorState.optional(),pending:z.array(command).max(8).optional(),closedPortalIDs:z.array(z.string().max(120)).max(200).optional(),household:anonymousHousehold.optional(),homeScene:scene.optional(),profiles:z.array(z.object({id:z.string(),rule:z.string(),minute:z.number().int(),hazard:hazard.optional(),spatial:z.boolean().optional(),canStart:z.boolean().optional(),roomRequired:z.boolean().optional()}).strict()).max(40),learningObjectives:z.array(z.string().max(200)).max(6).default([]),lastAction:committedActionContext.optional(),recentActions:z.array(committedActionContext).max(8).optional()}).strict().superRefine((data,ctx)=>{
 if(data.privateContext&&((data.household&&data.household.revision!==data.binding.householdRevision)||(data.homeScene&&data.homeScene.homeRevision!==data.binding.homeRevision)))ctx.addIssue({code:'custom',path:['binding'],message:'stale_context'});
 if(data.privateContext&&(!data.contextBinding||data.contextBinding.revisions.household!==data.binding.householdRevision||(data.contextBinding.revisions.home??0)!==data.binding.homeRevision))ctx.addIssue({code:'custom',path:['contextBinding'],message:'stale_context'});
 const actions=data.recentActions;
 if(!actions)return;
 for(let n=0;n<actions.length;n++){
  const action=actions[n]!,previous=actions[n-1];
  if(action.contractVersion!=='dryrun.committed-action-context/1'||action.commitRevision===undefined||action.commandIndex===undefined||action.commitRevision>data.binding.revision||previous&&(action.commitRevision<previous.commitRevision!||action.commitRevision===previous.commitRevision&&(action.commandIndex<=previous.commandIndex!||action.id!==previous.id)))ctx.addIssue({code:'custom',path:['recentActions',n],message:'invalid_committed_action_order'});
 }
 const last=actions.at(-1);
 if(last? !data.lastAction||Object.keys(last).some(key=>Reflect.get(last,key)!==Reflect.get(data.lastAction!,key)):data.lastAction!==undefined)ctx.addIssue({code:'custom',path:['lastAction'],message:'latest_committed_action_mismatch'});
});
export type DirectorContext=z.infer<typeof directorContext>;
export const toolArgs=z.object({command:command.optional(),commands:z.array(command).min(1).max(8).optional()}).strict();
const toolID=z.string().min(1).max(120);
export const stressRetestPlan=z.object({version:z.literal('dryrun.stress-retest/1'),commands:z.array(z.union([
 ...[
  ['moveTo','Recorded person ID to move','Recorded destination room ID'],
  ['takeSupply','Recorded inventory item ID, not a resource balance ID','Recorded person ID who picks it up'],
  ['transferSupply','Recorded inventory item ID','Recorded current carrier room ID where the item is put down'],
  ['assignHelper','Recorded person ID needing help','Recorded helper person ID'],
  ['closeDoor','Recorded operable door portal ID','Recorded adjacent person ID'],
  ['allocatePower','Recorded equipment ID','Compatible recorded backup ID or none'],
 ].map(([kind,target,value])=>z.object({kind:z.literal(kind!),target:toolID.describe(target!),value:toolID.describe(value!)}).strict()),
 z.object({kind:z.literal('useStoredWater'),value:z.enum(['essential','all'])}).strict(),
])).min(1).max(8)}).strict();
export const stressRetestComparison=z.object({version:z.literal('dryrun.stress-comparison/1'),baselineMinute:minute,retestMinute:minute,commonHorizonReached:z.boolean(),resolvedRequirementIDs:z.array(toolID).max(100),remainingRequirementIDs:z.array(toolID).max(100),newlyUnmetRequirementIDs:z.array(toolID).max(100),remainingUnknownIDs:z.array(toolID).max(100)}).strict();
export const directorToolSchemas={
 evaluateCandidateAction:toolArgs,
 inspectScene:z.object({}).strict(),
 queryRoutes:z.object({}).strict(),
 evaluateResources:z.object({}).strict(),
 inspectDependencies:z.object({}).strict(),
 runCounterfactual:z.object({profileIDs:z.array(toolID).min(1).max(8),retestPlan:stressRetestPlan.optional()}).strict(),
};
const dependency=z.object({id:toolID,kind:toolID,subjectIDs:z.array(toolID).max(100),evidenceIDs:z.array(z.string().max(128)).max(100),status:z.string().max(300)}).strict();
const path=z.object({spaceSequence:z.array(toolID).max(100),portalSequence:z.array(toolID).max(200),connectorSequence:z.array(toolID).max(50),verificationNeeded:z.array(toolID).max(200)}).strict();
const route=z.object({personID:toolID.optional(),primary:path.optional(),alternative:path.optional(),alternativeStatus:z.enum(['independent','sharesChokepoint','none']),sharedChokepoints:z.array(toolID).max(200),noRouteReason:z.enum(['noVerifiedExteriorExit','incompleteConnectivity','incompatibleMobility','blockedByScenario','missingBuildingPlan','invalidGeometry','unknownStartSpace']).optional()}).strict();
const successfulToolObservation=z.discriminatedUnion('kind',[
 z.object({kind:z.literal('inspectScene'),scene:scene.optional()}).strict(),
 z.object({kind:z.literal('queryRoutes'),routes:z.array(route).max(100)}).strict(),
 z.object({kind:z.literal('evaluateResources')}).strict(),
 z.object({kind:z.literal('inspectDependencies'),dependencies:z.array(dependency).max(100)}).strict(),
 z.object({kind:z.literal('runCounterfactual'),scope:z.literal('initial_household_with_selected_profiles'),sourceConcernDigest:z.string().min(1).max(128).optional(),failed:z.boolean(),criterionID:toolID,dependencyIDs:z.array(toolID).max(100),baseline:snapshot,controlledRetest:snapshot.optional(),comparison:stressRetestComparison.optional()}).strict(),
]);
export const toolObservation=z.union([successfulToolObservation,z.object({kind:z.literal('runCounterfactual'),status:z.literal('unavailable'),reason:z.literal('host_rejected_counterfactual')}).strict()]);
export const previewConsequences=z.object({experience:hazardExperience.optional(),assistance:z.array(exerciseAssistance).max(20).optional(),routes:z.array(route).max(100),directorState:directorState.optional(),spatial:z.object({hazard,stageID:toolID,originSpaceID:toolID.optional(),affectedSpaceIDs:z.array(toolID).max(100),affectedPortalIDs:z.array(toolID).max(200),destinationSpaceID:toolID.optional(),assumptionKey:toolID.optional()}).strict().optional()}).strict();
export const suggestionValidationArgs=z.object({commands:z.array(command).min(1).max(8),suggestedActions:z.array(suggestedAction).min(1).max(4)}).strict();
export const suggestionValidation=z.array(z.object({id:toolID,feasible:z.boolean(),rejection:z.string().max(120).optional()}).strict()).min(1).max(4);
export const toolResult=z.object({binding,snapshot,suggestionValidation:suggestionValidation.optional(),rejection:z.object({kind:z.literal('evaluateCandidateAction'),reason:z.enum(['invalidCommand','budget','finished'])}).strict().optional(),contextDigest:z.string().max(128),observation:toolObservation.optional(),preview:previewConsequences.optional()}).strict();
export const operationRequest=z.object({contractVersion:z.literal(version),requestID:z.string().min(1).max(120),role:z.literal('director'),synthetic:z.literal(true),providerConsent:z.array(z.enum(['gemini','groq','codex'])).min(1).max(3).optional(),context:directorContext}).strict();
export const continuationRequest=z.object({token:z.string(),binding,callID:z.string(),result:toolResult}).strict();
export function minimizedSnapshot(receipt:{snapshot:Record<string,unknown>}){const {simMinute,resources,services,unmetRequirements,unknowns,firedEventIDs}=receipt.snapshot;return snapshot.parse({simMinute,resources,services,unmetRequirements,unknowns,firedEventIDs});}

/** Only current host-computed identity/reach metadata; omit route geometry and private annotations.
 * Undefined is not assessed, while an empty array is an assessed empty summary. */
export function minimizedAssistance(receipt:{assistance?:readonly Record<string,unknown>[]}){
 if(receipt.assistance===undefined)return undefined;
 return z.array(exerciseAssistance).max(20).parse(receipt.assistance.map(({personID,helperID,reachStatus,sharedWithPersonIDs,simultaneousCapacity})=>({personID,helperID,reachStatus,sharedWithPersonIDs,simultaneousCapacity})));
}
