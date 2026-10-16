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
