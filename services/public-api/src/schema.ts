// Zod schemas mirroring packages/DryRunCore/Sources/DryRunCore/Models/PublicData.swift.
// Shared JSON fixtures are validated here and decoded by Swift contract tests.
import { z } from "zod";

export const ReviewState = z.enum(["reviewed", "draft", "needsReview", "unverified"]);
export const DataClassification = z.enum(["live", "demo", "curated", "fixture"]);
export const CoverageStatus = z.enum(["verifiedPartial", "oemOnly", "notStarted", "statewideOnly"]);
export const ActivationState = z.enum(["active", "inactive", "unknown", "notApplicable"]);
export const ResourceServiceType = z.enum([
  "emergencyManagement", "publicHealth", "waterProvider", "electricUtility", "transportation", "assistanceLine",
  "assistanceRegistry", "disasterAssistance", "warmingCenter", "coolingCenter", "shelter", "alertEnrollment", "other",
]);

const httpsURL = z.string().url().refine((u) => u.startsWith("https://"), "must be https");
export const RegionID = z.string().regex(/^(48\d{3}|tx-statewide|tx-25)$/);

export const SourceRef = z.object({
  id: z.string().regex(/^S\d{2,3}$/),
  publisher: z.string().min(1),
  title: z.string().min(1),
  url: httpsURL,
  checkedAt: z.string().min(1),
  reviewState: ReviewState,
}).strict();

export const ContactPoint = z.object({
  phone: z.string().max(40).optional(),
  phoneNote: z.string().max(400).optional(),
  url: httpsURL.optional(),
  address: z.string().max(200).optional(),
}).strict();

export const PublicResource = z.object({
  id: z.string().regex(/^[A-Za-z0-9._-]{1,64}$/),
  name: z.string().min(1),
  publisher: z.string().min(1),
  serviceType: ResourceServiceType,
  jurisdiction: z.string(),
  regionIDs: z.array(RegionID).min(1),
  contact: ContactPoint,
  summary: z.string().max(1200),
  activation: ActivationState,
  latitude: z.number().optional(),
  longitude: z.number().optional(),
  accessibilityNote: z.string().optional(),
  petPolicy: z.string().optional(),
  sourceIDs: z.array(z.string()).min(1),
  checkedAt: z.string(),
  expiresAt: z.string().optional(),
  reviewState: ReviewState,
  classification: DataClassification,
}).strict().refine((r) => r.activation !== "active" || r.expiresAt !== undefined, "activation requires expiresAt");

export const RegionInfo = z.object({
  id: RegionID,
  name: z.string(),
  kind: z.string(),
  nwsZoneIDs: z.array(z.string().regex(/^[A-Z]{2}Z\d{3}$/)),
  nwsCountyIDs: z.array(z.string().regex(/^[A-Z]{2}C\d{3}$/)),
  coverage: CoverageStatus,
  coverageNote: z.string().optional(),
  inTX25: z.enum(["all", "part", "n/a"]),
}).strict();

export const RegionPack = z.object({
  schemaVersion: z.literal(1),
  contentVersion: z.string().min(1),
  packID: z.string().regex(/^[A-Za-z0-9._-]{1,64}$/),
  generatedAt: z.string(),
  expiresAt: z.string().optional(),
  classification: DataClassification,
  regions: z.array(RegionInfo),
  resources: z.array(PublicResource),
  sources: z.array(SourceRef).min(1),
}).strict().superRefine((p, ctx) => {
  const ids = new Set(p.sources.map((s) => s.id));
  for (const r of p.resources) {
    for (const s of r.sourceIDs) if (!ids.has(s)) ctx.addIssue({ code: "custom", message: `${r.id} cites unknown source ${s}` });
  }
});

export const PublicAlert = z.object({
  id: z.string().min(1).max(300),
  event: z.string(),
  headline: z.string().nullable().optional(),
  description: z.string(),
  instruction: z.string().nullable().optional(),
  severity: z.string(),
  areaDesc: z.string(),
  affectedZones: z.array(z.string()),
  sent: z.string(),
  effective: z.string().nullable().optional(),
  expires: z.string().nullable().optional(),
  ends: z.string().nullable().optional(),
  fetchedAt: z.string(),
  sourceURL: httpsURL,
  classification: DataClassification,
}).strict();

export const AlertsEnvelope = z.object({
  schemaVersion: z.literal(1),
  regionID: RegionID,
  fetchedAt: z.string(),
  status: z.enum(["ok", "unavailable", "notSupported"]),
  alerts: z.array(PublicAlert),
}).strict();

export type RegionPackT = z.infer<typeof RegionPack>;
export type PublicAlertT = z.infer<typeof PublicAlert>;
export type AlertsEnvelopeT = z.infer<typeof AlertsEnvelope>;
export type RegionInfoT = z.infer<typeof RegionInfo>;
