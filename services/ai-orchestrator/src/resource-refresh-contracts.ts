import {z} from 'zod';
/** Local scheduling identity only; it never contains native geographic listings or their origin. */
export const resourceStrategyKey=z.object({schemaVersion:z.literal('dryrun.resource-strategy-key/1').optional(),gapCategories:z.array(z.string().min(1).max(120)).max(30),transport:z.string().min(1).max(30),limitedBudget:z.boolean(),regionID:z.string().min(1).max(120),normalizedInputDigest:z.string().regex(/^[a-f0-9]{1,16}$/).optional(),relatedTaskIDs:z.array(z.string().min(1).max(120)).max(100).optional()}).strict();
