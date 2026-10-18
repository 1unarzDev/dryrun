# Remaining work — October 17 product revision

The current product is Prepare, Rehearse and Plan. General family preparation is useful without address,
geometry, medical equipment or rehearsal. County coverage is optional public content, not the organizing
principle. This backlog supersedes the older county-first and equipment-only priorities; historical decisions
remain in git history. Implemented behavior and actual evidence are mapped in REVISION_EVIDENCE and VERIFICATION.

## Required verification and fixes

1. **Installed-SDK native build and simulator integration.** Build the current SHA using
   `scripts/mac/verify.sh`, with the iOS 18 minimum. Fix compiler/API/concurrency errors and actual journey defects;
   do not replace failing gates with syntax parsing. Exercise a small iPhone, ordinary/large text, EN/ES/VI,
   VoiceOver, Reduce Motion, light/dark, and inspect new screenshots. See CLAUDE_NATIVE_HANDOFF.
2. **Real local persistence and selected exports.** Fresh real-vault install: skip address/scan, add an
   international contact, open/select/share/print the universal family card, force quit/relaunch. Verify protected
   key/file attributes, locked-device recovery, save failure/draft behavior and export leases through activity/
   Print background, cancellation and completion. In-memory UI tests alone do not satisfy this gate.
3. **Apple services with optional location.** Texas/other-US/non-US/rural/unresolved addresses, denied GPS,
   rapid changes/cancel/retry, ordinary directions origins/modes, map-snapshot failure, attribution and offline
   essentials. Both meetups and source records must persist through all entry points and update the next PDF.
4. **LiDAR-capable physical iPhone Pro.** Native connected-room scan, structure processing, measured mapping,
   grade/stair/exit correction, person assignment, save/relaunch, fire/flood/tornado rehearsal and export. Include
   interruption, late callbacks, repeated Finish, poor capture and denial/manual fallback. Keep private scans local.
   Record exact hardware/OS/SHA/error evidence in DEVICE_CHECKLIST; simulator success cannot satisfy capture.
5. **Native visual plan inspection.** Phone preview and Letter/A4/grayscale PDF, long individual notes, large
   family, selected critical fields, native map unavailable, all supported languages, exact current route panels.
   Portable ReportLab references are useful layout evidence only. Verify the full note and vital contact/meetup
   text survive native pagination without shrinking or clipping.
6. **Human safety and language review.** Compare authored wording/source provenance and EN/ES/VI translations
   with qualified/fluent reviewers before changing draft/needsReview states. Automated tests and source checks
   do not certify family protection or clinical instructions. Do not invent reviewers or endorsements.
7. **Observed usability.** Use USABILITY_PROTOCOL and the local privacy-minimal results template with consenting
   testers when available. Measure time to a useful card/plan, navigation errors, meeting/route understanding and
   one practical preparation. The 90-second card and 2–4-minute exercise times remain unmeasured design targets.
   Recruitment/outreach requires explicit authorization.

## Product boundaries to retain during fixes

- No fabricated personal home or ground-floor assumption; unknown/no-supported-route states remain explicit.
- Factual preparation completion follows the correct saved subject; physical checks require actual records.
  Generic Done, hypothetical comparison and source ownership never certify compatibility or readiness.
- Unsupported addresses use local planning and requested Apple services without substituted Texas resources.
  More regional providers, live flood overlays and a global-alert backend are outside this release's core.
- Public API receives no household/medical/contact/indoor data. Encrypted local storage, provenance and
  deterministic conservative routing stay intact. No live disaster command, survival score or safe-time countdown.
- Manual correction remains constrained; free-vertex CAD editing and independent captured-wall editing are absent.
  Concise household-authored arrangements are used for several continuity needs rather than lengthy questionnaires.

## Optional work after the required journey is verified

- Profile rendering and simulation on the oldest supported physical device; optimize demonstrated bottlenecks.
- Additional reviewed language packs or optional noncritical translation after EN/ES/VI is visually/human checked.
- Signed downloadable content before introducing remote rule updates. Any public-service deployment requires
  separate authorization; no deployment or broader county coverage is needed for the basic local product.
- Richer spatial illustration, derived-result caching or export recovery options only when they improve the
  verified family journey. No extra tab, accounts, invitations or notification campaign is required.
