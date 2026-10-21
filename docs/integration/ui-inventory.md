# Native surface and state inventory

Source-discovered inventory, base 26332de plus integration working changes. All entries below are **unverified on physical device** until linked to a released reviewer report/capture. This list is a verification queue, not a native pass claim. User requires plugged-in iPhone 16 Pro; output_review drives protected surfaces exclusively. Original captures remain reviewer-only, derivatives must preserve actual geometry. Shared variants: ordinary/accessibility text, supported language long strings (en/es/vi), light/dark, loading/populated/empty/offline/error/restored when applicable. Record exact covered variants instead of extrapolating.

| Surface / source | Material states and interactions | Family decision / acceptance | Cleared evidence / verdict |
|---|---|---|---|
| RootView / onboarding | unlocked/locked; demo/create; example disclosure; language | reach desired household without changing owner data | Unverified |
| HouseholdSetupView | create; intake review sheet; address suggestions; member add; all edit steps; keyboard; Save fail/success | record name/contact/location without repeated setup | Unverified |
| DescribeHouseholdView | empty, progress, review/accept/reject, unavailable | confirm extracted facts before save | Unverified |
| Prepare NextStepsView | loading; first 3/all; urgent/ordinary; unknown/recorded/done; finish-card links; briefing collapsed/loading/expanded/fallback | choose feasible next action, identify meaningful uncertainty | Unverified; reviewer requested |
| PreparationTaskEditor / detail/comparison | task facts; hypothetical compare; actual completion; failure | distinguish practice preview from real completion | Unverified |
| FocusedHouseholdEditor | family/member/helper; contacts/new contact; supplies/water; transport; backups; review; preparation/checklist; remove confirmation; Save fail/in-flight | correct relevant fact in one push with clear name/role; preserve Cancel | Unverified; reviewer requested |
| MedicalSetupView | equipment add/edit/remove; power and backup details | record device continuity requirements | Unverified |
| OutageCardView | critical selection; contacts/meetups; empty data; PDF preview/share; pagination | carry current chosen emergency facts | Unverified |
| HomeTabView / HomeConfirmationView | absent/scanned/manual home; review/confirmation; launch RoomPlan | understand home status and next correction | Unverified; physical RoomPlan gate |
| HomeRoomListView / ManualHomeEditorView | selected room/opening; door/window correction; draft/cancel/Save; stale/failure/relaunch | correct connectivity and persist stable geometry | Unverified; house specialist owner |
| FloorPlanView / DollhouseView | selected/unknown/blocked connectors; floors; reduced motion; hazard overlays | understand supported path and current consequence | Unverified |
| HomeAddressEditorView | saved/blank/ambiguous/offline geocode; Save/Cancel | anchor resources to actual home | Unverified |
| MapPlanningView | overview/selected pin; resource types; ordinary/official/simulated route; meetup chooser; refresh/empty/offline/stale | compare useful destinations without safe-route implication | Unverified; maps owner |
| Plan / resources | contacts, home/card links, unknown or sourced destination, contextual task handoff | find preparation and trusted destination without another setup chore | Unverified |
| Rehearse hazard picker / session | each selectable family × fire/tornado/flood/freeze/heat/water; option selection; blocked/no feasible action; loading/failure/restore | distinct consequential choices and faithful visible effect | Unverified; all 18 cells require evidence |
| Rehearsal debrief / practice | ending; correct/incorrect/coached; completed retirement; next check; refreshed score | explain actual consequence and useful next preparation | Unverified |
| Assessment / stress / score | unknown/partial/full coverage; dependency fail; unchanged/changed score; provenance | understand what counts and next improvement; no technical rubric version | Unverified |
| SettingsView / ReviewReminderSection | sample selection/reset; language; reminders; consent; export/delete; unavailable | correct context and manage private state with clear feedback | Unverified |

Every reachable sheet/inspector/form/preview discovered during device walk must receive its own capture/state row if its behavior differs materially from the parent grouping. Inventory completeness itself awaits independent family/integration review. Exact source screen symbols for Plan/rehearsal/score must be reconciled by owning specialists; grouping does not assert implemented navigation or completed verification.
