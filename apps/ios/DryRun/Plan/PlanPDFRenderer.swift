import UIKit
import DryRunCore

/// Renders a validated PlanDocument as real text (searchable, Unicode via Core Text/UIKit).
/// Never screenshots a scroll view. Text is never shrunk below the minimum; content that does not fit
/// flows to a continuation page that is clearly marked, rather than being clipped.
/// Main-actor isolated: it is only called from a button action, and this keeps UIKit drawing APIs
/// legal regardless of how a given SDK annotates them.
@MainActor
struct PlanPDFRenderer {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter, points
    static let margin: CGFloat = 48
    static let minimumBodySize: CGFloat = 11

    struct Output {
        var data: Data
        var pageCount: Int
        /// Plan pages that needed a continuation page (reported in VERIFICATION, never clipped).
        var continuedPageIDs: [String]
    }

    func render(_ doc: PlanDocument) -> Output {
        let bounds = CGRect(origin: .zero, size: Self.pageSize)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Dry Run household plan",
            kCGPDFContextCreator as String: "Dry Run",
        ]
        var pageCount = 0
        var continued: [String] = []
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        let data = renderer.pdfData { ctx in
            for page in doc.pages {
                var blocks = Self.blocks(for: page, doc: doc)
                var first = true
                while !blocks.isEmpty {
                    ctx.beginPage()
                    pageCount += 1
                    var y = Self.drawHeader(doc: doc, title: first ? page.title : page.title + " (continued)")
                    let footerTop = Self.pageSize.height - Self.margin - 36
                    var drewAny = false
                    while let block = blocks.first {
                        let height = block.height(width: Self.contentWidth)
                        if y + height > footerTop && drewAny {
                            break
                        }
                        block.draw(at: CGPoint(x: Self.margin, y: y), width: Self.contentWidth)
                        y += height
                        drewAny = true
                        blocks.removeFirst()
                    }
                    if !blocks.isEmpty {
                        continued.append(page.id)
                        Self.drawText("→", at: CGPoint(x: Self.pageSize.width - Self.margin - 20, y: footerTop - 4),
                                      font: .preferredFont(forTextStyle: .footnote), width: 20)
                    }
                    Self.drawFooter(doc: doc, pageNumber: pageCount)
                    first = false
                }
            }
        }
        return Output(data: data, pageCount: pageCount, continuedPageIDs: Array(Set(continued)).sorted())
    }

    static var contentWidth: CGFloat { pageSize.width - margin * 2 }

    // MARK: - Blocks

    /// Main-actor isolated like the renderer: nested types do not inherit the enclosing type's isolation.
    @MainActor
    struct Block {
        var attributed: NSAttributedString
        var spacingAfter: CGFloat
        func height(width: CGFloat) -> CGFloat {
            ceil(attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) + spacingAfter
        }
        func draw(at point: CGPoint, width: CGFloat) {
            // Draw into the measured height, as `drawText` does. With a .greatestFiniteMagnitude height the opening
            // lines of a long wrapped entry (e.g. the 2-1-1 help line) were missing from the PDF.
            let size = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).size
            attributed.draw(with: CGRect(x: point.x, y: point.y, width: width, height: ceil(size.height)),
                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
    }

    static func blocks(for page: PlanPage, doc: PlanDocument) -> [Block] {
        var out: [Block] = []
        let heading = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let body = UIFont.systemFont(ofSize: max(minimumBodySize, 11.5))
        let bold = UIFont.systemFont(ofSize: max(minimumBodySize, 11.5), weight: .bold)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        para.headIndent = 12
        para.firstLineHeadIndent = 0
        for section in page.sections {
            out.append(Block(attributed: NSAttributedString(string: section.heading, attributes: [.font: heading, .foregroundColor: UIColor.black]),
                             spacingAfter: 3))
            for line in section.lines {
                let bullet = line.style == .prohibition ? "⚠︎ " : (line.style == .contact ? "☎︎ " : "• ")
                var text = bullet + line.text
                if line.isFallback { text += "  [EN]" }
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: line.style == .prohibition ? bold : body,
                    .foregroundColor: line.style == .caveat ? UIColor.darkGray : UIColor.black,
                    .paragraphStyle: para,
                ]
                out.append(Block(attributed: NSAttributedString(string: text, attributes: attrs), spacingAfter: 2))
            }
            out.append(Block(attributed: NSAttributedString(string: " ", attributes: [.font: UIFont.systemFont(ofSize: 4)]), spacingAfter: 4))
        }
        return out
    }

    // MARK: - Header/footer

    @discardableResult
    static func drawText(_ s: String, at p: CGPoint, font: UIFont, width: CGFloat, color: UIColor = .black) -> CGFloat {
        let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let rect = a.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        a.draw(with: CGRect(x: p.x, y: p.y, width: width, height: rect.height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(rect.height)
    }

    static func drawHeader(doc: PlanDocument, title: String) -> CGFloat {
        var y = margin
        if let banner = doc.draftTranslationBanner {
            y += drawText(banner, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 11, weight: .bold), width: contentWidth,
                          color: UIColor(red: 0.6, green: 0.3, blue: 0, alpha: 1)) + 2
        }
        if let note = doc.fallbackNote {
            y += drawText(note, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 10), width: contentWidth, color: .darkGray) + 2
        }
        if let content = doc.contentReviewBanner {
            y += drawText(content, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 10), width: contentWidth, color: .darkGray) + 4
        }
        y += drawText(title, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 20, weight: .bold), width: contentWidth) + 10
        return y
    }

    static func drawFooter(doc: PlanDocument, pageNumber: Int) {
        let y = pageSize.height - margin - 24
        let date = ISO8601DateFormatter.string(from: doc.generatedAt, timeZone: .current, formatOptions: [.withFullDate])
        drawText("\(doc.footer)  ·  \(date)  ·  content \(doc.contentVersion)  ·  sources: \(doc.sourceIDs.joined(separator: ", "))  ·  p. \(pageNumber)",
                 at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 8), width: contentWidth, color: .darkGray)
    }
}
