# Dry Run

Dry Run is an iOS app for families to rehearse the first minutes and the next 72 hours of a disaster in their own
household. The rehearsals show how one failure causes others, let the family compare preparations, and leave them
with a plan they can open offline.

> **Status: AI-assisted first-review prototype (2026-10-09).** The core engine, routing, vault, and backend are
> tested on Linux. The iOS app is **authored but has not been compiled yet**, because no Mac was available. All safety
> content and translations are unreviewed drafts. See `docs/VERIFICATION.md` and `docs/AI_ASSISTANCE.md`.

## What runs today

| Component | How to run | Status |
|---|---|---|
| `packages/DryRunCore`: models, simulation, ranking, routing, plan builder (Foundation-only) | `scripts/swift.sh packages/DryRunCore test` (Swift 6.2 in Docker) or `swift test` on macOS | Tested |
| `packages/DryRunVault`: encrypted vault, public pack cache | `scripts/swift.sh packages/DryRunVault test` | Tested (Linux uses swift-crypto; Keychain/file protection need a device) |
| `services/public-api`: Hono public-data Worker | `cd services/public-api && pnpm install && pnpm test` · local: `pnpm dev` | Tested locally, not deployed |
| `apps/ios`: SwiftUI app | `cd apps/ios && xcodegen && open DryRun.xcodeproj` | Authored only (syntax-parsed) |

### Requirements
- Core/vault: Docker (the `swift:6.2` image) **or** Swift 6 / Xcode 26 on macOS.
- iOS app: macOS with Xcode 26 (iOS 18 deployment target) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
  RoomPlan scanning needs a LiDAR iPhone; everything else works without LiDAR.
- Backend: Node 22+ and pnpm. No API keys are needed: the app runs fully on bundled data.

## Try the demo (once the app builds)

1. Launch → **Try a fictional household**, then choose **Oak household**. This is a rural well, electric heat, an
   oxygen concentrator, and a battery station nobody has confirmed works.
2. **Rehearse → Freeze with power loss.** Step through: power out → heat stops → well pump stops → taps dry →
   the concentrator has no confirmed backup. Answer the two decisions; unsafe options are never rewarded.
3. **Debrief** → open "Confirm a backup that works with Oxygen concentrator" → **Try this change**. The same exercise
   replays with only that change: the critical outage event disappears and the requirement is resolved. Your household
   is not changed unless you tap **Mark preparation completed**.
4. **Rehearse → Home fire.** The kitchen is blocked (an authored exercise condition), and the practice route
   switches to the other exit. Routes appear in text and on the 2D plan.
5. **Plan** → choose Tiếng Việt → **Generate plan** → view, share, or print the PDF. Untranslated lines are marked
   [EN], and the draft-translation banner is visible.
6. **Help**: shows the 911, 2-1-1 Texas, and STEAR (opt-in) contacts as text. It works without map tiles.

Airplane mode: everything above still works. Alerts say current conditions are unavailable.

## Fictional data only
Every household, home, and phone number (555-01xx) in `fixtures/` and `content/` is fictional.

## On a Mac
See `docs/MACOS_VERIFICATION.md`. `scripts/mac/verify.sh` produces one bundle to send back. For UI work, see
`docs/FRONTEND_HANDOFF.md`, `scripts/mac/screens.sh`, and `scripts/mac/device.sh`. From Linux, an external Mac can
be driven with `scripts/remote-mac.sh`.

## Docs
`docs/FRONTEND_HANDOFF.md` · `docs/MACOS_VERIFICATION.md` · `docs/DEVICE_CHECKLIST.md` · `docs/ARCHITECTURE.md` · `docs/DECISIONS.md` · `docs/VERIFICATION.md` · `docs/SAFETY_AND_CONTENT.md` ·
`docs/AI_ASSISTANCE.md` · `docs/STUDENT_IMPLEMENTATION.md` · `docs/REVIEW.md` · `docs/BACKLOG.md` · `docs/CONTRACTS.md`
· lane reports and adversarial reviews in `docs/lanes/`.
