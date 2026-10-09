// Deterministic public brief for a region. Works with no model at all. Unknown stays "unknown".
import type { AlertsEnvelopeT, RegionInfoT, RegionPackT } from "../schema";
import type { FloodContext } from "../fema";

const STALE_MS = 30 * 60 * 1000;

export interface RegionBrief {
  regionID: string;
  name: string;
  generatedBy: "template";
  generatedAt: string;
  coverage: { status: RegionInfoT["coverage"]; note: string | null };
  emergencyOffice: { name: string; phone: string | null; url: string | null; sourceIDs: string[]; reviewState: string } | null;
  alertEnrollment: { status: "officialPageMentionsSignUp" | "unknown"; url: string | null; sourceIDs: string[] };
  officialAlerts: { status: "current" | "noneCurrentInLastFetch" | "unavailable"; count: number; fetchedAt: string | null };
  floodMap: { status: FloodContext["coverage"]; classification: FloodContext["classification"]; mapDate: string | null; note: string };
  siteActivation: { status: "confirmed" | "unknown"; note: string };
  statewideHelp: Array<{ name: string; phone: string | null; note: string | null; sourceIDs: string[] }>;
}

export function buildRegionBrief(info: RegionInfoT, pack: RegionPackT, statewide: RegionPackT | undefined,
  alerts: AlertsEnvelopeT | undefined, flood: FloodContext, now: Date): RegionBrief {
  const mine = pack.resources.filter((r) => r.regionIDs.includes(info.id));
  const office = mine.find((r) => r.serviceType === "emergencyManagement");
  const signUp = mine.find((r) => r.serviceType === "alertEnrollment")
    ?? (office && /sign[- ]?up|alert/i.test(office.summary) ? office : undefined);
  let officialAlerts: RegionBrief["officialAlerts"] = { status: "unavailable", count: 0, fetchedAt: null };
  if (alerts && alerts.status === "ok") {
    const fetched = Date.parse(alerts.fetchedAt);
    const current = alerts.alerts.filter((a) => {
      const ends = [a.ends, a.expires].filter((x): x is string => !!x).map(Date.parse).filter((n) => !Number.isNaN(n));
      return a.classification === "live" && ends.length > 0 && now.getTime() < Math.min(...ends);
    });
    officialAlerts = now.getTime() - fetched > STALE_MS
      ? { status: "unavailable", count: 0, fetchedAt: alerts.fetchedAt }
      : { status: current.length > 0 ? "current" : "noneCurrentInLastFetch", count: current.length, fetchedAt: alerts.fetchedAt };
  }
  const confirmedSite = mine.some((r) => ["shelter", "warmingCenter", "coolingCenter"].includes(r.serviceType)
    && r.activation === "active" && r.sourceIDs.length > 0 && (r.classification === "live" || r.classification === "curated")
    && !!r.expiresAt && now.getTime() < Date.parse(r.expiresAt));
  return {
    regionID: info.id,
    name: info.name,
    generatedBy: "template",
    generatedAt: now.toISOString(),
    coverage: { status: info.coverage, note: info.coverageNote ?? null },
    emergencyOffice: office ? { name: office.name, phone: office.contact.phone ?? null, url: office.contact.url ?? null,
      sourceIDs: office.sourceIDs, reviewState: office.reviewState } : null,
    alertEnrollment: signUp ? { status: "officialPageMentionsSignUp", url: signUp.contact.url ?? null, sourceIDs: signUp.sourceIDs }
                            : { status: "unknown", url: null, sourceIDs: [] },
    officialAlerts,
    floodMap: { status: flood.coverage, classification: flood.classification, mapDate: flood.mapDate, note: flood.note },
    siteActivation: confirmedSite
      ? { status: "confirmed", note: "An official source confirms an open site; check its listed expiry." }
      : { status: "unknown", note: "No official source confirms an open shelter, warming, or cooling site. Unknown does not mean closed." },
    statewideHelp: (statewide?.resources ?? []).filter((r) => ["assistanceLine", "assistanceRegistry", "disasterAssistance"].includes(r.serviceType))
      .map((r) => ({ name: r.name, phone: r.contact.phone ?? null, note: r.contact.phoneNote ?? null, sourceIDs: r.sourceIDs })),
  };
}
