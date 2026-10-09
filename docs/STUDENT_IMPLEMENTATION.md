# Substantive work the student can own

Each item is a real technical contribution with its own tests and a clear "explain it" component for judges.
Pick 2–3 and do them fully rather than touching all of them. Record the work in `AI_ASSISTANCE.md` honestly
(if you use AI help, say where).

1. **Compile, run, and fix the iOS app on a Mac** (prerequisite for everything below).
   `cd apps/ios && xcodegen && open DryRun.xcodeproj`. Fix compile errors in the authored-only native code,
   run the UI journeys in `DryRunUITests`, and record results in `VERIFICATION.md`. You will learn the app's
   structure quickly by fixing it. *Explain:* AppModel's run-ID gate and why a late result must be discarded.

2. **Home-graph extraction from your own scans.** Scan a room at home (or a friend's, with permission) on a
   LiDAR iPhone. Compare the `ScanImport` proposal with tape measurements; tune `GeometryTolerance` and the
   adjacency rules; add regression fixtures from *anonymized* geometry (no photos, no addresses).
   *Explain:* why a scanned door is "proposed" until confirmed, and why windows are never exits.

3. **Alternate-route independence.** Today an alternative must use a different exit and avoid the primary route's
   chokepoints. Implement and test a stronger definition (e.g. node-disjoint paths via max-flow / Suurballe),
   and show a case where the current rule and yours differ. *Explain:* why two routes sharing one hallway are not
   two ways out.

4. **An accessibility scenario and tests.** For a wheelchair user on an upper floor or in an apartment with an
   unverified common stair: model helper assignment, step-free requirements, and the typed `incompatibleMobility`
   result end to end; add plan text that never instructs a helper to re-enter a fire.

5. **Transparent ranking method.** Write down the tier rules and tie-breaks as a spec, build a small table-driven
   test suite from it, and justify each ordering decision with sources. *Explain:* why cheap actions never outrank
   a critical dependency.

6. **Region-pack ingestion and a verified local pack.** Own `PublicPackStore` ingestion end to end: signature or
   hash manifest design, freshness/expiry handling, and a verified county pack you check by phone/website yourself
   (with dates). *Explain:* why a hash alone does not prove who wrote a pack.

7. **Private-data-flow audit.** Trace every path that household data can take (vault, PDF export, share sheet,
   logs, app switcher, network). Write the audit, then fix what you find with tests.

Minimum bar for "significant contribution": you can open any file you claim, explain what it does and why,
change it, and show a test you wrote that would fail without your change.
