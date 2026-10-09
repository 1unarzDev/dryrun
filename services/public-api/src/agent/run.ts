// Fixed pipeline: code (not the model) decides which sources to fetch — the region pack's cited source IDs.
import { extractClaims } from "./extract";
import { fetchOfficialSource, type FetchDeps, type SourceAllowlist } from "./fetchSource";
import { buildModelPrompt, validateModelProposals, type ModelProvider } from "./model";
import type { FetchedSource, PublicClaim } from "./types";

export interface AgentRunResult {
  regionID: string;
  fetched: string[];
  failed: Array<{ sourceID: string; reason: string }>;
  claims: PublicClaim[];
  modelUsed: boolean;
  modelRejected: number;
}

export async function runRegionalAgent(regionID: string, sourceIDs: string[], jurisdiction: string | null,
  allow: SourceAllowlist, deps: FetchDeps, provider: ModelProvider): Promise<AgentRunResult> {
  const fetched: FetchedSource[] = [];
  const failed: AgentRunResult["failed"] = [];
  for (const id of [...new Set(sourceIDs)].sort().slice(0, 20)) {
    try { fetched.push(await fetchOfficialSource(id, allow, deps)); }
    catch (e) { failed.push({ sourceID: id, reason: e instanceof Error ? e.message : "error" }); }
  }
  const ctx = { regionID, jurisdiction };
  const claims = fetched.flatMap((s) => extractClaims(s, ctx));
  let modelUsed = false, modelRejected = 0;
  if (fetched.length > 0 && await provider.available()) {
    modelUsed = true;
    let proposals: unknown = [];
    try { proposals = await provider.propose(buildModelPrompt(fetched)); } catch { proposals = []; }
    const v = validateModelProposals(proposals, fetched, ctx);
    modelRejected = v.rejected;
    const seen = new Set(claims.map((c) => c.id));
    for (const c of v.accepted) if (!seen.has(c.id)) claims.push(c);
  }
  return { regionID, fetched: fetched.map((f) => f.sourceID), failed, claims, modelUsed, modelRejected };
}
