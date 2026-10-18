# Fictional plan reference examples

These are **portable reference renders**, generated from the current DryRunCore PlanDocument snapshots.
They are not iOS screenshots, native CoreText/PDFKit exports, Apple map snapshots, or proof that share/print works.
Every household, note, phone number, address and layout is fictional. Do not use these documents as a real plan.

`plan-examples/` contains seven JSON documents: English, Spanish and Vietnamese family cards/full plans, plus a
12-person Vietnamese card with a roughly 12,000-character note. `pdf/` contains each in Letter and A4 (14 PDFs).
Basic cards are two pages; the long card is five pages on both paper sizes. Full plans are 19 pages on A4 and 20 on Letter because
the reference renderer puts each qualified scenario/person diagram on its own page. This is not a page-count
prediction for the native app. Missing Apple imagery is shown as text destinations; no map tiles are retained.

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

Current English Letter, Spanish A4 and Vietnamese Letter card first pages were inspected at full rendered size.
Current EN Letter, ES A4 and VI Letter full-plan contact sheets were inspected, with English Letter meeting-place
page 3 and route diagram page 16 also opened at full size. Not every full-plan page was inspected at full size.

After moving oversized instructions after the main card, the regenerated large Vietnamese card was inspected:
Letter pages 1, 2, 3 and 5, and A4 pages 1 and 5. Contacts and both meetups precede the unchanged full instruction
text; the continuation heading and END marker are visible. No overlap, missing glyphs or clipping was found in
those inspected pages. The five-page reference layout keeps a spacious main-card/continuation separation.
Translations remain AI drafts; user-entered example notes/proper names are intentionally preserved, and some
dynamic text retains English fallbacks.

Native SDK compilation, phone preview, native pagination, attribution, grayscale printing, VoiceOver, activity
lifecycle and actual Letter/A4 output are pending the Mac session. See
[the native handoff](../docs/CLAUDE_NATIVE_HANDOFF.md) and [verification](../docs/VERIFICATION.md).
