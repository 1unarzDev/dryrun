# Fictional plan reference examples

These are **portable reference renders**, generated from the current DryRunCore PlanDocument snapshots.
They are not iOS screenshots, native CoreText/PDFKit exports, Apple map snapshots, or proof that share/print works.
Every household, note, phone number, address and layout is fictional. Do not use these documents as a real plan.

`plan-examples/` contains seven JSON documents: English, Spanish and Vietnamese family cards/full plans, plus a
12-person Vietnamese card with a roughly 12,000-character note. `pdf/` contains each in Letter and A4 (14 PDFs).
Basic cards are two pages; the long card is five pages on both sizes. Full plans are 24 pages on both
sizes because the reference renderer puts each qualified current scenario/person/floor diagram on its own page,
including no-route/exposure context. This is not a native page-count target. The reference-only JSON envelope
contains core-computed panel descriptors/titles/start anchors; Python does not recalculate routes. Missing Apple
imagery is shown as text destinations; no map tiles are retained.

## Reproduce on Linux

With Docker Swift 6.2, Python reportlab/pypdf/Pillow, Poppler, and Noto Sans (regular/bold) fonts installed:

```bash
DRYRUN_DUMP=1 DRYRUN_SCRATCH=preview scripts/swift.sh packages/DryRunCore test --filter PlanDemoDump
python3 scripts/preview-plan.py output/plan-examples/*.json --paper both
python3 scripts/audit-plan-examples.py --render --output tmp/pdfs/reviewed
```

The generator reads the canonical core data; the reference layout deliberately differs from native rendering.
`pdf-text-audit.json` records page counts, extracted text sizes and paper bounds. The audit checks all PDFs for
the structured international phone, both meeting-place labels and finding instructions, valid paper size,
replacement characters, and the long-note END marker. Text extraction alone cannot prove absence of clipping.

## Visual review actually performed

For this connected-state closure, English Letter, Spanish A4 and Vietnamese Letter card page 1 were inspected
at full rendered size. EN Letter, ES A4 and VI Letter full-plan contact sheets were inspected; EN Letter pages 12
(tornado), 16 (flood no-route) and 20 (fire) were also opened at full size. A furniture-fill/room-label ordering
problem was corrected in reference/native source and regenerated EN Letter page 20 was re-inspected. Not every
full-plan page was inspected at full size.

The 12-person Vietnamese long-note card was inspected on Letter pages 1, 3, 5 and A4 page 5. Main contacts/meetups
precede the unchanged long instructions; the continuation heading and END marker are visible. No overlap,
missing glyphs or clipping was found in the inspected pages. Text audit covers all 14 PDFs for both meetups,
finding instructions, structured international phone, paper size, replacement glyphs and the long-note END marker.
Translations remain AI drafts. User notes/proper names stay exact; reference cover/renderer labels and fictional
room names remain English. This reference renderer is not whole-app localization proof.

Native SDK compilation, phone preview, native pagination, attribution, grayscale printing, VoiceOver, activity
lifecycle and actual Letter/A4 output are pending the Mac session. See
[the native handoff](../docs/CLAUDE_NATIVE_HANDOFF.md) and [verification](../docs/VERIFICATION.md).

October17 hosted-native follow-up regenerated all seven JSON snapshots and 14 reference PDFs with content
version2026.10.2 after portable planning fixes. The full text/paper audit passed. Newly re-opened images were
Spanish A4 card page1, Vietnamese long-note A4 page5 (including END marker) and the English Letter full-plan
contact sheet; no new clipping/overlap was observed there. Earlier detailed inspections above remain a record
of those earlier renders. Native PDFs and activity/Print behavior remain a distinct verification gate.
