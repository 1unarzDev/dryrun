# AI assistance ledger

**Honest summary:** this first-review build was produced almost entirely by AI agents on 2026-10-09. No student
code is in it yet. Under the 2026 Congressional App Challenge rules (AI support must be disclosed, students must make
significant contributions and understand the technology, and AI may not constitute all technical development [S01]),
this build is an **AI-assisted reference prototype and foundation, not a submission**. The student's own
implementation work must be added and documented (see `STUDENT_IMPLEMENTATION.md`) before the national deadline,
**October 26, 2026, 12:00 p.m. Eastern / 11:00 a.m. Central**.

## Agents and models

| Role | Model / tool | Scope |
|---|---|---|
| Lead (integration) | Claude Opus 5.5 in Claude Code (CLI), Linux host | Contracts, core models, content library, localizer, plan builder/validator, rehearsal cursor and stale-result gate, iOS app shell (all tabs, AppModel, PDF renderer, settings, help, onboarding), vault bridge, XcodeGen spec, English plan/common text, docs |
| Agent A (simulation) | Claude Opus 5.5 (forked sub-agent) | Scenario schema and six packs, dependency model, backup allocation, hazard rules, rehearsal engine, interventions, counterfactual compare, action catalog, ranking, English scenario/action text, simulation tests |
| Agent B (spatial) | Claude Opus 5.5 (forked sub-agent) | Geometry, sample homes, home validator, egress planner, route cache, scan import, iOS RoomPlan/2D/3D/editor views, spatial tests |
| Agent C (privacy & public data) | Claude Opus 5.5 (forked sub-agent) | DryRunVault package, public-data policy, source manifest, region packs, backend (Hono/Zod/Vitest), ES/VI draft translations, iOS Keychain/file-protection/public-API adapters, privacy tests |

Each lane was also adversarially reviewed by a different agent (see `docs/lanes/review-*.md`). Those reviews found
real defects, which were fixed and turned into regression tests.

A human (the owner) wrote the product/engineering brief that defined requirements. The agents made the routine
engineering decisions recorded in `DECISIONS.md` and `docs/lanes/*.md`.

## Integration pass (2026-10-16)

| Role | Model / tool | Scope |
|---|---|---|
| Codex integration agent | GPT-6-based Codex, Linux checkout | Integrated the MapKit planning journey, public geographic contracts and resource precedence, private saved places and vault migration, RoomPlan lifecycle/review repairs, transactional home persistence, portable verification, and integration documentation |
| Existing map lane | AI sub-agent | Native map/list/search/directions/location adapters, public resource and content changes, map provenance |
| Existing RoomPlan lane | AI sub-agent | RoomPlan callback lifecycle, confirmation controls, geometry triangulation, scan fixtures |

This pass did not have access to Xcode, an iOS SDK, a simulator, or a physical LiDAR phone. The exact portable test
results and those unverified platform limits are recorded in `docs/VERIFICATION.md`; no screenshots or private-home
data were created.

## Materially AI-generated

Everything under `apps/`, `packages/`, `services/`, `content/`, `fixtures/`, `scripts/`, and `docs/` (except the
owner's brief PDF in `docs/`). Specifically AI-written content that needs human review before anyone relies on it:

- **Safety text** in `content/locales/en/*.json` and scenario packs (paraphrased from cited CDC/NWS/USFA/FDA pages).
- **Spanish and Vietnamese translations** in `content/locales/{es,vi}` — machine/AI drafts, all marked `draft`.
- **Regional directory entries** in `content/regions` — see `docs/lanes/agent-c.md` for which were checked against
  official pages and when.

## Not AI-generated / not done

- No real household data was used. All people, homes, and phone numbers (555-01xx) are fictional.
- No student code, student testing, device testing, or human review has happened yet.

## How to keep this ledger accurate going forward

For every later change, record: who (student / AI tool + model), which files, what was generated vs. written,
and what the student verified or tested themselves. Do not relabel AI-written code as student work.

## Family-preparedness revision (2026-10-17)

Codex (GPT-6-based agent, Linux) integrated optional layout/vault migration, three-destination navigation,
transactional persistence, private boundaries, task/plan contracts, tests, evidence and Mac handoff. Parallel
AI lanes owned core/preparation/family card; maps/plan/export; scan/rehearsal/spatial behavior. Each lane independently
source-reviewed another lane. Findings included stale form writes, hidden geometry in card exports, unsupported
meeting-task blank screens, closed-attic refuge and scan processing interruption. Source-review findings led to
implementation changes; source review is not native screenshot/device verification.

EN/ES/VI additions and fictional test/reference artifacts are AI-generated drafts. Portable PDF examples use a
ReportLab reference renderer of actual Core PlanDocument JSON, not the iOS CoreText renderer. Exact current test
results and limits are in VERIFICATION. No native SDK build, simulator/device run, measured household usability,
professional clinical/fire review or human translation review occurred in this pass. A Claude session on the
owner's Mac is expected to continue native verification via CLAUDE_NATIVE_HANDOFF. Do not attribute future results
until that session supplies them. No student contribution, recruitment, partner feedback or endorsement is implied.


October 17 follow-up (same Linux Codex integration, with independent AI preparation/spatial/maps source reviews):
added constrained geometry correction/provenance and explicit levels/stairs; fixed independent-wall preservation,
shared current shelter validation, maintenance/physical-check invalidation, separate solo/joint review and optional
one-time reminder cancellation/deletion. Added tests and EN/ES/VI draft controls. The vault incremental build's stale
binary failure was reproduced, then cleared by rebuilding without source changes; fresh suites provide the reported
evidence. Native reminder tests are authored only. No current simulator/device screenshots or professional review
were produced; remaining native work is handed to the owner's existing Claude/Mac checkout.

Additional October 17 connected-flow review (same Codex/AI lanes) fixed focused task ownership, canonical
supply/location continuity, subject-specific medical supplies, utility/drill/flood/well completion, selected-export
failure/privacy, route/GPS cancellation, card coordinate/role output, explicit public coverage, scene-floor/exit
presentation, retained scan review and localized subject/quantity labels. Core comparison diffs retain subjects.
The PDF skill was used for regenerated fictional reference artifacts and visual/text inspection. Current counts
are recorded in VERIFICATION; no current native, simulator, physical test or human review was performed.

Final portable PDF review moved oversized responder instructions after the main contact/meetup card, retaining
all user-authored text and explicit export selection. The regenerated long-note Letter/A4 first/continuation/end
pages were inspected; output/README.md records exact pages and limits. This did not execute native PDF rendering.

Selected-language closure (Codex on Linux, with the same preparation/maps/scan AI lanes): localized Help, scan/rehearsal presentation, default marker/enum values, plan validation/dates/decimals and composed-card translation/source provenance. Root added complete-pack selection and shared country-aware map/water presentation, kept engine data unchanged, corrected local emergency-service wording and recorded an accessible official Canadian source. An independent AI source review inspected this follow-up. New core tests, seven Linux app-helper checks and regenerated fictional reference renders provide portable evidence only. ES/VI remain AI drafts; no human translation, safety, simulator/device or native export result is implied.

The independent follow-up source review found four further issues and fixes: empty default event subjects now resolve by longest exact evidence ID (including dotted IDs), mixed power/cold-storage card wording no longer denies electrical requirements, composed water-unit fallbacks reach document provenance, and official English alert text has a fallback label. Core regressions cover subject/default/custom-name retention, route reasons, unit fallback and mixed card sections; native interaction remains pending.

Connected-state closure (Codex, Linux; the same independent preparation/maps/spatial AI lanes) added optional-layout
rehearsals, lineage-safe room assignments, person-scoped window escape, canonical helper reach, frozen RoomPlan
processing generations, distinct local-leak content, shared medical/alarm/transport readiness, recorded factual
progress, source-resource actions/provenance and canonical current-state plan panels. Root integrated selected
preview/export transactions and practiced-input reuse, migration/linkage, schema/engine versions and EN/ES/VI
content. Independent review found migration canvas-edit/localization regressions; fixes and tests were integrated.
Reference PDF visual inspection caught furniture covering room names; label order was corrected in reference
and native renderer source. Exact final evidence is in VERIFICATION; native output has not been executed.
Human translation/safety review and all physical/simulator results remain pending. No participant or endorsement
is invented. All user-authored audit/handoff files remain outside the commit.

Hosted-native continuation (same Codex agent): discovered and manually ran the repository's existing GitHub
macOS verification workflow for dbac954. Native package/backend checks passed; actual app compilation exposed
the private NSCoding delegate's unstable Objective-C name. Added an explicit runtime class name, retained all
generation guards, and prepared a rerun. Also corrected portable tabular-status parsing and updated stale county/
equipment-only backlog and Mac instructions. Exact run/environment/failures are in VERIFICATION. No simulator
journey or physical capture result is implied by this failed build.
