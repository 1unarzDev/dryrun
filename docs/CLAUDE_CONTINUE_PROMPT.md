# Copy into the existing Claude session on the Mac

Continue working in this existing DryRun checkout. The owner wants you to own the next implementation,
visual-design and verification pass, including improving the PDFs. Do not treat Codex's work as completion.

First read **docs/goals/2026-10-17-family-preparedness.md completely**. It preserves the owner's original
`/goal` prompt verbatim and is the acceptance brief. Also read current instructions, uncommitted changes,
CLAUDE_NATIVE_HANDOFF, VERIFICATION, REVISION_EVIDENCE, UI_AUDIT, ARCHITECTURE, MAPKIT_SCAN_INTEGRATION,
SAFETY_AND_CONTENT and DEVICE_CHECKLIST. The current branch is authoritative: inspect divergence and preserve
newer/local Mac work before integrating origin/main. The owner authorized commit/push and says a connected
LiDAR-capable iPhone Pro and Xcode signing account will be available. Publishing/submission, outreach and
private-home uploads are not authorized.

Understand the product before judging the implementation: help a family answer **What should we prepare next?
What would we do in our home? Where is our plan when we need it?** The connected journey is household → home
and two meeting places → short scenario → resolve a real gap → share/print the updated plan. A household
without a scan, address, equipment or full profile must still receive useful preparations and a basic card.
Preserve a clearly fictional exploration path. Keep only Prepare, Rehearse and Plan as top-level destinations.

Audit every original requirement against current code and behavior. Codex's tests, documentation and adapters
are evidence to inspect, not proof of a working end-to-end product. Find omissions, regressions and awkward
interactions; implement the missing work. Do not merely mark existing files or reported test counts complete.

Use **ideators** before committing to visual changes. Use the Mac session's available ideator agents/workflows;
if there is no named tool, assign explicit short ideation roles and report that honestly. Have them consider
(1) family-card/full-plan visual communication, (2) the shortest connected preparation journey, and
(3) spatial-rehearsal/map clarity. Keep this bounded, choose a coherent direction, then build it. Use an
independent reviewer to inspect actual screenshots/PDF pages and navigation after integration. Avoid parallel
edits to shared models, AppModel, persistence and navigation without explicit ownership.

The owner specifically wants **strong, clean visual PDFs**, and wants you to improve them rather than treating
the portable references as final design. Inspect output/pdf as interim fictional references only. Build a
visually coherent phone preview and native Letter/A4 exports with:

- A concise family card: prominent person-associated critical information, readable contacts, two distinct
  meetups and review/missing-information states. Use sensible typography, spacing and deliberate page breaks.
- A useful neighborhood map with home and numbered meetup/resource markers, matching textual details,
  a separate extent for distant places and Apple's required attribution. Draw intended annotations at snapshot
  coordinates. Keep geographic and indoor coordinate systems in separate coordinated panels.
- Clean home diagrams with room/floor labels, real opening gaps, exits, shelter/refuge and selected useful
  equipment/supply icons. Preserve exact canonical route legs, subject/stage qualifications and no-route states.
- A restrained, consistent icon vocabulary (native symbols where appropriate), clear legends and hierarchy,
  readable grayscale/large-family/long-note output. No decorative clutter or tiny type to force one page.
- The same intentionally selected content in preview, Share and Print; no hidden sensitive fields/geometry.
  Missing/partial map imagery must leave a useful text-and-home plan with a truthful image-status notice.

Review the rehearsal changes critically. Inspect **the running UI**, not only source. Rehearse starts with the
home visible and offers one understandable decision at a time. Make the fire, flood and tornado scenes feel
complete and visually coherent across multiple home configurations, while all six hazards remain available.
Use the shared deterministic stage/subject state for 2D, 3D, text, route selection, comparison and export.
Make origin, occupants, smoke/water/window exposure, affected connections, current route/shelter and changed
consequences legible. Historical or invalidated paths must not look available. Verify unknown starts,
exposed starts, blocked exits, unsuitable windows, missing stairs and inaccessible shelters honestly. Review
Codex's changes for safety and correctness; do not assume the example ranch proves other layouts work.

"Full map simulations" means strong, connected native maps and illustrative spatial exercise scenes, not
fabricated live disaster overlays or predicted safe routes. Visuals never decide route validity. Preserve
conservative routing, explicit exercise assumptions, provenance, no survival score/countdown or clinical
interruption limits, and static equivalents for Reduce Motion.

Make the app **frictionless without bloated features**. Walk every journey from a fresh install. Find overly
nested sheets, wizard resets, excessive questions, duplicate selectors, stale secondary labels, hidden actions
and unnecessary confirmations. Reuse compact focused editors; important tasks should reach their relevant
form within one transition of the tab root. Save must return to the initiating task and close only its actual
gap. Keep draft/error/Undo behavior. Do not add accounts, family invitations, new top-level tabs, a shopping
catalog, a medical-record system, CAD tools or a live disaster command center. Remove friction through better
structure and sensible existing-data defaults rather than adding settings and screens.

Continue through implementation and native verification. Start with the current SDK failures in VERIFICATION,
run scripts/mac/verify.sh, fix failures, inspect new EN/ES/VI screenshots and native PDFs, and exercise a small
phone/large text/VoiceOver/Reduce Motion. Use scripts/mac/screens.sh for targeted review. iOS18, Swift6 strict
concurrency, encrypted local storage, migration/recovery, public-data allowlists and the deterministic engine
remain requirements. Never disable a failing check to obtain a green run.

With the connected iPhone Pro, install using scripts/mac/device.sh (see signing instructions), then actually
scan connected rooms, process/review/correct openings and levels, assign residents, save/relaunch, rehearse and
export. Test cancel/retry/interruption/late callbacks/repeated Finish and manual fallback. Record model, iOS,
Xcode/SDK, commit, exact paths, errors and limitations. Keep private real-home scans and medical data local;
use fictional/anonymized evidence for sharing.

Commit and push the resulting integrated work. Finish with a compact **requirement → implemented behavior →
files → actual validation → remaining human/hardware check** table, linked screenshots/PDFs and exact install
steps. A successful compiler pass is not usability, safe geometry, physical scan, complete localization or
system Share/Print proof. Report what remains incomplete candidly; do not claim full completion from adapters,
portable reference PDFs or historical results. No participants, feedback or professional endorsement may be
invented. Continue toward the owner's complete original goal rather than merely reviewing the latest diff.
