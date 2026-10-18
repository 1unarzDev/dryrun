# Frontend handoff

Current direction (October 17): **Prepare, Rehearse, Plan**, focused factual editors, universal family card and optional home geometry. Native build, simulator and physical-device verification of this revision are pending; see CLAUDE_NATIVE_HANDOFF and REVISION_EVIDENCE. Historical October 14 screenshots do not verify changed flows. Older guidance below is subordinate to the current revision brief and architecture.

## 1. The UI is a thin client over a tested core

All behavior lives in `packages/DryRunCore` (Foundation-only; current counts in VERIFICATION). Views should render core results and call
`AppModel` intents. They should never compute safety logic, routes, priorities, or text themselves. If a design needs
new information, add it to the core result with a test, then render it.

**`AppModel`** (`apps/ios/DryRun/App/AppModel.swift`, `@MainActor @Observable`) is the only state the views use:

| State | Meaning |
|---|---|
| `phase` | `.loading / .onboarding / .ready / .vaultLocked / .vaultNeedsRecovery / .contentFailed`. Each needs a designed screen; locked and recovery must never look like an empty fresh start. |
| `household`, `home` | The current private data. Home may be intentionally absent. Facts bump revisions; live previews update and old saved scenario output is retained as labeled stale history. |
| `rehearsal: RehearsalCursor?` | The step-through cursor: `visibleEvents`, `currentMinute`, `pendingDecision`, `snapshotAtCursor`, `isFinished`. |
| `comparison: RehearsalComparison?` | "Try this change" result: baseline, modified, and a structured `diff`. |
| `savedPlan`, `planIsStale` | The localized `PlanDocument`. |
| `locale`, `localizer` | All user-visible text. |
| `capabilities.plan` | `CapabilityPlan`: which flows to offer (scan / camera denied / unsupported; live or cached alerts; model or templates). |
| `isWorking`, `lastError` | Progress; a generic error alert (raw errors are never shown, since they contain paths). |

**Intents:**
- `startRehearsal`, `choose(option:at:)`, `tryChange`
- `markPreparationCompleted` (a real-world record, kept separate from tried changes)
- `generatePlan`, `updateHousehold`, `updateHome`, `deleteAllPrivateData`

Async results are applied only if they still match the latest request, household and home revision, and locale
(`LatestRequestGate`). Keep that pattern for any new async work.

## 2. Data shapes the UI renders

| Screen | Core type | Key fields for design |
|---|---|---|
| Timeline event | `SimulationEvent` | `simMinute` (the exercise clock, not wall time), `severity` (info / caution / critical), `titleKey`/`detailKey` + `templateValues`, `serviceChanges`, `evidence` (rule, facts, causes, sources) |
| Service panel | `SimulationSnapshot` | `services` (operational / degraded / unavailable / unknown), `resources` (amount may be `nil` = unknown), `unmetRequirements` |
| Decision card | `DecisionPoint` | `promptKey`; options with `labelKey`, `feedbackKey`, `isRecommended` (unsafe options exist and are never rewarded) |
| Debrief cards | `Recommendation` | `tier` 1–5 (already ordered), `titleKey`, `whyKey`, `modeledEffectKey`, `effort` (noCost / low / moderate / high), `unconfirmed`, `feasibilityNotes`, `sourceIDs`, optional `tryIntervention` |
| Before/after | `RehearsalDiff` | `serviceChanges` [before, after], `resourceChanges`, `resolvedRequirements`, `newRequirements`, `added/removedEventIDs` |
| Routes | `RouteResult` | `primary` / `alternative` `RoutePath` (per-floor `legs` of metric points), `alternativeStatus` (independent / sharesChokepoint / none), typed `noRouteReason`, `request.exclusions` (usual routes vs. blocked-scenario routes), per person and mobility |
| Home | `HomeModel` | Metric 2D polygons per floor, `Floor.toCommon` transform, portal `verification` (verified / proposed / unknown / rejected), annotations (exits, meeting point, alarms, shelter spot, hydrant as context only) |
| Confirmation | `HomeConfirmation.steps` / `apply` | One question at a time; "Not sure" leaves an item unknown and out of routes |
| Plan | `PlanDocument` | pages → sections → lines with `style` (normal / prohibition / contact / caveat), `isFallback`, `isDraftTranslation`; document banners |
| Help | `PublicResource`, `PublicDataPolicy` | `activationDisplay` (confirmed active / inactive / unconfirmed / not applicable), alert `freshness` (current / stale / expired / demo); phone numbers always shown as text |

## 3. Rules the design must keep (product honesty and safety)

These are product requirements, not styling preferences:

1. A persistent **"Practice scenario"** label. Show the simulated clock ("+3h 00m") separately from any real
   timestamp. No countdowns, survival scores, readiness percentages, or celebratory "you survived" moments.
2. **Never reward unsafe options visually**, for example by styling the "use the oven" option as a correct answer.
   Decision feedback text is authored and must be shown as is.
3. Routes are **"practice routes under these assumptions."** Draw only the canonical route points; no smoothed
   shortcuts through walls. When there is no route, show the typed reason rather than hiding the section.
4. **Unknown is its own state.** It is never shown as "no," "0," "closed," or "open." It needs a distinct, non-color
   cue, because status uses icon + text + color, never color alone.
5. **"Try this change" vs "Mark preparation completed"** must look and read differently. One is hypothetical; the
   other is a real-world record.
6. **Draft and fallback labeling** must stay visible in ES/VI. Keep the exact English phrase "Draft translation -
   language review pending" and the [EN] markers on fallback lines.
7. **No auto-calling and no alarm audio.** Phone and web actions are explicit taps; phone numbers are also shown as
   text.
8. **A map pin is not an open shelter.** Show activation only from `activationDisplay`.
9. **Privacy surfaces:**
   - The privacy shield window covers sheets in the app switcher.
   - Plaintext PDFs exist only during preview, share, or print.
   - Show the sharing boundary text where users share.
   - Never put household data in widgets, notifications, Spotlight, or Live Activities.

## 4. Localization: how to add or change text

- All text goes through `model.localizer("key", ["placeholder": value])`. Keys live in
  `content/locales/<en|es|vi>/<domain>.json`; domains are common, plan, help, scenarios, actions.
- To add a string, add the English key, then the ES/VI drafts. Record baselines with
  `node services/public-api/scripts/record-translation-baseline.mjs es vi`; Vitest fails when English changes after
  a translation was recorded.
- Placeholders must match across locales (a core test enforces this). Format numbers and units in code, not in
  translated prose.
- **Remaining hard-coded English: about 210 strings.** The most visible ones are onboarding and household setup (39),
  the manual home editor (38), confirmation (25), Home tab (19), Settings (19), the RoomPlan flow (18), and Help
  service-type names (13). `ServiceNames` and the "why did this happen" fact and rule IDs are also English or raw.
  This is the biggest localization task for the frontend pass.
- Design for text expansion: Vietnamese and Spanish run noticeably longer than English. Test with the `vi` and `es`
  previews and screenshots, and at the largest Dynamic Type size.

## 5. Current structure and visual starting point

- Four tabs: **Rehearse · Home · Plan · Help**. Settings is a toolbar sheet.
- Sheets: Debrief, Before/After, PDF preview, Confirmation, the household setup wizard (pushed), and RoomPlan
  (full screen).
- Rehearse uses a `NavigationStack(path:)`, which demo launches use to deep-link.
- `Theme` (`DryRunApp.swift`) uses a warm neutral background, teal accent, and amber/red status colors, with symbol
  and color helpers per `ServiceState`/`EventSeverity`. These are placeholder tokens to replace in the design pass.
- Spatial views (`apps/ios/DryRun/Spatial`) take plain inputs, not `AppModel`:
  - `FloorPlanView(home:routes:highlightedFloorID:)` draws with a Canvas.
  - `DollhouseView(home:routes:floorID:)` uses RealityKit: simple solids with cutaway walls, `Floor.toCommon`
    applied, and a scene cache keyed by content. Pause it offscreen and offer 2D as the low-power default.
  - `HomeRoomListView` is the accessible room list, a first-class view and not an afterthought.
- **Accessibility identifiers are a test contract:**
  - `onboarding.sample.<householdID>`, `scenario.<scenarioID>`
  - `rehearsal.next`, `rehearsal.debrief`, `decision.option.<optionID>`
  - `plan.generate`, `plan.viewSaved`

  Keep them stable when restyling, or update `DryRunUITests` in the same change.

## 6. Biggest UX gaps (good first frontend targets)

1. Raw identifiers and English-only names:
   - **Still raw:** the timeline's "Why did this happen?" (`EventCard`) prints rule, fact, cause-event, and source IDs.
   - **Fixed after the first simulator run:** service rows, the debrief's "Still unconfirmed", recommendation
     "Based on", picker labels, and home issues now use readable names (`ServiceNames`, `UnknownNames`,
     `HouseholdLabels`, `DisplayNames`, `HomeValidator.describe`).
   - **Still English-only:** those readable names are hard-coded, so ES/VI screens show them in English. Move them
     into the locale packs.
2. The rehearsal screen is a plain card list. The brief asks for one focused timeline/home view; the home canvas plus
   event annotations is the open design question.
3. Before/after is a text list. Make the cascade difference visible: the device stays powered, an event disappears.
4. The fire timeline prints "helper assigned" before a later "helper blocked" event (core ordering, BACKLOG #18).
5. Onboarding and setup are long forms. Progressive disclosure exists but is visually plain.
6. Nothing has been checked on a device for Dynamic Type, VoiceOver order, Reduce Motion or Transparency, or contrast.

## 7. Preview and test loop for the design pass

| Where | How |
|---|---|
| Xcode canvas | `App/Previews.swift`: 9 deterministic previews (rehearsal mid and end, debrief, home, plan EN/ES/VI, help) |
| Simulator screenshots | `scripts/mac/screens.sh --locales en,vi --screens fire,plan --open` |
| Phone | `scripts/mac/device.sh -- -demoHousehold hh-lake -demoLocale vi -demoTab plan -demoPlan all` (any screen or state; see `DemoLaunch.swift`) |
| External Mac from Linux | `scripts/remote-mac.sh you@mac screens --locales en` (artifacts are copied back here for review) |
| Cloud Mac | GitHub Actions **iOS verify** (manual trigger, simulator only) |

The tour exports PNGs plus accessibility-tree dumps per screen. I can review those from here without a Mac.
