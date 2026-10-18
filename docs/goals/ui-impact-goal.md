# Historical goal — Goal: Dry Run — Congressional App Challenge build (UI redesign + 3 impact features)

Superseded by the October 17 family-preparedness revision. Retained as historical context; see REVISION_EVIDENCE and CLAUDE_NATIVE_HANDOFF for current work.

## Mission
Make Dry Run the app a family with a medically dependent member opens once and walks away from with a working
power-outage plan. The judge's question is "who does this help, and does it work?" Answer it on screen in the first
60 seconds, in the household's language, without anyone getting stuck or tapping a button that does nothing.

**Primary user:** a Texas household where someone depends on powered medical equipment or refrigerated medication
(oxygen concentrator, CPAP/BiPAP, power wheelchair, insulin), often with an older relative, and sometimes most
comfortable in Spanish or Vietnamese. In a freeze or grid failure their risk is not discomfort but losing breathing
support or medication within hours. The Oak household (`hh-oak`) is the demo family.

## Non-negotiable constraints (read `docs/FRONTEND_HANDOFF.md` §3 first)
- **Honesty rules stay:**
  - No readiness score, percentage, countdown, streak, or "you survived" moment.
  - Progress is a list of concrete items: done, still to do, or unknown.
  - Unknown is its own state (icon + text, never color alone).
  - "Try this change" (hypothetical) and "Mark preparation completed" (real) must look and read differently.
- **Safety logic stays in `packages/DryRunCore` with tests.** Views render core results and call `AppModel`
  intents. New information is added to the core with a test first, then rendered.
- **No new medical claims.**
  - Never estimate how long someone is safe without power.
  - Runtimes come only from what the household recorded ("documented by the manufacturer or care plan").
  - Every new safety line cites an existing source ID or is clearly marked as a household-entered fact.
- **Every new user-visible string goes through the localizer**, in `content/locales/{en,es,vi}`:
  - Add ES/VI drafts for each new key.
  - Keep the draft-translation banner.
  - Re-record the baselines with `node services/public-api/scripts/record-translation-baseline.mjs es vi`.
- **Privacy:**
  - Household data stays on device and never goes into notifications, widgets, Spotlight, or Live Activities.
  - Sharing is always an explicit tap that shows the sharing-boundary text first.
- **Accessibility:** VoiceOver labels on every control, Dynamic Type up to XXL without clipping, 44 pt tap targets,
  and contrast at WCAG AA.

## Part 1 — UI redesign (every existing screen)
1. **Design system.** Create `App/Theme.swift` with tokens for color, type scale, spacing, corner radius, and status
   styles. Build reusable components: `StatusPill`, `SectionCard`, `PrimaryButton`, `SecondaryButton`, `EmptyState`.
   Use them on every screen, keep the look calm and high-contrast, and support dark mode.
2. **Onboarding.** Two paths, each one tap:
   - "See how it works": the Oak household, landing directly in the freeze rehearsal.
   - "Set up my household": replaces the long form with a short guided setup, one question per screen with a
     progress indicator (step 3 of 6, not a percentage). The order is: people, medical equipment, backup power,
     heat/water, contacts, language. Every question has a "Not sure" answer.
3. **Rehearsal screen.**
   - Replace the ~20-row status wall with the 3–5 services that changed at this step, plus "Show all".
   - Make the current event the hero card.
   - Show the decision as large option buttons and the timeline as a compact list.
4. **Debrief.** Lead with the top three preparations as cards with a clear primary action. Group "Unconfirmed facts"
   as questions the family can answer in place (this updates the household and re-runs).
5. **Home, Plan, and Help.** Use consistent cards, and keep the floor plan readable at a glance. On the Plan tab,
   "Generate plan" becomes a single prominent action that shows what changed since the last plan. Help leads with 911
   and the household's own contacts.
6. **Button audit.** Every tappable element does something visible:
   - Sheets dismiss correctly, back navigation works, and nothing is a no-op.
   - Destructive actions confirm first.
   - Async actions show progress and a readable error.
   - Write the audit as a table in `docs/UI_AUDIT.md` (screen, control, result, verified-by).

## Part 2 — Three impact features
**A. "Next steps" home screen (new first tab).**
- Show the household's preparations ranked by the core (tiers from `RecommendationRanker`, merged across the
  scenarios they rehearsed), each as a card with one clear action:
  - "Call your supplier" (phone shown as text plus a tap to call)
  - "Record your backup's runtime"
  - "Try this change"
  - "Mark completed"
- Completed and unknown items are listed separately. There is no score.
- A short "Since your last rehearsal" line explains changes.
- Core work: a function that merges recommendations across results (with tests).

**B. Medical power-outage card.**
- One screen per essential device, readable in 15 seconds by a neighbor or a 911 dispatcher. It shows:
  - the device and who uses it
  - the confirmed compatible backup and its documented runtime ("unknown" if not recorded)
  - the supplier or care-team phone
  - the out-of-area contact
  - where to go if power is out long, which must be a destination the household confirmed and not an assumed shelter
  - 911 and 2-1-1 Texas
- Works offline in EN/ES/VI, can be printed or shared as a one-page PDF (via the existing renderer), and is
  reachable in two taps from launch.
- Core work: a `MedicalOutageCard` built from `HouseholdProfile`, with a validator test (no unfilled placeholders,
  no invented runtimes, private notes excluded unless chosen).

**C. Share the plan with family and caregivers.**
- A "Share with family" flow lets the user pick what to include (household plan, outage card, or both), see the
  sharing-boundary text and a preview, and then use the share sheet.
- A "Ready to share" checklist shows what is still unknown before sending.
- Plaintext files exist only for the duration of the share, as today.

## Verification (required before calling it done)
- `scripts/mac/verify.sh` passes all steps on the iOS simulator.
- Core tests cover every new core function, and backend tests (the translation baseline) pass.
- New UI tests:
  - Onboarding demo path to rehearsal in 3 taps or fewer.
  - Guided setup from start to finish with every answer "Not sure".
  - Next steps → mark completed → the item moves to Completed.
  - Outage card open → share PDF.
  - Every button from `docs/UI_AUDIT.md` exercised at least once across the suite.
- Add the new screens to the screenshot tour in EN/ES/VI, then inspect every image by eye: clipping, overlap, raw
  IDs or enum names, English text in ES/VI outside marked fallbacks.
- Run the accessibility pass on the simulator (Accessibility Inspector audit with no errors, Dynamic Type XXL
  screenshots of the main screens).
- Record the results in `docs/VERIFICATION.md`, and don't claim device-only behavior was tested.

## Demo deliverables (Congressional App Challenge)
- A `docs/DEMO_SCRIPT.md` for a 2–3 minute video, built around the Oak family:
  - the problem: a freeze cuts power to Grandpa's oxygen concentrator
  - the rehearsal shows the cascade
  - the debrief points to the backup
  - "Try this change" shows the before and after
  - the outage card is printed and shared with family
  - the same flow in Vietnamese
- Each beat names the exact launch arguments that open that screen.
- A one-paragraph impact statement grounded in cited sources already in `content/sources`, with no invented
  statistics.

## Order of work
1. Design system and button audit.
2. Rehearsal and debrief redesign.
3. Feature B (outage card), the strongest demo moment.
4. Feature A (next steps).
5. Guided setup.
6. Feature C (sharing).
7. Localization, accessibility, and the full verification run.
8. Demo script.

Commit after each step with passing tests. If something doesn't fit before the deadline, cut it from the end of
this list rather than shipping a half-working screen.
