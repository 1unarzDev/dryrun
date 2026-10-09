// FEMA National Flood Hazard Layer context [S18], behind a provider interface.
// STATUS: live integration NOT implemented in this build. Only a clearly labelled fixture provider exists.
// Mapped flood hazard is planning context: never current depth at a home, never road safety.

export interface FloodContext {
  regionID: string;
  classification: "live" | "fixture";
  coverage: "mapped" | "partial" | "missing" | "unknown";
  mapStatus: "effective" | "preliminary" | "unknown";
  mapDate: string | null;
  note: string;
  sourceIDs: string[];
}

export interface FloodHazardProvider {
  context(regionID: string): Promise<FloodContext>;
}

export class FixtureFloodHazardProvider implements FloodHazardProvider {
  async context(regionID: string): Promise<FloodContext> {
    return {
      regionID,
      classification: "fixture",
      coverage: "unknown",
      mapStatus: "unknown",
      mapDate: null,
      note: "Fixture only: live FEMA NFHL lookup is not implemented in this build. Check FEMA's Flood Map Service Center. Flood maps show mapped hazard, not current flooding or safe roads.",
      sourceIDs: ["S18"],
    };
  }
}
