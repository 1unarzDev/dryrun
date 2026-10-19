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
export const toolResult=z.object({binding,snapshot,contextDigest:z.string().max(128)}).strict();
export const operationRequest=z.object({contractVersion:z.literal(version),requestID:z.string().min(1).max(120),role:z.literal('director'),synthetic:z.literal(true),context:directorContext}).strict();
export const continuationRequest=z.object({token:z.string(),binding,callID:z.string(),result:toolResult}).strict();
export function minimizedSnapshot(receipt:{snapshot:Record<string,unknown>}){const {simMinute,resources,services,unmetRequirements,unknowns}=receipt.snapshot;return snapshot.parse({simMinute,resources,services,unmetRequirements,unknowns});}
