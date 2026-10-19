import {anonymousHousehold,scene} from './features.js';
import { z } from 'zod';
export const version='dryrun.ai/1';
export const command=z.object({kind:z.enum(['schedule','advance','requestDecision','finish']),target:z.string().max(120).optional(),value:z.string().max(120).optional(),minute:z.number().int().nonnegative().max(4320).optional()}).strict();
export const directorOutput=z.object({commands:z.array(command).min(1).max(8),purpose:z.string().min(1).max(900),evidenceIDs:z.array(z.string().max(120)).max(20)}).strict();
export const binding=z.object({sessionID:z.string().min(1).max(120),revision:z.number().int().nonnegative(),eventSequence:z.number().int().nonnegative(),contextDigest:z.string().min(1).max(128),householdRevision:z.number().int().nonnegative(),homeRevision:z.number().int().nonnegative()}).strict();
export const snapshot=z.object({simMinute:z.number().int().nonnegative(),resources:z.record(z.string(),z.object({amount:z.number().nonnegative().nullable().optional(),unit:z.enum(['gal','Wh','h','charges'])}).strict()),services:z.record(z.string(),z.enum(['operational','degraded','unavailable','unknown'])),unmetRequirements:z.array(z.string()).max(100),unknowns:z.array(z.string()).max(100)}).strict();
export const directorContext=z.object({binding,snapshot,household:anonymousHousehold.optional(),homeScene:scene.optional(),profiles:z.array(z.object({id:z.string(),rule:z.string(),minute:z.number().int()}).strict()).max(40),learningObjectives:z.array(z.string().max(200)).max(6).default([]),lastAction:z.object({id:z.string(),kind:z.string(),target:z.string().optional(),value:z.string().optional()}).strict().optional()}).strict();
export type DirectorContext=z.infer<typeof directorContext>;
export const toolArgs=z.object({command}).strict();
const toolID=z.string().min(1).max(120);
export const directorToolSchemas={
 evaluateCandidateAction:toolArgs,
 inspectScene:z.object({}).strict(),
 queryRoutes:z.object({}).strict(),
 evaluateResources:z.object({}).strict(),
 inspectDependencies:z.object({}).strict(),
 runCounterfactual:z.object({profileIDs:z.array(toolID).min(1).max(8)}).strict(),
};
const dependency=z.object({id:toolID,kind:toolID,subjectIDs:z.array(toolID).max(100),evidenceIDs:z.array(z.string().max(128)).max(100),status:z.string().max(300)}).strict();
const path=z.object({spaceSequence:z.array(toolID).max(100),portalSequence:z.array(toolID).max(200),connectorSequence:z.array(toolID).max(50),verificationNeeded:z.array(toolID).max(200)}).strict();
const route=z.object({personID:toolID.optional(),primary:path.optional(),alternative:path.optional(),alternativeStatus:z.enum(['independent','sharesChokepoint','none']),sharedChokepoints:z.array(toolID).max(200),noRouteReason:z.enum(['noVerifiedExteriorExit','incompleteConnectivity','incompatibleMobility','blockedByScenario','missingBuildingPlan','invalidGeometry','unknownStartSpace']).optional()}).strict();
export const toolObservation=z.discriminatedUnion('kind',[
 z.object({kind:z.literal('inspectScene'),scene:scene.optional()}).strict(),
 z.object({kind:z.literal('queryRoutes'),routes:z.array(route).max(100)}).strict(),
 z.object({kind:z.literal('evaluateResources')}).strict(),
 z.object({kind:z.literal('inspectDependencies'),dependencies:z.array(dependency).max(100)}).strict(),
 z.object({kind:z.literal('runCounterfactual'),scope:z.literal('initial_household_with_selected_profiles'),failed:z.boolean(),criterionID:toolID,dependencyIDs:z.array(toolID).max(100),baseline:snapshot}).strict(),
]);
export const toolResult=z.object({binding,snapshot,contextDigest:z.string().max(128),observation:toolObservation.optional()}).strict();
export const operationRequest=z.object({contractVersion:z.literal(version),requestID:z.string().min(1).max(120),role:z.literal('director'),synthetic:z.literal(true),context:directorContext}).strict();
export const continuationRequest=z.object({token:z.string(),binding,callID:z.string(),result:toolResult}).strict();
export function minimizedSnapshot(receipt:{snapshot:Record<string,unknown>}){const {simMinute,resources,services,unmetRequirements,unknowns}=receipt.snapshot;return snapshot.parse({simMinute,resources,services,unmetRequirements,unknowns});}
