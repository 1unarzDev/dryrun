# House editing integration slice

Owner: house_simulation; HOME-02, HOME-01, HAZ-01..03, UI-01, REL-01. Base 26332de with existing owner work preserved. No phone session used by this specialist; all native acceptance belongs to the exclusive designated reviewer on the plugged-in iPhone 16 Pro.

## Purpose and contract

A family corrects the selected room name/type or an opening classification directly on the existing home plan, then saves once. This improves the indoor exit/shelter decision by keeping the graph and shown opening classification aligned. Captured coordinates and IDs remain canonical. Simpler alternative considered: lists alone; retained canvas selection because it identifies the actual opening. Existing lists remain an accessible alternative.

Known inputs: actual saved graph/revision, selected element ID, recorded opening operability/access and shelter suitability. Unknown safety facts remain separate from valid capture dimensions. No exact exterior coordinate or disaster-safe route is inferred.

The editor callback is `@MainActor (HomeModel, Int?) async -> Bool`. The explicit `savedBaseRevision` init argument is captured once in State; nil means expected absence of a saved home. AppModel must compare current optional revision for equality, including nil, before persisting. The root owns AppModel/callers. Save snapshots the draft, prevents concurrent interactions and dismissal during persistence, and dismisses only after true. False preserves edits and exposes retry feedback. Cancel leaves persistence untouched. Pending marker edits apply before saving. Reclassification preserves ID/endpoints/floor/sides/width while clearing prior escape suitability; an open doorway cannot transfer operability evidence to a new door/window.

## Files

- apps/ios/DryRun/Spatial/ManualHomeEditorView.swift: awaited save, cancel, direct selected-canvas navigation, immediate opening-type control; remove room dimension/measurement/review controls and opening measured-width input.
- apps/ios/DryRun/Spatial/HomeRoomListView.swift: remove legacy room measurement/name-confirmation suffixes.
- packages/DryRunCore/Sources/DryRunCore/Spatial/HomeGeometryEditor.swift: transactional reclassification.
- packages/DryRunCore/Tests/DryRunCoreTests/OpeningReclassificationTests.swift: stable geometry/identity, escape-evidence invalidation, no-op/error atomicity, doorway operability guard.

## Shared scenario agreement

Retain the existing scenario-house-contract.md authority. Fire routes use supported indoor paths and do not certify outside accounting from intent. Tornado candidates require suitable recorded room plus reachable per-person route. Flood refuge requires supported floor/access facts, separate from a household leak. Maps may hand off a confirmed exterior exit to a labeled home-origin geographic preview; no door coordinate can be invented. These changes add no simulation movement store and no score credit. Scenario transitions/person-specific shelter/exterior accounting remain scenario/integration-owned acceptance gates.

## Evidence and remaining gates

Focused Swift test first capture run-ec0e901df1f045978fce9130e125467a returned exit 1; raw diagnostics requested from dedicated reviewer. Retried with authorized cache access through the same firewall: run-d42474b77f84479e9bffa4687d5d98eb returned exit 1. Source inspection subsequently corrected a new test assigning EvidenceValue instead of Bool to emergencyEscapeConfirmed; recheck still required. No protected output inspected. No Mac native build or physical verification claimed by specialist.

Required iPhone reviewer sequence: use hh-oak isolated example; select room and opening from canvas/list, ensure highlight follows; switch Door/Window and confirm geometry unchanged; Cancel/reopen unchanged; save/relaunch retains corrected classification and route refresh; inject failed write and stale revision (including an initially unsaved draft versus newly saved scan), verify draft retained and new saved graph protected; repeated Save no duplication. Check ordinary and accessibility text size. Real RoomPlan capture requires owner-assisted physical movement and must be recorded separately from imported synthetic capture tests.
