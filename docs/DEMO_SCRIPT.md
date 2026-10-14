# Demo script: Congressional App Challenge video (2–3 minutes)

The story follows the **Oak household** (fictional): a rural Erath County home with a private electric well, all-electric
heat, and **Grandpa, who uses an oxygen concentrator**. Their portable battery station has never been tested with it.
Everything shown uses fictional data.

Each beat names the launch arguments that open that screen directly. Set them in Xcode under **Product > Scheme >
Edit Scheme… > Run > Arguments**, or pass them with `scripts/mac/device.sh -- <args>`. Add `-disableAnimations` for
steadier recordings.

| # | Time | Beat (what to say) | Screen | Launch arguments |
|---|---|---|---|---|
| 1 | 0:00–0:20 | **The problem.** In a Texas winter storm the power can go out for days. For a family whose grandfather depends on an oxygen concentrator, that's not an inconvenience; it's an emergency. (Optional: one cited fact from S05, quoted exactly; see below.) | Onboarding | *(none)* |
| 2 | 0:20–0:40 | **One tap to see it.** Pick the Oak household. Next steps opens and runs all six practice scenarios. The first item: confirm a backup that works with the oxygen concentrator. | Next steps | `-demoHousehold hh-oak -demoTab next` |
| 3 | 0:40–1:10 | **Rehearse the freeze.** Step through it: power out → heat stops → well pump stops → taps dry → the concentrator has no confirmed backup. Each step shows what just changed. The household makes a decision; unsafe options are never rewarded. | Freeze rehearsal | `-demoHousehold hh-oak -demoScenario freeze-power-loss -demoStep decision` |
| 4 | 1:10–1:30 | **What would help.** The debrief lists the top preparations. Open "Confirm a backup…", then **Try this change**: the same storm replayed with only that change. The oxygen outage disappears. Nothing in the household changed; it's a practice comparison. | Debrief → Before and after | `-demoHousehold hh-oak -demoScenario freeze-power-loss -demoStep end`, then tap Debrief |
| 5 | 1:30–2:00 | **The outage card.** One page for Grandpa's concentrator: device, backup, documented runtime, who to call, where to go, plus 911, 2-1-1 Texas and STEAR. Tap **Fill in what's missing**, record the tested battery station and the runtime from the care plan, and the card updates. Print it for the fridge. | Outage card | `-demoHousehold hh-oak -demoTab next`, then tap Medical power-outage card |
| 6 | 2:00–2:20 | **Share with family.** Send the plan and the card to the aunt in Abilene and the oxygen supplier. The app shows what's still unknown before you send. | Share with family | `-demoHousehold hh-oak -demoTab next`, then tap Share with family |
| 7 | 2:20–2:40 | **In their language.** The same plan in Vietnamese for the Lake household, clearly labeled as a draft translation. Works offline in airplane mode. | Plan tab (Vietnamese) | `-demoHousehold hh-lake -demoLocale vi -demoTab plan -demoPlan all` |
| 8 | 2:40–2:55 | **Close.** Private by design: the household stays encrypted on the phone. No scores, no countdowns: just what to do next. | Next steps | `-demoHousehold hh-oak -demoTab next` |

## Impact statement (one paragraph, for the submission form)

> Dry Run helps Texas families who depend on powered medical equipment rehearse a power outage before it happens.
> In a few minutes a family sees how losing power cascades through their own home: heat, well water, and an oxygen
> concentrator with no tested backup. It then shows the preparations that matter most, lets them test a change
> safely, and gives them a one-page outage card for each device to print or share with relatives and caregivers. The
> card and plan work offline, in English, Spanish, and Vietnamese, and household details never leave the phone.
> Guidance comes from cited public sources: the FDA on medical devices in disasters (S25), the CDC on power outages
> (S20), and the Texas Emergency Assistance Registry (S28). The app never estimates how long someone is safe without
> power.

**Optional statistic.** If you want a number in beat 1, take it word for word from the Texas DSHS February 2021
winter storm mortality report (S05:
https://www.dshs.texas.gov/sites/default/files/news/updates/SMOC_FebWinterStorm_MortalitySurvReport_12-30-21.pdf) and
cite it on screen. Don't round it or paraphrase it into a stronger claim.

## Recording checklist

- Use the simulator (iPhone 18 Pro) or your phone in Do Not Disturb, with the clock reading 9:41
  (`xcrun simctl status_bar booted override --time 9:41`).
- Turn on airplane mode before beat 7 to show it works offline.
- Every household, phone number (555-01xx), and place is fictional; say so once on screen.
- Keep the "Practice scenario" label visible in the rehearsal shots.
