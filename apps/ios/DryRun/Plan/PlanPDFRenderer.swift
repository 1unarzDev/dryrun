import UIKit
import CoreText
import DryRunCore

/// Renders a validated PlanDocument as real text (searchable, Unicode via Core Text/UIKit).
/// Never screenshots a scroll view. Text is never shrunk below the minimum; content that does not fit
/// flows to a continuation page that is clearly marked, rather than being clipped.
///
/// Layout ("responder sheet"): every section is a bordered box with a heading band and one symbol. Critical
/// information uses an inverted black band and a heavier border, so the hierarchy survives grayscale printing.
/// Nothing relies on color alone.
/// Main-actor isolated: it is only called from a button action, and this keeps UIKit drawing APIs
/// legal regardless of how a given SDK annotates them.
@MainActor
struct PlanPDFRenderer {
    enum Paper: String, CaseIterable { case letter, a4
        var size: CGSize { self == .letter ? CGSize(width: 612, height: 792) : CGSize(width: 595.28, height: 841.89) }
    }
    static let pageSize = CGSize(width: 612, height: 792) // default, US Letter
    static let margin: CGFloat = 42
    static let topMargin: CGFloat = 40
    static let bottomMargin: CGFloat = 40
    static let minimumBodySize: CGFloat = 11
    static let footerHeight: CGFloat = 30

    struct Output {
        var data: Data
        var pageCount: Int
        /// Plan pages that needed a continuation page (reported in VERIFICATION, never clipped).
        var continuedPageIDs: [String]
    }

    /// Callers may supply their loaded packs; retained older documents use the bundled packs by default.
    /// This is a content adapter, not a second translation table maintained by the PDF renderer.
    private static let bundledContent: ContentLibrary? = try? ContentLibrary.load(from: ContentLocator.contentRoot())

    func render(_ doc: PlanDocument, paper: Paper = .letter, mapPanels: [PlanMapPanel] = [], localizer: Localizer? = nil) -> Output {
        let l = (localizer ?? Self.bundledContent?.localizer(for: doc.locale))?.with(locale: doc.locale)
            ?? Localizer(locale: doc.locale, tables: [:], manifest: nil)
        // Two passes: the first counts pages so every footer can say "Page X of N".
        let counted = Pass(doc: doc, paper: paper, mapPanels: mapPanels, l: l, totalPages: nil).run()
        let final = Pass(doc: doc, paper: paper, mapPanels: mapPanels, l: l, totalPages: counted.pageCount).run()
        return final
    }

    static func exportText(_ key: String, locale: String) -> String {
        switch (key, locale) {
        case ("sources", "es"): "Fuentes (identificadores)"
        case ("sources", "vi"): "Nguồn (mã tham chiếu)"
        case ("sources", _): "Sources (reference IDs)"
        case ("exercise", "es"): "Ejercicio"
        case ("exercise", "vi"): "Bài tập"
        case ("exercise", _): "Exercise"
        case ("example", "es"): "Hogar de ejemplo ficticio"
        case ("example", "vi"): "Nhà ví dụ hư cấu"
        case ("example", _): "Fictional example home"
        case ("continued", "es"): "continuación"
        case ("continued", "vi"): "tiếp theo"
        case ("continued", _): "continued"
        case ("mapUnavailable", "es"): "Imagen del mapa no disponible. Usa los nombres, direcciones e instrucciones guardados."
        case ("mapUnavailable", "vi"): "Không có ảnh bản đồ. Dùng tên, địa chỉ và hướng dẫn đã lưu."
        default: "Map image unavailable. Use the saved names, addresses and finding instructions."
        }
    }

    // MARK: - Type and color

    enum Style {
        static let ink = UIColor.black
        static let secondary = UIColor(white: 0.30, alpha: 1)
        static let rule = UIColor(white: 0.55, alpha: 1)
        static let band = UIColor(white: 0.90, alpha: 1)
        static let title = UIFont.systemFont(ofSize: 22, weight: .bold)
        static let bandFont = UIFont.systemFont(ofSize: 11, weight: .bold)
        static let name = UIFont.systemFont(ofSize: 13, weight: .bold)
        static let body = UIFont.systemFont(ofSize: 11.5)
        static let bodyBold = UIFont.systemFont(ofSize: 11.5, weight: .bold)
        static let missing = UIFont.italicSystemFont(ofSize: 11.5)
        static let phone = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        static let meta = UIFont.systemFont(ofSize: 10)
        static let metaBold = UIFont.systemFont(ofSize: 10, weight: .bold)
        static let footer = UIFont.systemFont(ofSize: 9)

        static func paragraph(lineSpacing: CGFloat = 1.5, alignment: NSTextAlignment = .natural) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping; p.lineSpacing = lineSpacing; p.alignment = alignment
            return p
        }
        static func text(_ s: String, _ font: UIFont = body, _ color: UIColor = ink, alignment: NSTextAlignment = .natural) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph(alignment: alignment)])
        }
    }

    static func symbol(for sectionID: String) -> String {
        switch sectionID {
        case "identity": "house.fill"
        case "critical", "instruction-continuation": "exclamationmark.triangle.fill"
        case "contacts", "help": "phone.fill"
        case "outsideMeetingPoint", "meeting": "figure.walk"
        case "backupMeetingPlace": "car.fill"
        case "continuity", "equipment", "medical", "device", "backup": "cross.case.fill"
        case "review": "calendar"
        case "people": "person.2.fill"
        case "supplies", "water": "shippingbox.fill"
        case "steps", "actions": "list.number"
        case "sources": "book.closed"
        case "places", "goTo": "mappin.and.ellipse"
        default: "square.text.square"
        }
    }

    // MARK: - Rows

    /// One table row: optional left column (name), wrapping body, optional right column (phone).
    /// Only the body splits across pages; the left/right columns stay with the first fragment.
    @MainActor
    struct Row {
        var left: NSAttributedString?
        var body: NSAttributedString
        var right: NSAttributedString?
        var leftWidth: CGFloat = 0
        var rightWidth: CGFloat = 0
        var symbol: String? = nil
        var padding: CGFloat = 5
        var separator = true

        static let gap: CGFloat = 10
        static let symbolWidth: CGFloat = 16

        private func columns(_ width: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            let lead = (symbol == nil ? 0 : Self.symbolWidth) + (left == nil ? 0 : leftWidth + Self.gap)
            let trail = right == nil ? 0 : rightWidth + Self.gap
            return (lead, max(60, width - lead - trail), trail)
        }
        func height(width: CGFloat) -> CGFloat {
            let (_, bodyWidth, _) = columns(width)
            var h = measure(body, bodyWidth)
            if let left { h = max(h, measure(left, leftWidth)) }
            if let right { h = max(h, measure(right, rightWidth)) }
            return ceil(h) + padding * 2
        }
        /// Splits the body at Core Text's visible range for `height`. Returns nil remainder when it all fits.
        func split(width: CGFloat, height: CGFloat) -> (Row, Row?) {
            let (_, bodyWidth, _) = columns(width)
            let (head, tail) = PlanPDFRenderer.split(body, width: bodyWidth, height: max(14, height - padding * 2))
            var first = self; first.body = head
            guard let tail else { return (first, nil) }
            var rest = self; rest.body = tail; rest.left = nil; rest.right = nil; rest.symbol = nil
            if left != nil { rest.left = NSAttributedString(string: " "); }
            return (first, rest)
        }
        func draw(at origin: CGPoint, width: CGFloat) {
            let (lead, bodyWidth, _) = columns(width)
            var x = origin.x
            let y = origin.y + padding
            if let symbol {
                PlanPDFRenderer.drawSymbol(symbol, in: CGRect(x: x, y: y + 2, width: 10, height: 10))
                x += Self.symbolWidth
            }
            if let left { PlanPDFRenderer.draw(left, in: CGRect(x: x, y: y, width: leftWidth, height: measure(left, leftWidth))) }
            PlanPDFRenderer.draw(body, in: CGRect(x: origin.x + lead, y: y, width: bodyWidth, height: measure(body, bodyWidth)))
            if let right {
                PlanPDFRenderer.draw(right, in: CGRect(x: origin.x + width - rightWidth, y: y, width: rightWidth, height: measure(right, rightWidth)))
            }
        }
    }

    // MARK: - Page writer

    /// Owns page breaks, headers, footers and section box fragments for one rendering pass.
    @MainActor
    final class Pass {
        let doc: PlanDocument, paper: Paper, mapPanels: [PlanMapPanel], l: Localizer, totalPages: Int?
        let size: CGSize, width: CGFloat
        var ctx: UIGraphicsPDFRendererContext!
        var y: CGFloat = 0
        var pageCount = 0
        var continued: [String] = []
        var pageTitle = ""
        var pageIsOpen = false
        var reviewText: (String, Bool)?

        init(doc: PlanDocument, paper: Paper, mapPanels: [PlanMapPanel], l: Localizer, totalPages: Int?) {
            self.doc = doc; self.paper = paper; self.l = l; self.totalPages = totalPages
            self.mapPanels = doc.pages.allSatisfy { $0.id == "family-card" } ? [] : mapPanels
            size = paper.size; width = size.width - PlanPDFRenderer.margin * 2
        }

        var footerTop: CGFloat { size.height - PlanPDFRenderer.bottomMargin - PlanPDFRenderer.footerHeight }
        var x: CGFloat { PlanPDFRenderer.margin }
        func t(_ key: String, _ values: [String: String] = [:], fallback: String) -> String {
            let text = l.text(key, values)
            return text.isMissing ? Localizer.fill(fallback, values) : text.text
        }

        func run() -> Output {
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = [kCGPDFContextTitle as String: "Dry Run household plan", kCGPDFContextCreator as String: "Dry Run"]
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size), format: format)
            let data = renderer.pdfData { ctx in
                self.ctx = ctx
                for page in doc.pages { renderPage(page) }
                renderMaps()
                renderHomePanels()
                if pageIsOpen { closePage(continues: false) }
            }
            return Output(data: data, pageCount: pageCount, continuedPageIDs: Array(Set(continued)).sorted())
        }

        // MARK: Pages

        func openPage(title: String, isFirst: Bool) {
            ctx.beginPage(); pageCount += 1; pageIsOpen = true; pageTitle = title
            y = PlanPDFRenderer.topMargin
            if doc.visualSnapshot?.fictional == true || doc.pages.contains(where: { $0.sections.contains { $0.id == "identity" && $0.lines.contains { $0.style == .caveat } } }) {
                y += outlinedStrip(t("pdf.fictional", fallback: "FICTIONAL EXAMPLE — not a real household or home"), bold: true) + 6
            }
            if let banner = doc.draftTranslationBanner { y += outlinedStrip(banner, bold: true) + 6 }
            var notes: [String] = []
            if let note = doc.fallbackNote { notes.append(note) }
            if isFirst, let content = doc.contentReviewBanner { notes.append(content) }
            for note in notes {
                y += PlanPDFRenderer.drawText(note, at: CGPoint(x: x, y: y), font: Style.meta, width: width, color: Style.secondary) + 3
            }
            // Title, with the review box on the right of a card's first page.
            var titleWidth = width
            if isFirst, let (review, missing) = reviewText {
                let label = t("pdf.lastReviewed", fallback: "Last reviewed")
                let box = NSMutableAttributedString(attributedString: Style.text(label + "\n", Style.metaBold, Style.secondary))
                box.append(Style.text(review, missing ? Style.missing : Style.bodyBold, missing ? Style.secondary : Style.ink))
                let boxWidth: CGFloat = 150
                let h = measure(box, boxWidth - 12) + 10
                let rect = CGRect(x: x + width - boxWidth, y: y + 2, width: boxWidth, height: h)
                Style.ink.setStroke(); let path = UIBezierPath(rect: rect); path.lineWidth = 1; path.stroke()
                PlanPDFRenderer.draw(box, in: rect.insetBy(dx: 6, dy: 5))
                titleWidth -= boxWidth + 12
                let th = PlanPDFRenderer.drawText(title, at: CGPoint(x: x, y: y), font: Style.title, width: titleWidth)
                y += max(th, h + 2) + 8
            } else {
                y += PlanPDFRenderer.drawText(title, at: CGPoint(x: x, y: y), font: Style.title, width: titleWidth) + 8
            }
            hairline(at: y, weight: 1.5); y += 10
        }

        func closePage(continues: Bool) {
            if continues {
                let note = Style.text(t("pdf.continuedNext", fallback: "Continued on next page") + " →", Style.metaBold, Style.secondary, alignment: .right)
                PlanPDFRenderer.draw(note, in: CGRect(x: x, y: footerTop - 2, width: width, height: 14))
            }
            let top = size.height - PlanPDFRenderer.bottomMargin - 16
            hairline(at: top - 4, weight: 0.5)
            let date = PlanBuilder.displayDate(doc.generatedAt, locale: doc.locale, timeZone: .current)
            let page = totalPages.map { t("pdf.page", ["page": "\(pageCount)", "total": "\($0)"], fallback: "Page {page} of {total}") } ?? "\(pageCount)"
            let right = Style.text("\(date) · \(doc.contentVersion) · \(page)", Style.footer, Style.secondary, alignment: .right)
            let rightWidth = min(width * 0.45, ceil(right.size().width) + 4)
            PlanPDFRenderer.draw(right, in: CGRect(x: x + width - rightWidth, y: top, width: rightWidth, height: 24))
            let left = NSAttributedString(string: doc.footer, attributes: [.font: Style.footer, .foregroundColor: Style.secondary,
                .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping; return p }()])
            // The safety footer wraps (up to three lines) rather than being cut off in longer languages.
            PlanPDFRenderer.draw(left, in: CGRect(x: x, y: top, width: width - rightWidth - 12, height: 40))
            pageIsOpen = false
        }

        /// Starts a continuation page for `id` when `height` does not fit. Returns true when it broke.
        @discardableResult
        func ensure(_ height: CGFloat, id: String) -> Bool {
            guard y + height > footerTop - 14 else { return false }
            closePage(continues: true)
            continued.append(id)
            openPage(title: t("pdf.continued", ["title": basePageTitle], fallback: "{title} (continued)"), isFirst: false)
            return true
        }

        // MARK: Drawing helpers

        func hairline(at y: CGFloat, weight: CGFloat) {
            let path = UIBezierPath(); path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x + width, y: y))
            path.lineWidth = weight; Style.ink.setStroke(); path.stroke()
        }

        func outlinedStrip(_ text: String, bold: Bool) -> CGFloat {
            let s = Style.text(text, bold ? Style.metaBold : Style.meta)
            let h = measure(s, width - 12) + 8
            let rect = CGRect(x: x, y: y, width: width, height: h)
            let path = UIBezierPath(rect: rect); path.lineWidth = 1; Style.ink.setStroke(); path.stroke()
            PlanPDFRenderer.draw(s, in: rect.insetBy(dx: 6, dy: 4))
            return h
        }

        /// Heading band; `critical` inverts it (white on black).
        func bandHeight(_ heading: String, width: CGFloat) -> CGFloat {
            max(22, measure(bandText(heading, color: Style.ink), width - 30) + 9)
        }
        func bandText(_ heading: String, color: UIColor) -> NSAttributedString {
            NSAttributedString(string: heading.uppercased(with: Locale(identifier: doc.locale)), attributes: [
                .font: Style.bandFont, .foregroundColor: color, .kern: 0.5,
                .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping; return p }()])
        }
        /// Heading band; `critical` inverts it (white on black). Long headings wrap rather than truncate.
        func band(_ heading: String, symbol: String, critical: Bool, at origin: CGPoint, width: CGFloat, height: CGFloat? = nil) -> CGFloat {
            let h = height ?? bandHeight(heading, width: width)
            let rect = CGRect(x: origin.x, y: origin.y, width: width, height: h)
            (critical ? Style.ink : Style.band).setFill(); UIBezierPath(rect: rect).fill()
            let color: UIColor = critical ? .white : Style.ink
            PlanPDFRenderer.drawSymbol(symbol, in: CGRect(x: origin.x + 7, y: origin.y + 5.5, width: 11, height: 11), color: color)
            let text = bandText(heading, color: color)
            PlanPDFRenderer.draw(text, in: CGRect(x: origin.x + 24, y: origin.y + 4.5, width: width - 30, height: measure(text, width - 30)))
            return h
        }

        func strokeBox(top: CGFloat, bottom: CGFloat, critical: Bool, dashed: Bool = false, x boxX: CGFloat? = nil, width boxWidth: CGFloat? = nil) {
            let rect = CGRect(x: boxX ?? x, y: top, width: boxWidth ?? width, height: max(0, bottom - top))
            let path = UIBezierPath(rect: rect); path.lineWidth = critical ? 2 : 0.75
            if dashed { path.setLineDash([4, 3], count: 2, phase: 0) }
            (critical ? Style.ink : Style.rule).setStroke(); path.stroke()
        }

        /// A bordered section with a band and rows. Rows never split unless taller than a whole page.
        func section(id: String, heading: String, rows: [Row], critical: Bool, pageID: String) {
            let inset: CGFloat = 8
            let inner = width - inset * 2
            var rows = rows
            let bandH = bandHeight(heading, width: width)
            let firstHeight = rows.first.map { min($0.height(width: inner), 60) } ?? 0
            ensure(bandH + firstHeight + 8, id: pageID)
            sectionStartPage = pageCount
            var top = y
            y += band(heading, symbol: PlanPDFRenderer.symbol(for: id), critical: critical, at: CGPoint(x: x, y: y), width: width)
            y += 2
            var index = 0
            while !rows.isEmpty {
                let row = rows.removeFirst()
                let h = row.height(width: inner)
                if y + h > footerTop - 14 {
                    let fullPage = footerTop - 14 - (PlanPDFRenderer.topMargin + 90) - bandH
                    if h > fullPage || footerTop - 14 - y > 80 {
                        // Taller than a page (or plenty of room left): split at the visible text range.
                        let (head, tail) = row.split(width: inner, height: footerTop - 14 - y)
                        head.draw(at: CGPoint(x: x + inset, y: y), width: inner)
                        y = footerTop - 14
                        if let tail { rows.insert(tail, at: 0) }
                    } else {
                        rows.insert(row, at: 0)
                    }
                    strokeBox(top: top, bottom: y + 2, critical: critical)
                    closePage(continues: true); continued.append(pageID)
                    openPage(title: t("pdf.continued", ["title": basePageTitle], fallback: "{title} (continued)"), isFirst: false)
                    top = y
                    y += band(t("pdf.continued", ["title": heading], fallback: "{title} (continued)"), symbol: PlanPDFRenderer.symbol(for: id), critical: critical, at: CGPoint(x: x, y: y), width: width)
                    y += 2
                    continue
                }
                if index > 0 && row.separator {
                    let path = UIBezierPath(); path.move(to: CGPoint(x: x + inset, y: y)); path.addLine(to: CGPoint(x: x + width - inset, y: y))
                    path.lineWidth = 0.4; UIColor(white: 0.75, alpha: 1).setStroke(); path.stroke()
                }
                row.draw(at: CGPoint(x: x + inset, y: y), width: inner)
                y += h; index += 1
            }
            y += 4
            strokeBox(top: top, bottom: y, critical: critical)
            y += 10
        }

        var basePageTitle = ""

        // MARK: Content

        func renderPage(_ page: PlanPage) {
            if pageIsOpen { closePage(continues: false) }
            basePageTitle = page.title
            let isCard = page.id == "family-card"
            reviewText = nil
            if isCard, let review = page.sections.first(where: { $0.id == "review" })?.lines.first {
                reviewText = (review.parts?.fields.first?.value ?? review.text, review.parts?.isMissing ?? false)
            }
            openPage(title: page.title, isFirst: true)
            if isCard { renderCard(page) } else { renderGeneric(page) }
            if page.id == doc.pages.last?.id, !doc.sourceIDs.isEmpty {
                let names = doc.sourceIDs.map { id in PlanPDFRenderer.bundledContent?.source(id).map { "\($0.publisher) (\(id))" } ?? id }
                let row = Row(body: Style.text(names.joined(separator: " · "), Style.meta, Style.secondary), padding: 4, separator: false)
                section(id: "sources", heading: PlanPDFRenderer.exportText("sources", locale: doc.locale), rows: [row], critical: false, pageID: page.id)
            }
            if page.kind == .essentials, page.id != "family-card", let snapshot = doc.visualSnapshot {
                let missing = PlanMapSelection.missingExtents(homeCoordinate: snapshot.homeCoordinate, places: snapshot.savedPlaces,
                                                               renderedExtentIDs: Set(mapPanels.compactMap(\.extentID)))
                if !missing.isEmpty {
                    let neighborhood = t("map.neighborhood", fallback: "Neighborhood")
                    let names = missing.map { $0.title(neighborhood: neighborhood) }.joined(separator: ", ")
                    let notice = l.text("map.snapshotMissing", ["panels": names])
                    let text = notice.isMissing ? PlanPDFRenderer.exportText("mapUnavailable", locale: doc.locale) + " (" + names + ")" : notice.text
                    section(id: "places", heading: t("map.neighborhood", fallback: "Neighborhood"),
                            rows: [Row(body: Style.text(text), symbol: "map", separator: false)], critical: false, pageID: page.id)
                }
            }
        }

        func renderCard(_ page: PlanPage) {
            let sections = Dictionary(page.sections.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            // Household identity directly under the title.
            if let identity = sections["identity"] {
                for line in identity.lines where line.style != .caveat {
                    let missing = line.parts?.isMissing ?? false
                    let font = line.parts?.subject != nil ? Style.name : (missing ? Style.missing : Style.body)
                    y += PlanPDFRenderer.drawText(line.text, at: CGPoint(x: x, y: y), font: font, width: width, color: missing ? Style.secondary : Style.ink) + 2
                }
                y += 8
            }
            for section in page.sections {
                switch section.id {
                case "identity", "review", "backupMeetingPlace": continue
                case "outsideMeetingPoint":
                    meetups(near: section, backup: sections["backupMeetingPlace"], pageID: page.id)
                default:
                    self.section(id: section.id, heading: section.heading, rows: rows(for: section), critical: section.isSafetyCritical && section.id != "contacts", pageID: page.id)
                }
            }
        }

        func rows(for section: PlanSection) -> [Row] {
            section.lines.map { line in
                guard let parts = line.parts else { return PlanPDFRenderer.bulletRow(line) }
                let missing = parts.isMissing
                if section.id == "contacts" {
                    let left = NSMutableAttributedString(attributedString: Style.text(parts.subject ?? "", Style.name))
                    if let detail = parts.detail { left.append(Style.text("\n" + detail, Style.meta, Style.secondary)) }
                    if parts.subject == nil { return Row(body: Style.text(line.text, Style.missing, Style.secondary)) }
                    let phone = parts.phone.map { Style.text($0, Style.phone, alignment: .right) }
                        ?? Style.text(parts.fields.first?.value ?? "", Style.missing, Style.secondary, alignment: .right)
                    return Row(left: left, body: NSAttributedString(string: ""), right: phone, leftWidth: 260, rightWidth: max(150, width - 260 - 40 - 16))
                }
                let body = NSMutableAttributedString()
                for (i, field) in parts.fields.enumerated() {
                    if i > 0 { body.append(Style.text("\n")) }
                    if let label = field.label { body.append(Style.text(label + ": ", Style.bodyBold)) }
                    body.append(Style.text(field.value, missing ? Style.missing : Style.body, missing ? Style.secondary : Style.ink))
                }
                if let subject = parts.subject {
                    return Row(left: Style.text(subject, Style.name), body: body, leftWidth: 120)
                }
                return Row(body: body)
            }
        }

        /// Near-home and outside-the-neighborhood meetups side by side, with the same numbers as the map.
        func meetups(near: PlanSection, backup: PlanSection?, pageID: String) {
            let pair = [near, backup].compactMap { $0 }
            let gutter: CGFloat = 12
            let columnWidth = pair.count == 2 ? (width - gutter) / 2 : width
            func content(_ section: PlanSection) -> NSAttributedString {
                let s = NSMutableAttributedString()
                for (i, line) in section.lines.enumerated() {
                    if i > 0 { s.append(Style.text("\n\n")) }
                    guard let parts = line.parts else { s.append(Style.text(line.text)); continue }
                    if let subject = parts.subject { s.append(Style.text(subject + "\n", Style.name)) }
                    for (j, field) in parts.fields.enumerated() {
                        if j > 0 { s.append(Style.text("\n")) }
                        if let label = field.label { s.append(Style.text(label + ": " + field.value, Style.meta, Style.secondary)); continue }
                        s.append(Style.text(field.value, parts.isMissing ? Style.missing : Style.body, parts.isMissing ? Style.secondary : Style.ink))
                    }
                }
                return s
            }
            let bodies = pair.map(content)
            let inner = columnWidth - 16
            let contentHeight = bodies.map { measure($0, inner) }.max() ?? 0
            let bandH = pair.map { bandHeight($0.heading, width: columnWidth) }.max() ?? 22
            let total = bandH + contentHeight + 16
            if pair.count < 2 || total > footerTop - 14 - (PlanPDFRenderer.topMargin + 90) {
                // Too tall to keep side by side: stacked sections that can continue across pages.
                for s in pair { section(id: s.id, heading: s.heading, rows: rows(for: s), critical: false, pageID: pageID) }
                return
            }
            ensure(total, id: pageID)
            let top = y
            for (i, s) in pair.enumerated() {
                let bx = x + CGFloat(i) * (columnWidth + gutter)
                _ = band(s.heading, symbol: PlanPDFRenderer.symbol(for: s.id), critical: false, at: CGPoint(x: bx, y: top), width: columnWidth, height: bandH)
                PlanPDFRenderer.draw(bodies[i], in: CGRect(x: bx + 8, y: top + bandH + 7, width: inner, height: measure(bodies[i], inner)))
                strokeBox(top: top, bottom: top + total, critical: false, dashed: s.lines.first?.parts?.isMissing == true, x: bx, width: columnWidth)
            }
            y = top + total + 10
        }

        /// Section content already printed, by page, so repeated blocks (help lines, helpers, equipment) print once.
        var printedSections: [String: Int] = [:]
        var sectionStartPage = 0

        func renderGeneric(_ page: PlanPage) {
            for section in page.sections {
                let key = section.heading + "\u{1}" + section.lines.map(\.text).joined(separator: "\u{1}")
                if let earlier = printedSections[key], earlier != pageCount {
                    let note = t("pdf.sameAsPage", ["page": "\(earlier)"], fallback: "Same as page {page}.")
                    self.section(id: section.id, heading: section.heading, rows: [Row(body: Style.text(note, Style.missing, Style.secondary), padding: 3, separator: false)],
                                 critical: false, pageID: page.id)
                    continue
                }
                self.section(id: section.id, heading: section.heading, rows: rows(for: section), critical: section.isSafetyCritical && section.lines.contains { $0.style == .prohibition }, pageID: page.id)
                printedSections[key] = sectionStartPage
            }
        }

        // MARK: Map pages

        func renderMaps() {
            for panel in mapPanels {
                if pageIsOpen { closePage(continues: false) }
                basePageTitle = panel.title
                openPage(title: panel.title, isFirst: false)
                let imageHeight = min(width * panel.image.size.height / max(panel.image.size.width, 1), footerTop - y - 120)
                let imageWidth = imageHeight * panel.image.size.width / max(panel.image.size.height, 1)
                let rect = CGRect(x: x + (width - imageWidth) / 2, y: y, width: imageWidth, height: imageHeight)
                // Apple's whole image, including its logo and legal attribution, is drawn unaltered.
                // JPEG keeps a map page to a few hundred kilobytes; Apple's attribution stays part of the image.
                let mapImage = panel.image.jpegData(compressionQuality: 0.82).flatMap(UIImage.init(data:)) ?? panel.image
                mapImage.draw(in: rect)
                let frame = UIBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5)); frame.lineWidth = 0.75; Style.rule.setStroke(); frame.stroke()
                y = rect.maxY + 6
                y += PlanPDFRenderer.drawText(t("pdf.mapFrame", fallback: "Map data and imagery: Apple Maps. Numbers match the list below."), at: CGPoint(x: x, y: y), font: Style.meta, width: width, color: Style.secondary) + 8
                var rows: [Row] = []
                if panel.showsHome {
                    rows.append(Row(left: PlanPDFRenderer.markerLabel(.home, "H"), body: Style.text(t("pdf.legend.home", fallback: "Home"), Style.bodyBold), leftWidth: 22))
                }
                for line in panel.legend {
                    if let (number, rest) = PlanPDFRenderer.numbered(line) {
                        let kind = panel.markerKinds[number] ?? .resource
                        rows.append(Row(left: PlanPDFRenderer.markerLabel(kind, "\(number)"), body: Style.text(rest), leftWidth: 22))
                    } else {
                        rows.append(Row(left: NSAttributedString(string: " "), body: Style.text(line, Style.meta, Style.secondary), leftWidth: 22, separator: false))
                    }
                }
                // Meeting places saved as text only keep their number in the key, marked as having no map pin.
                if panel.showsHome, let snapshot = doc.visualSnapshot {
                    for (index, place) in snapshot.savedPlaces.enumerated() where place.coordinate == nil
                        && (place.purpose == .outsideMeetingPoint || place.purpose == .backupMeetingPlace) {
                        let text = [place.label, place.findingInstructions].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                            + " — " + t("pdf.noPin", fallback: "no map pin saved")
                        rows.append(Row(left: PlanPDFRenderer.markerLabel(.meetup, "\(index + 1)"), body: Style.text(text), leftWidth: 22))
                    }
                }
                if !rows.isEmpty {
                    section(id: "places", heading: t("pdf.legend", fallback: "Key"), rows: rows, critical: false, pageID: "map-legend")
                }
            }
        }

        // MARK: Home diagrams

        func renderHomePanels() {
            guard doc.pages.contains(where: { $0.id != "family-card" }), let snapshot = doc.visualSnapshot, let home = snapshot.home else { return }
            var seenNoRoute: Set<String> = []
            for panel in snapshot.homePanels {
                // Several people with the same "no route established" stage would print identical pages: print one.
                if let route = panel.route, route.primary == nil, route.alternative == nil {
                    let key = [panel.scenarioID ?? "", panel.floorID, panel.spatialState?.stageID ?? "", route.noRouteReason?.rawValue ?? "", route.request.startSpaceID].joined(separator: "|")
                    if !seenNoRoute.insert(key).inserted { continue }
                }
                if pageIsOpen { closePage(continues: false) }
                let title = panel.title(in: snapshot)
                basePageTitle = title
                openPage(title: title, isFirst: false)
                let detailText = snapshot.panelDetails?[panel.id] ?? panel.details(in: snapshot, localizer: l)
                let detailHeight = detailText.reduce(CGFloat(40)) { $0 + measure(Style.text($1), width - 16 - Row.symbolWidth) + 6 }
                // Measure what the diagram will show (drawn offscreen), so its key and notes fit on the same page.
                let probeUsed = PlanPDFRenderer.elementsDrawn(home, floorID: panel.floorID, routes: panel.paths, state: panel.spatialState, selectedRoute: panel.route)
                let legendHeight = legend(probeUsed, draw: false)
                // The diagram gives way to its key and notes, but never shrinks below a readable size.
                let diagramHeight = max(min(width * 0.72, footerTop - 14 - y - 8 - legendHeight - 6 - detailHeight), min(200, width * 0.4))
                let rect = CGRect(x: x, y: y, width: width, height: diagramHeight)
                let frame = UIBezierPath(rect: rect); frame.lineWidth = 0.75; Style.rule.setStroke(); frame.stroke()
                let used = PlanPDFRenderer.drawHome(home, floorID: panel.floorID, routes: panel.paths, state: panel.spatialState,
                                                    selectedRoute: panel.route, rect: rect.insetBy(dx: 6, dy: 6), locale: doc.locale, exitLabel: t("pdf.exit", fallback: "EXIT"))
                y = rect.maxY + 8
                y += legend(used) + 6
                let details = (snapshot.panelDetails?[panel.id] ?? panel.details(in: snapshot, localizer: l)).map {
                    Row(body: Style.text($0), symbol: "info.circle", padding: 3, separator: false)
                }
                if !details.isEmpty {
                    section(id: "steps", heading: PlanPDFRenderer.exportText("exercise", locale: doc.locale), rows: details, critical: false, pageID: "home-\(panel.id)")
                }
            }
        }

        /// A key generated from what the diagram actually drew; never a fixed list.
        /// Lays out the key in rows of three; with `draw: false` it only measures, so the diagram can be sized first.
        @discardableResult
        func legend(_ used: Set<DiagramElement>, draw: Bool = true) -> CGFloat {
            let order: [DiagramElement] = [.wall, .door, .window, .unconfirmed, .blocked, .exit, .primary, .alternative, .affected, .exposed, .shelter, .stairs, .start, .furniture,
                                           .smokeAlarm, .coAlarm, .fireExtinguisher, .shutoff, .supplies, .medicalEquipment]
            let items = order.filter(used.contains)
            guard !items.isEmpty else { return 0 }
            let columns = 3
            let columnWidth = width / CGFloat(columns)
            var rowTop: CGFloat = 0
            for start in stride(from: 0, to: items.count, by: columns) {
                let row = Array(items[start..<min(start + columns, items.count)])
                let labels = row.map { Style.text(t("pdf.legend.\($0.rawValue)", fallback: $0.rawValue), Style.meta) }
                let h = max(16, labels.map { measure($0, columnWidth - 36) }.max() ?? 0) + 3
                if draw {
                    for (i, item) in row.enumerated() {
                        let cx = x + CGFloat(i) * columnWidth
                        PlanPDFRenderer.drawLegendSample(item, in: CGRect(x: cx, y: y + rowTop + 3, width: 26, height: 11))
                        PlanPDFRenderer.draw(labels[i], in: CGRect(x: cx + 32, y: y + rowTop + 1, width: columnWidth - 36, height: h))
                    }
                }
                rowTop += h
            }
            return rowTop
        }
    }

    // MARK: - Text primitives

    static func bulletRow(_ line: PlanLine) -> Row {
        var text = line.text
        if line.isFallback { text += "  [EN]" }
        let font = line.style == .prohibition ? Style.bodyBold : Style.body
        let color = line.style == .caveat ? Style.secondary : Style.ink
        let symbol: String
        switch line.style {
        case .prohibition: symbol = "exclamationmark.triangle.fill"
        case .contact: symbol = "phone.fill"
        case .caveat: symbol = "info.circle"
        case .normal: symbol = "circle.fill"
        }
        var row = Row(body: Style.text(text, font, color), symbol: symbol, padding: 3, separator: false)
        if line.style == .normal { row.symbol = "smallcircle.filled.circle" }
        return row
    }

    static func numbered(_ line: String) -> (Int, String)? {
        guard let dot = line.firstIndex(of: "."), let n = Int(line[..<dot]), line[line.index(after: dot)...].hasPrefix(" ") else { return nil }
        return (n, String(line[line.index(dot, offsetBy: 2)...]))
    }

    static func markerLabel(_ kind: PlanMapMarkerKind, _ label: String) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = markerImage(kind, label: label, diameter: 18)
        attachment.bounds = CGRect(x: 0, y: -4, width: 18, height: 18)
        return NSAttributedString(attachment: attachment)
    }

    /// Home: black rounded square "H". Meeting place: filled black circle. Saved resource: white ring.
    static func markerImage(_ kind: PlanMapMarkerKind, label: String, diameter d: CGFloat) -> UIImage {
        MarkerPoint.image(kind, label: label, diameter: d)
    }

    /// Symbols are rasterized at 4x before drawing. Drawn directly into a PDF context they are embedded as a private
    /// glyph font that some viewers and printers show as solid squares.
    /// Rasterized symbols are cached so a PDF embeds each icon once rather than once per use (keeps files small).
    private static var symbolCache: [String: UIImage] = [:]

    static func drawSymbol(_ name: String, in rect: CGRect, color: UIColor = .black) {
        let pointSize = (rect.height * 4).rounded()
        let key = "\(name)|\(pointSize)|\(color == .white ? "w" : "k")"
        let bitmap: UIImage
        if let cached = symbolCache[key] { bitmap = cached } else {
            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            guard let symbol = UIImage(systemName: name, withConfiguration: config)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return }
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
            bitmap = UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in symbol.draw(at: .zero) }
            symbolCache[key] = bitmap
        }
        let scale = min(rect.width / bitmap.size.width, rect.height / bitmap.size.height)
        let size = CGSize(width: bitmap.size.width * scale, height: bitmap.size.height * scale)
        bitmap.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }

    static func draw(_ s: NSAttributedString, in rect: CGRect) {
        s.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    @discardableResult
    static func drawText(_ s: String, at p: CGPoint, font: UIFont, width: CGFloat, color: UIColor = .black) -> CGFloat {
        let a = Style.text(s, font, color)
        let h = measure(a, width)
        draw(a, in: CGRect(x: p.x, y: p.y, width: width, height: h))
        return ceil(h)
    }

    /// Splits at Core Text's actual visible UTF-16 range, so a long note continues instead of being clipped.
    static func split(_ s: NSAttributedString, width: CGFloat, height: CGFloat) -> (NSAttributedString, NSAttributedString?) {
        let setter = CTFramesetterCreateWithAttributedString(s as CFAttributedString)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        // Normal line heights fit; the minimum still guarantees progress for malformed oversized font data.
        let count = min(s.length, max(1, CTFrameGetVisibleStringRange(frame).length))
        let head = s.attributedSubstring(from: NSRange(location: 0, length: count))
        guard count < s.length else { return (head, nil) }
        var tailRange = NSRange(location: count, length: s.length - count)
        // Do not start a continuation with the line break that ended the previous fragment.
        while tailRange.length > 0, (s.string as NSString).character(at: tailRange.location) == 10 { tailRange.location += 1; tailRange.length -= 1 }
        return (head, tailRange.length > 0 ? s.attributedSubstring(from: tailRange) : nil)
    }
}

@MainActor
func measure(_ s: NSAttributedString, _ width: CGFloat) -> CGFloat {
    guard s.length > 0 else { return 0 }
    return ceil(s.boundingRect(with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
}

/// What a home diagram actually drew, so its key lists only those symbols.
enum DiagramElement: String, Hashable, CaseIterable {
    case wall, door, window, unconfirmed, blocked, exit, primary, alternative, affected, exposed, shelter, stairs, start, furniture
    case smokeAlarm, coAlarm, fireExtinguisher, shutoff, supplies, medicalEquipment
    init?(_ kind: AnnotationKind) {
        switch kind {
        case .smokeAlarm: self = .smokeAlarm
        case .coAlarm: self = .coAlarm
        case .fireExtinguisher: self = .fireExtinguisher
        case .utilityShutoffGas, .utilityShutoffWater, .utilityShutoffElectric: self = .shutoff
        case .supplies: self = .supplies
        case .medicalEquipment: self = .medicalEquipment
        default: return nil
        }
    }
    var symbol: String? {
        switch self {
        case .smokeAlarm, .coAlarm: "sensor.fill"
        case .fireExtinguisher: "fire.extinguisher.fill"
        case .shutoff: "bolt.fill"
        case .supplies: "shippingbox.fill"
        case .medicalEquipment: "cross.case.fill"
        default: nil
        }
    }
}

extension PlanPDFRenderer {
    static func drawLegendSample(_ element: DiagramElement, in r: CGRect) {
        let mid = CGPoint(x: r.minX, y: r.midY), end = CGPoint(x: r.maxX, y: r.midY)
        func line(_ width: CGFloat, dash: [CGFloat] = [], color: UIColor = .black) {
            let p = UIBezierPath(); p.move(to: mid); p.addLine(to: end); p.lineWidth = width
            if !dash.isEmpty { p.setLineDash(dash, count: dash.count, phase: 0) }
            color.setStroke(); p.stroke()
        }
        switch element {
        case .wall: line(2.5)
        case .door:
            line(2.5); UIColor.white.setFill(); UIRectFill(CGRect(x: r.minX + 7, y: r.midY - 3, width: 12, height: 6))
            jambs(CGPoint(x: r.minX + 7, y: r.midY), CGPoint(x: r.minX + 19, y: r.midY))
        case .window:
            line(2.5); UIColor.white.setFill(); UIRectFill(CGRect(x: r.minX + 5, y: r.midY - 3, width: 16, height: 6))
            windowMark(CGPoint(x: r.minX + 5, y: r.midY), CGPoint(x: r.minX + 21, y: r.midY))
        case .unconfirmed: line(1.5, dash: [3, 3])
        case .blocked: drawText("×", at: CGPoint(x: r.minX + 7, y: r.minY - 5), font: .systemFont(ofSize: 16, weight: .heavy), width: 20)
        case .exit: exitArrow(at: CGPoint(x: r.minX + 8, y: r.midY), direction: CGVector(dx: 1, dy: 0))
        case .primary: line(3)
        case .alternative: line(2.5, dash: [7, 4], color: UIColor(white: 0.35, alpha: 1))
        case .affected: hatch(UIBezierPath(rect: r), fill: UIColor(white: 0.80, alpha: 1)); UIColor.black.setStroke(); UIBezierPath(rect: r).stroke()
        case .exposed:
            let p = UIBezierPath(rect: r.insetBy(dx: 1, dy: 1)); p.lineWidth = 2; p.setLineDash([3, 2], count: 2, phase: 0); UIColor.black.setStroke(); p.stroke()
        case .shelter: drawSymbol("shield.lefthalf.filled", in: CGRect(x: r.minX + 7, y: r.minY - 1, width: 13, height: 13))
        case .stairs: drawSymbol("stairs", in: CGRect(x: r.minX + 7, y: r.minY - 1, width: 13, height: 13))
        case .start: drawSymbol("person.crop.circle.fill", in: CGRect(x: r.minX + 7, y: r.minY - 1, width: 13, height: 13))
        case .furniture: UIColor(white: 0.85, alpha: 1).setFill(); UIRectFill(CGRect(x: r.minX + 4, y: r.minY, width: 18, height: r.height))
        default: if let symbol = element.symbol { drawSymbol(symbol, in: CGRect(x: r.minX + 7, y: r.minY - 1, width: 13, height: 13)) }
        }
    }

    static func jambs(_ a: CGPoint, _ b: CGPoint) {
        let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 0.001)
        let nx = -dy / len * 4, ny = dx / len * 4
        let p = UIBezierPath()
        for q in [a, b] { p.move(to: CGPoint(x: q.x - nx, y: q.y - ny)); p.addLine(to: CGPoint(x: q.x + nx, y: q.y + ny)) }
        p.lineWidth = 1; UIColor.black.setStroke(); p.stroke()
    }

    static func windowMark(_ a: CGPoint, _ b: CGPoint) {
        let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 0.001)
        let nx = -dy / len * 1.6, ny = dx / len * 1.6
        let p = UIBezierPath()
        for s in [-1.0, 1.0] { p.move(to: CGPoint(x: a.x + nx * s, y: a.y + ny * s)); p.addLine(to: CGPoint(x: b.x + nx * s, y: b.y + ny * s)) }
        p.move(to: CGPoint(x: a.x - nx, y: a.y - ny)); p.addLine(to: CGPoint(x: a.x + nx, y: a.y + ny))
        p.move(to: CGPoint(x: b.x - nx, y: b.y - ny)); p.addLine(to: CGPoint(x: b.x + nx, y: b.y + ny))
        p.lineWidth = 0.9; UIColor.black.setStroke(); p.stroke()
    }

    static func exitArrow(at p: CGPoint, direction d: CGVector) {
        let len = max(hypot(d.dx, d.dy), 0.001), ux = d.dx / len, uy = d.dy / len
        let tip = CGPoint(x: p.x + ux * 11, y: p.y + uy * 11)
        let path = UIBezierPath()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: p.x - uy * 6, y: p.y + ux * 6))
        path.addLine(to: CGPoint(x: p.x + uy * 6, y: p.y - ux * 6))
        path.close(); UIColor.black.setFill(); path.fill()
    }

    static func hatch(_ path: UIBezierPath, fill: UIColor) {
        fill.setFill(); path.fill()
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState(); path.addClip()
        let b = path.bounds
        let lines = UIBezierPath()
        var x = b.minX - b.height
        while x < b.maxX { lines.move(to: CGPoint(x: x, y: b.maxY)); lines.addLine(to: CGPoint(x: x + b.height, y: b.minY)); x += 6 }
        lines.lineWidth = 0.6; UIColor(white: 0.35, alpha: 1).setStroke(); lines.stroke()
        ctx.restoreGState()
    }

    static func arrowhead(from a: CGPoint, to b: CGPoint, size: CGFloat, color: UIColor) {
        let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 0.001), ux = dx / len, uy = dy / len
        let base = CGPoint(x: b.x - ux * size, y: b.y - uy * size)
        let p = UIBezierPath(); p.move(to: b)
        p.addLine(to: CGPoint(x: base.x - uy * size * 0.55, y: base.y + ux * size * 0.55))
        p.addLine(to: CGPoint(x: base.x + uy * size * 0.55, y: base.y - ux * size * 0.55))
        p.close(); color.setFill(); p.fill()
    }

    /// Same floor polygons, openings and exact route-leg points as the on-device canvas.
    /// Returns the elements it drew, for the key.
    @discardableResult
    static func drawHome(_ home: HomeModel, floorID: String, routes: [RoutePath], state: SpatialExerciseState? = nil,
                         selectedRoute: RouteResult? = nil, rect: CGRect, locale: String = "en", exitLabel: String = "EXIT") -> Set<DiagramElement> {
        var used: Set<DiagramElement> = []
        let rooms = home.spaces.filter { $0.floorID == floorID }
        let pts = rooms.flatMap(\.polygon)
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(), let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return used }
        let pad: CGFloat = 26
        let scale = min((rect.width - pad * 2) / max(maxX - minX, 1), (rect.height - pad * 2) / max(maxY - minY, 1))
        let offsetX = rect.minX + (rect.width - (maxX - minX) * scale) / 2
        let offsetY = rect.minY + (rect.height - (maxY - minY) * scale) / 2
        func point(_ p: Vec2) -> CGPoint { CGPoint(x: offsetX + (p.x - minX) * scale, y: offsetY + (maxY - p.y) * scale) }
        func polygon(_ points: [Vec2]) -> UIBezierPath {
            let path = UIBezierPath()
            if let first = points.first { path.move(to: point(first)); for p in points.dropFirst() { path.addLine(to: point(p)) }; path.close() }
            return path
        }
        let affected = Set(state?.affectedSpaceIDs ?? [])
        let exposed = Set(state?.exposedSpaceIDs ?? [])
        // 1. Room fills (affected rooms hatched so the state survives grayscale printing).
        for room in rooms {
            let path = polygon(room.polygon)
            if affected.contains(room.id) { hatch(path, fill: UIColor(white: 0.82, alpha: 1)); used.insert(.affected) }
            else { UIColor.white.setFill(); path.fill() }
        }
        for obstacle in home.obstacles where obstacle.floorID == floorID { UIColor(white: 0.85, alpha: 1).setFill(); polygon(obstacle.polygon).fill(); used.insert(.furniture) }
        // 2. Walls.
        for room in rooms {
            let path = polygon(room.polygon); path.lineWidth = 2.5; path.lineJoinStyle = .miter; UIColor.black.setStroke(); path.stroke()
            used.insert(.wall)
            if exposed.contains(room.id) {
                let inner = polygon(inset(room.polygon, by: 0.25))
                inner.lineWidth = 2; inner.setLineDash([3, 2], count: 2, phase: 0); inner.stroke(); used.insert(.exposed)
            }
            if state?.destinationSpaceID == room.id {
                let inner = polygon(inset(room.polygon, by: 0.18)); inner.lineWidth = 3; inner.stroke(); used.insert(.shelter)
            }
        }
        // 3. Openings: knock a real gap out of the wall, then mark the kind.
        for portal in home.portals where portal.floorID == floorID {
            let a = point(portal.a), b = point(portal.b)
            let gap = UIBezierPath(); gap.move(to: a); gap.addLine(to: b); gap.lineWidth = 5; gap.lineCapStyle = .butt
            UIColor.white.setStroke(); gap.stroke()
            let status = HomeScenePresentation.openingStatus(portal, in: home, state: state, request: selectedRoute?.request)
            if portal.kind == .window { windowMark(a, b); used.insert(.window) } else { jambs(a, b); used.insert(.door) }
            if status == .unconfirmed {
                let p = UIBezierPath(); p.move(to: a); p.addLine(to: b); p.lineWidth = 1.2; p.setLineDash([2.5, 2], count: 2, phase: 0)
                UIColor.black.setStroke(); p.stroke(); used.insert(.unconfirmed)
            }
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            if status == .unavailable || (portal.kind == .window && state?.hazard == .tornado) {
                drawText("×", at: CGPoint(x: mid.x - 5, y: mid.y - 11), font: .systemFont(ofSize: 17, weight: .heavy), width: 20); used.insert(.blocked)
            }
            if status == .availableExit {
                // Point the arrow away from the room it serves.
                let room = [portal.sideA, portal.sideB].compactMap { side -> Space? in if case .space(let id) = side { return home.space(id) }; return nil }.first
                var normal = CGVector(dx: -(b.y - a.y), dy: b.x - a.x)
                if let room {
                    let c = point(Geometry.centroid(room.polygon))
                    if (c.x - mid.x) * normal.dx + (c.y - mid.y) * normal.dy > 0 { normal = CGVector(dx: -normal.dx, dy: -normal.dy) }
                }
                let len = max(hypot(normal.dx, normal.dy), 0.001)
                let start = CGPoint(x: mid.x + normal.dx / len * 4, y: mid.y + normal.dy / len * 4)
                exitArrow(at: start, direction: normal); used.insert(.exit)
                // The word sits beyond the arrow tip so the two never overprint.
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8.5, weight: .heavy)]
                let w = (exitLabel as NSString).size(withAttributes: attrs).width
                let ux = normal.dx / len, uy = normal.dy / len
                let anchor = CGPoint(x: mid.x + ux * (19 + w / 2 * abs(ux)), y: mid.y + uy * (19 + 5 * abs(uy)))
                (exitLabel as NSString).draw(at: CGPoint(x: anchor.x - w / 2, y: anchor.y - 5), withAttributes: attrs)
            }
        }
        // 4. Routes: exact legs. Primary solid black with an arrowhead; alternative dashed gray.
        for (index, route) in routes.enumerated() {
            let color = index == 0 ? UIColor.black : UIColor(white: 0.35, alpha: 1)
            for leg in route.legs where leg.floorID == floorID {
                guard let first = leg.points.first else { continue }
                let path = UIBezierPath(); path.move(to: point(first)); for p in leg.points.dropFirst() { path.addLine(to: point(p)) }
                path.lineWidth = index == 0 ? 3 : 2.5; path.lineCapStyle = .round; path.lineJoinStyle = .round
                if index > 0 { path.setLineDash([7, 4], count: 2, phase: 0) }
                color.setStroke(); path.stroke()
                if leg.points.count >= 2 { arrowhead(from: point(leg.points[leg.points.count - 2]), to: point(leg.points[leg.points.count - 1]), size: 8, color: color) }
                used.insert(index == 0 ? .primary : .alternative)
            }
        }
        // 5. Stairs.
        for connector in home.connectors {
            for (spaceID, p) in [(connector.fromSpaceID, connector.fromPoint), (connector.toSpaceID, connector.toPoint)] where home.space(spaceID)?.floorID == floorID {
                let c = point(p); drawSymbol("stairs", in: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)); used.insert(.stairs)
            }
        }
        // 6. Markers: selected annotations (alarms, extinguisher, supplies) and the recorded starting room.
        // Exterior annotations are described in text; anything outside the diagram frame is not drawn.
        var markers: [CGRect] = []
        for annotation in home.annotations where annotation.floorID == floorID {
            guard let position = annotation.position else { continue }
            let c = point(position)
            let disc = CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16)
            guard rect.insetBy(dx: 4, dy: 4).contains(disc) else { continue }
            UIColor.white.setFill(); UIBezierPath(ovalIn: disc).fill()
            drawSymbol(annotationSymbol(annotation.kind), in: disc.insetBy(dx: 2.5, dy: 2.5))
            markers.append(disc)
            if let element = DiagramElement(annotation.kind) { used.insert(element) }
        }
        // A failed route still has a recorded starting room. Match the phone's illustrative marker;
        // never substitute a path endpoint or imply a measured/live occupant position.
        if let room = HomeScenePresentation.startingRoom(in: home, route: selectedRoute), room.floorID == floorID,
           let position = HomeScenePresentation.startingRoomPosition(in: home, route: selectedRoute) {
            let p = point(position)
            let marker = CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)
            UIColor.white.setFill(); UIBezierPath(ovalIn: marker.insetBy(dx: -1.5, dy: -1.5)).fill()
            drawSymbol("person.crop.circle.fill", in: marker)
            markers.append(marker.insetBy(dx: -2, dy: -2))
            used.insert(.start)
        }
        // 7. Room names last, on a white knockout so furniture or hatching never hides them, moved clear of markers.
        for room in rooms {
            let center = point(RoomPaths.anchor(in: room, home: home, clearance: 0) ?? Geometry.centroid(room.polygon))
            let label = room.label
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.black]
            let size = (label as NSString).boundingRect(with: CGSize(width: 110, height: 40), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil).size
            let base = CGRect(x: min(max(center.x - size.width / 2, rect.minX), rect.maxX - size.width), y: center.y - size.height / 2, width: ceil(size.width), height: ceil(size.height))
            // Stay inside this room: try small offsets clear of markers, never a neighbouring room.
            let shape = polygon(room.polygon)
            var box = base
            for dy in [0, 13, -13, 26, -26] as [CGFloat] {
                let candidate = base.offsetBy(dx: 0, dy: dy)
                let inside = shape.contains(CGPoint(x: candidate.midX, y: candidate.minY + 1)) && shape.contains(CGPoint(x: candidate.midX, y: candidate.maxY - 1))
                if inside && !markers.contains(where: { $0.intersects(candidate.insetBy(dx: -2, dy: -2)) }) { box = candidate; break }
            }
            UIColor(white: 1, alpha: 0.9).setFill(); UIBezierPath(roundedRect: box.insetBy(dx: -2, dy: -1), cornerRadius: 2).fill()
            (label as NSString).draw(with: box, options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
            if state?.originSpaceID == room.id {
                // Exercise origin: a flame badge above the name, distinct from the hatch every affected room gets.
                let badge = CGRect(x: box.midX - 8, y: box.minY - 19, width: 16, height: 16)
                UIColor.white.setFill(); UIBezierPath(ovalIn: badge.insetBy(dx: -1.5, dy: -1.5)).fill()
                drawSymbol(state?.hazard == .flashFlood ? "water.waves" : "flame.fill", in: badge.insetBy(dx: 2, dy: 2))
            }
        }
        return used
    }

    /// Pulls every vertex toward the centroid by `meters` (display-only inner outline, not geometry).
    static func inset(_ polygon: [Vec2], by meters: Double) -> [Vec2] {
        let c = Geometry.centroid(polygon)
        return polygon.map { p in
            let dx = c.x - p.x, dy = c.y - p.y, d = max(hypot(dx, dy), 0.0001)
            let k = min(meters / d, 0.4)
            return Vec2(p.x + dx * k, p.y + dy * k)
        }
    }

    /// The elements `drawHome` would draw, found by drawing once offscreen (sizes only affect placement).
    static func elementsDrawn(_ home: HomeModel, floorID: String, routes: [RoutePath], state: SpatialExerciseState?, selectedRoute: RouteResult?) -> Set<DiagramElement> {
        var used: Set<DiagramElement> = []
        _ = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 360)).image { _ in
            used = drawHome(home, floorID: floorID, routes: routes, state: state, selectedRoute: selectedRoute, rect: CGRect(x: 0, y: 0, width: 500, height: 360))
        }
        return used
    }

    static func annotationSymbol(_ kind: AnnotationKind) -> String {
        switch kind {
        case .smokeAlarm, .coAlarm: "sensor.fill"
        case .fireExtinguisher: "fire.extinguisher.fill"
        case .exteriorHydrant: "drop.fill"
        case .utilityShutoffWater, .utilityShutoffGas, .utilityShutoffElectric: "bolt.fill"
        case .supplies: "shippingbox.fill"
        case .medicalEquipment: "cross.case.fill"
        case .tornadoShelterCandidate: "shield.lefthalf.filled"
        case .outsideMeetingPoint: "figure.2"
        }
    }
}
