# October 17 requirement-to-evidence map

**Implementation prepared; native build and device test pending.** No current simulator or physical-device run.
Current portable counts: core204, vault35, backend68; exact commands/limits in VERIFICATION. Source paths are
relative to this repository. The native handoff is actionable; no build success is implied by its existence.

| Requested change | Implemented behavior / principal files | Validation performed | Remaining hardware/human check |
|---|---|---|---|
| Personal household without layout; safe migration | Optional PrivateSnapshot.home; explicit vault absence flag distinct from corruption; stable home ID. AppModel, Services/VaultPrivateDataStore, VaultModels | Full core/vault suites, absent-layout encrypted reload and legacy recovery tests | Native AppPersistenceTests and fresh real-vault relaunch |
| Three destinations and progressive family setup | RootView; HouseholdSetupView; FocusedHouseholdEditor; NextStepsView. One self, optional age/address, relationships, direct forms | Source review and syntax parse; UI journeys updated | Current small-phone/90sec timing/VoiceOver screenshots |
| Equipment, medicine and contacts | Household model; EquipmentEditorFields; MedicalSetupView; DependencyModel/BackupAllocation. Localized type/custom label migration; cold versus electrical; ownership distinct from confirmation; type changes invalidate old support confirmations | FamilyPreparationRevisionTests; old fixtures/semantics; independent candidate-save review | Every native selector, failed-write form retention, provider/human review |
| Universal selected-content card | FamilyEmergencyCard; OutageCardView. Clinical/contact/medication/instructions independent, two meetups, continuity/helpers/transport/supply locations/review; no hidden geometry | Core adversarial selection and mixed/med-only tests; fictional reference render/text audit | Native CoreText/PDFKit/share/Print selected content, long notes, activity leases |
| Broad factual preparations | BaselinePreparedness; PreparationCompletion; NextSteps; PREPAREDNESS_COVERAGE. Baseline before exercise, scoped identity/fingerprints, separate alarm/check/coverage, maintenance and review | Ranking, merging, independent same-device tasks, cold-only/mixed, alarm facts, stale check invalidation and separate solo/joint review tests | Native save-return and reopening all editors; source/human safety review |
| Optional address and useful maps | HomeAddressEditorView, MapPlanningView/Models/Adapters. GPS-free Apple search, independent nearby requests, persistent places, explicit purposes, home-origin directions | Core places/policy; native fake tests authored, source-review late result fixes | Texas/other-US/non-US/rural/unresolved real Apple calls, denial/offline/cancellation |
| Stable rescan and geographic continuity | AppModel.updateHome/moveHome; HomeMeetingPlaces. Same-home stable ID, preserve places, remap only known room IDs; explicit move reset | HomeMeetingPlaces tests; native rescan test authored | Real rescan/move persistence, ambiguous assignments |
| Native RoomPlan and correction | RoomCaptureContainer, RoomPlanMapping, HomeConfirmation, ManualHomeEditor, ManualLayout. Shared AR frame/StructureBuilder, generation-bound callbacks, blank manual fallback, grade/exit review, shape-preserving resizing, explicit levels/stair endpoints, assignment | Core import/generation/grade/correction/independent-wall/landing tests; Apple API docs checked; syntax parse | Installed SDK build; measured LiDAR connected-room capture, transforms/story/tracking/interruption |
| Deterministic fire/flood/tornado scene | SpatialExercise, HazardRules, EgressPlanner, RehearsalCursor, FloorPlan/Dollhouse/Rehearse. Current stage/person routes; real shelter/refuge; exposed start; explicit window suitability | Spatial matrix13 configurations, fire origin/start/exclusion cases, flood/tornado access and route audits; shared current shelter/hypothetical isolation, full deterministic suites | Native 2D/3D/export visual agreement, Reduce Motion, physical home rehearsal |
| Coherent live visual plan/export | PlanDocument/Builder, PlanViews/PDFRenderer/MapSnapshotRenderer. Live facts/saved places, qualified final route geometry, separate geographic/indoor panels, snapshot fallback, Letter/A4 continuation | LivingPlan/PlanIntegration tests, portable fictional PDFs; native long-note/legend/lease tests authored | Attributed native snapshots, real Letter/A4/grayscale PDFs and system lifecycle |
| EN/ES/VI, accessibility | Existing Localizer extended common/native/spatial/plan; InfoPlist.strings; stable IDs, proper names/notes preserved | Backend placeholder/number/drift checks68 tests; rendered fictional references | Some dynamic validation English fallbacks; all current forms/AX/VO/large text/language and professional translation review pending |
| Optional review reminder | ReviewReminders, ReviewReminderSection, Settings/FocusedHouseholdEditor. One explicit generic non-repeating local reminder; shared cancel/deletion generation | 5 fake native tests authored, syntax parsed | Permission/delivery/relaunch/deletion on system, native typecheck |
| Demonstration and community evidence | DEMO_SCRIPT, USABILITY_PROTOCOL, results template, output examples, CLAUDE_NATIVE_HANDOFF | Fictional artifact generation and portable QA only | No recording, unfamiliar-household pilot, external endorsement or recruitment performed |

## Material remaining limitations

Native adapters have not compiled against the installed iOS SDK in this session; iOS18 minimum remains. Actual
RoomPlan mapping/frame alignment and errors must be verified with the owner’s Mac/iPhone. Manual context correction
covers names/types/moves, shape-preserving resize, opening re-placement, markers, explicit levels/first rooms,
refuge and separately recorded stair endpoints with review/Undo. Free vertex/CAD and independent captured-wall
editing remain absent; uncertain captured barriers are conservatively retained. Reconnect/dietary/infant/flood/heat
arrangements partly use concise recorded notes. The user can choose a one-time local review reminder; its actual
permission/delivery/deletion behavior is pending native verification. Current UI timing/large text/localization,
real Apple map behavior, native PDF readability and share lifecycle remain unverified. Safety text and ES/VI are
AI drafts. No professional/participant outcomes are claimed.

The project is native SwiftUI/RoomPlan; Expo Go cannot run it. The owner’s Claude/Mac session should build and
fix native errors, run the current full journey/screens, and return exact SHA/environment evidence. Install via
`scripts/mac/device.sh` after successful native build. No publishing or third-party outreach is authorized.
