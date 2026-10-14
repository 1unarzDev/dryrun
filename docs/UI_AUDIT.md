# UI button audit

Every tappable control, what it does, and what proves it works. "Journey" means a test in
`apps/ios/DryRunUITests/DemoJourneyUITests.swift`; "Tour" means `ScreenshotTourUITests` opened that screen via the
control. Simulator: iPhone 18 Pro, iOS 27.0. Last run: 2026-10-14.

Rules checked for every row: no control is a no-op, destructive actions confirm first, async actions show progress,
and failures show a readable message (never a raw error).

## Onboarding

| Control | Result | Verified by |
|---|---|---|
| See how it works (`onboarding.demo`) | Loads the Oak household and opens the freeze rehearsal | Journey `testOnboardingDemoReachesRehearsalInOneTap` |
| Set up my household (`onboarding.create`) | Opens the guided setup | Journey `testGuidedSetupWithEveryAnswerNotSure` |
| Example household rows (`onboarding.sample.*`) | Load that fictional household; Next steps opens | All journeys (`hh-oak`, `hh-lake`) |
| Language menu (`onboarding.language`) | Switches the onboarding language | Manual |

## Guided setup (create and edit)

| Control | Result | Verified by |
|---|---|---|
| Next / Back (`setup.next`, `setup.back`) | Moves between the 7 steps; progress shows "Step n of 7" | Journey `testGuidedSetupWithEveryAnswerNotSure` |
| Finish (`setup.save`) | Saves the household (unknowns kept unknown) and opens the app | Journey `testGuidedSetupWithEveryAnswerNotSure` |
| Add person / device / backup / contact / way to travel / pet | Adds a row; empty rows are dropped on save | Manual |
| Swipe to delete rows | Removes the row (at least one person is kept) | Manual |
| Cancel / Save (edit mode) | Discards / saves edits; derived results are recomputed | Journey `testOutageCardFillInClosesGapsAndShares` (same save path) |

## Next steps (first tab)

| Control | Result | Verified by |
|---|---|---|
| Medical power-outage card (`next.outageCard`) | Opens the card sheet | Journey `testOutageCardFillInClosesGapsAndShares`, Tour |
| Practice a scenario (`next.rehearse`) | Switches to the Rehearse tab | Manual |
| Share with family (`next.share`) | Opens the share flow | Journey `testShareWithFamilyPreview`, Tour |
| Step rows (`next.step.*`) | Open the step detail | Journey `testNextStepsMarkDoneMovesToDone` |
| Show all / Show fewer (`next.showAll`) | Expands or collapses the list | Manual |
| Answer in household details (`next.answerQuestions`) | Opens the household editor | Manual |
| Try this change (`next.tryChange`) | Runs the source scenario and opens Before and after; shows a message on failure | Manual (same engine path as the debrief journey) |
| Mark completed (`next.markDone`) | Records the completion; the step moves to Done | Journey `testNextStepsMarkDoneMovesToDone` |
| Source links | Open the cited page in Safari | Manual |

## Outage card and device editor

| Control | Result | Verified by |
|---|---|---|
| Fill in what's missing (`card.fix`) | Opens the device editor for that card | Journey `testOutageCardFillInClosesGapsAndShares`, Tour |
| Add a medical device (toolbar `+` / empty state) | Opens the editor for a new device | Manual |
| Call buttons on contact lines | Open the dialer for that number (explicit tap; never auto-dials) | Manual |
| Print or share the card (`card.share`) | Renders the PDF and opens the preview | Journey `testOutageCardFillInClosesGapsAndShares` |
| Editor: Works with / Tested / Runtime / Add backup / Add contact / Add place | Edit the household; the card updates after Save | Journey `testOutageCardFillInClosesGapsAndShares` (works-with, runtime, save) |
| Editor: Cancel / Save (`medical.save`) | Discard / save | Journey `testOutageCardFillInClosesGapsAndShares` |
| Done | Closes the card | Manual |

## Share with family

| Control | Result | Verified by |
|---|---|---|
| Household plan / Power-outage card / Private notes toggles | Choose what goes in the PDF | Manual |
| Preview and share (`share.preview`) | Builds the plan if needed, renders the plan and card PDF, opens the preview | Journey `testShareWithFamilyPreview` |
| Preview: Share / Print / Close | Share sheet / AirPrint / closes and deletes the temporary file | Manual (AirPrint untested on device) |

## Rehearse

| Control | Result | Verified by |
|---|---|---|
| Scenario cards (`scenario.*`) | Open that rehearsal | Journeys (fire, freeze) |
| Next step (`rehearsal.next`) | Reveals the next event; disabled while a decision is pending ("Choose above") | Journeys |
| Decision options (`decision.option.*`) | Re-run with that choice; the card is scrolled above the bottom bar | Journey `testFreezeTryChangeShowsBeforeAndAfter` |
| Replay (`rehearsal.replay`) | Restarts the same scenario | Manual |
| Debrief (`rehearsal.debrief`) | Enabled at the end; opens the debrief | Journeys, Tour |
| Everything in the home right now (`rehearsal.allServices`) | Expands the full service list | Manual |
| Earlier timeline rows | Expand to the full event card | Manual |
| Why did this happen? | Shows facts, causes, and sources in words | Manual |
| Debrief: recommendation rows, Show all (`debrief.showAll`) | Open detail / expand | Journey `testFreezeTryChangeShowsBeforeAndAfter` |
| Detail: Try this change (`recommendation.tryChange`) | Opens Before and after | Journey `testFreezeTryChangeShowsBeforeAndAfter` |
| Detail: Mark completed (`recommendation.markDone`) | Records the completion | Same code path as `next.markDone` |

## Home, Plan, Help, Settings

| Control | Result | Verified by |
|---|---|---|
| Home: 2D / 3D / Room list | Switch views | Tour (`home-2d`, `home-3d`, `home-rooms`) |
| Home: Confirm rooms, doors, and exits; Edit; Scan | Open confirmation / manual editor / RoomPlan (LiDAR only) | Manual; RoomPlan needs a device |
| Plan: language, scenario toggles, Generate plan (`plan.generate`) | Build and save the plan; progress while building | Journeys (fire, Vietnamese) |
| Plan: View saved plan (`plan.viewSaved`) | Opens the plan | Tour (`plan-document`) |
| Plan: Share / Print | PDF preview (same as above) | Manual |
| Help: 911 call button | Opens the dialer (explicit tap) | Manual |
| Help: household contacts, resource call/website buttons | Dialer / Safari | Manual |
| Help: Medical power-outage card (`help.outageCard`) | Opens the card | Manual |
| Help: Show map | Shows the directory map (needs tiles) | Manual |
| Settings: language, Delete all household data (confirms first), Done | As labeled | Manual |

## Known gaps

- Strings in Home, Settings, the manual home editor, and the RoomPlan flow are still English-only (backlog item 8).
  Everything added in this round is localized in EN/ES/VI (drafts).
- RoomPlan scanning, AirPrint, Keychain, and file protection need a physical iPhone.
