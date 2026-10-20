# /goal: Beacon demo for the Congressional App Challenge (deadline Mon Oct 26, 2026, 12:00 pm EDT)

Paste everything below the line as the `/goal` prompt.

---

Continue Dry Run on branch `dryrun-six-hazard-continue` (Mac, wired iPhone 16 Pro). Read first:
`docs/IMPACT_FRAMING.md` (the only allowed statistics), `docs/ai/wired-iphone-pass-2026-10-20.md` (current state and how
to drive the phone with `scripts/mac/device-test.sh`), and `DryRun_AI_Implementation_Reference.md` (guardrails).

**Mission for the demo (one sentence):** Dry Run is a family's disaster rehearsal coach for Tarrant County. Its AI,
**Beacon**, uses everything the household records (people, medical equipment, pets, supplies, LiDAR home scan) to
tailor what to buy, where to go and what to practice, before the next storm.

**Decisions already made by the owner (do not re-ask):**
- The AI is named **Beacon** in every user-facing string (EN/ES/VI). No "Gemini" in the UI. Remove the inline data-sent
  paragraph; keep one plain sentence in Settings → About ("Beacon uses Google Gemini; names, phone numbers and
  addresses are never sent"). Gemini stays disclosed in the video and written answers (Challenge rule).
- **Hosted backend + demo replay.** Deploy `services/ai-orchestrator` to a free cloud host with the key server-side.
  The app gets the gateway URL from a build setting, not launch arguments. A recorded Beacon session replays
  automatically when the provider fails (503/429/timeout), labelled as a replay in the debug build.
- **Shopping list uses curated price ranges**, not live web prices.
- **Hero features (all four):** live alert → do this now; LiDAR scan → tailored drill; accessible shelter map; smart
  shopping list.

**Guardrails (keep):** Core decides facts, priorities, scores and completion; Beacon may select, order and explain
within Core's constraints, and every Beacon output is validated in Core with a deterministic fallback. Never show a
green "safe", never claim wheelchair-optimized routes (MapKit has no such routing): show known accessibility
features with their source. Use only verified statistics. Keep the synthetic-only gate for AI requests unless the
owner explicitly approves real households (a hosted endpoint with a static token is not production authorization).

## Milestones (in order; each ends verified on the phone with screenshots inspected)

1. **Beacon everywhere, reliably (day 1).**
   - Rebrand the AI as Beacon.
   - Deploy the gateway to the hosted backend; add the replay fallback.
   - Make Beacon on by default for the demo household: Prepare's top 3 are tailored on open, the rehearsal director is
     Beacon, and the debrief has a Beacon summary.
   - Raise or configure `DRYRUN_MAX_USD` for the demo, and use a model with available capacity.
   - Acceptance: a fresh install on cellular shows Beacon output on Prepare within 20 s, or the replay.
2. **Live alert → "Do this now" (day 2).**
   - Fetch active National Weather Service alerts for Tarrant County (api.weather.gov; free, needs a User-Agent).
   - Map each alert type to the matching rehearsal: tornado warning, flash-flood warning, extreme heat, winter storm,
     and others.
   - Show a home-screen banner with three household-specific steps (from Core, explained by Beacon) and a
     "Rehearse this now" button.
   - Add a demo toggle that injects a recorded alert, so the video doesn't depend on the weather.
   - Acceptance: a UI test with the injected alert reaches the matching rehearsal.
3. **Smart shopping list (day 3).**
   - Core turns inventory gaps and baseline items into a buy list: item, quantity for this household (people,
     pets, device runtime), and a cost range from a reviewed table `content/prices/tarrant-v1.json` with a source
     and date.
   - Offer a "Budget" kit and a "Complete" kit, ranked by safety benefit per dollar; medical-dependency items first.
   - Beacon explains each item for this household.
   - Check items off; buying something updates inventory and the score.
   - Acceptance: Core tests for the quantities, ranking and budget limit.
4. **Accessible shelter and cooling map (day 4).**
   - MapKit map of the household's saved places, plus places from public sources:
     - FEMA open shelters (the public ArcGIS feature service; verify its fields and terms first);
     - a curated `content/places/tarrant-v1.json` of cooling/warming centers and libraries, each with its source and
       retrieval date.
   - Show step-free and accessibility notes only when the source states them. Flag "call to confirm medical power".
   - Route with MapKit (driving or walking), plus Beacon's household note ("Grandpa needs outlet access for oxygen").
   - Acceptance: a phone screenshot shows a route and source labels.
5. **LiDAR scan → tailored drill (day 5).**
   - Verify on the phone: RoomPlan scan, then confirm, save, relaunch, and run a fire rehearsal on the scanned home.
   - Beacon picks the setup (fire origin, starting rooms) from the household.
   - Fix whatever breaks. Record a clean scan for the video.
6. **Simplify for non-technical families (alongside 1–5).**
   - Home screen: the score as progress rings with the next 3 actions; celebrate progress.
   - Move caveats behind an ⓘ button; plain-language copy; at most 3 items before "Show all"; larger tap targets.
   - Get ES/VI reviewed by a native speaker if possible, and flag any string that wasn't.
7. **Submission kit (day 6).**
   - A 2:45 video script that meets the Challenge's required elements: names, app name, one-sentence purpose,
     audience, tools and languages, and the app working. Open with the Uri and emPOWER numbers from
     `IMPACT_FRAMING.md`.
   - Answers to the written questions.
   - An AI-use disclosure.
   - A screenshot set.

**Stop rule:** if a milestone isn't verified on the phone by the end of its day, ship what works behind a flag and move
on. Milestones 1, 2 and 7 are mandatory; 3–5 are ordered by value.

**Each milestone also needs:**
- Core/gateway tests.
- A phone journey in `apps/ios/DryRunUITests`.
- The full regression: Core, Vault, gateway plus TypeScript, public, and on the phone the unit tests,
  `SixHazardUITests` and `DeviceAuditUITests`.
- A commit and push as the owner (no Claude attribution lines).
- An update to `docs/ai/wired-iphone-pass-2026-10-20.md`.

**Needs the owner:**
- Pick a hosting account and log in: Google Cloud Run (free tier) or Render.
- Confirm the participating congressional district.
- Team member names for the video.
- A native ES/VI reviewer, if available.
