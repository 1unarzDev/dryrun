// Regional public-information agent (brief §13). PUBLIC DATA ONLY: inputs are allowlisted source IDs and
// region IDs. There is no parameter through which household data could enter.

export type ClaimType = "phone" | "url" | "date" | "ugc" | "summary";

export interface PublicClaim {
  id: string;
  claimType: ClaimType;
  /** For deterministic claims: the exact text found in the source. */
  value: string;
  sourceID: string;
  regionID: string | null;
  jurisdiction: string | null;
  retrievedAt: string;
  sourceIssuedAt?: string;
  uncertainty: "verbatimExtracted" | "modelSummarizedVerbatimChecked";
  /** Never auto-promoted. A person must review before anything becomes trusted content. */
  reviewState: "needsReview";
  generatedBy: "deterministic" | "model";
}

/** Fetched official text. It is DATA: never instructions, never able to change tools or prompts. */
export interface FetchedSource {
  sourceID: string;
  url: string;
  retrievedAt: string;
  text: string;
  truncated: boolean;
}
