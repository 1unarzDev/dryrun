# Fictional plan reference examples

These are **portable reference renders**, generated from the current DryRunCore PlanDocument snapshots.
They are not iOS screenshots, native CoreText/PDFKit exports, Apple map snapshots, or proof that share/print works.
Every household, note, phone number, address and layout is fictional. Do not use these documents as a real plan.

`plan-examples/` contains seven JSON documents: English, Spanish and Vietnamese family cards/full plans, plus a
12-person Vietnamese card with a roughly 12,000-character note. `pdf/` contains each in Letter and A4 (14 PDFs).
Basic cards are one page; the long card is five pages. Full plans are 18 pages on A4 and 19–20 on Letter because
the reference renderer puts each qualified scenario/person diagram on its own page. This is not a page-count
prediction for the native app. Missing Apple imagery is shown as text destinations; no map tiles are retained.

## Reproduce on Linux

With Docker Swift 6.2, Python reportlab/pypdf/Pillow, Poppler, and DejaVu Sans fonts installed:

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

Poppler-rendered EN/ES/VI representative cards, the long-note continuation/end, and English/Spanish full-plan
contact sheets were inspected. The final English Letter and Spanish A4 full-plan contact sheets show the separate
canonical indoor diagrams, qualified routes, and text-only neighborhood panel. English A4 and Spanish Letter
cards and Vietnamese Letter/long-note end pages were inspected for hierarchy and legibility. Representative
pages were opened at full rendered size; not every full-plan page was inspected at full size.
No visible overlap, missing glyphs or clipping was found in those inspected pages. The oversized note retains
its END marker and the remaining contacts/meetups/review section. Translations remain AI drafts; user-entered
example notes/proper names are intentionally preserved, and some dynamic text retains English fallbacks.

Native SDK compilation, phone preview, native pagination, attribution, grayscale printing, VoiceOver, activity
lifecycle and actual Letter/A4 output are pending the Mac session. See
[the native handoff](../docs/CLAUDE_NATIVE_HANDOFF.md) and [verification](../docs/VERIFICATION.md).
