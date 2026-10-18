import UIKit
import CoreText
import DryRunCore

/// Renders a validated PlanDocument as real text (searchable, Unicode via Core Text/UIKit).
/// Never screenshots a scroll view. Text is never shrunk below the minimum; content that does not fit
/// flows to a continuation page that is clearly marked, rather than being clipped.
/// Main-actor isolated: it is only called from a button action, and this keeps UIKit drawing APIs
/// legal regardless of how a given SDK annotates them.
@MainActor
struct PlanPDFRenderer {
    enum Paper: String, CaseIterable { case letter, a4
        var size: CGSize { self == .letter ? CGSize(width: 612, height: 792) : CGSize(width: 595.28, height: 841.89) }
    }
    static let pageSize = CGSize(width: 612, height: 792) // default, US Letter
    static let margin: CGFloat = 48
    static let minimumBodySize: CGFloat = 11

    struct Output {
        var data: Data
        var pageCount: Int
        /// Plan pages that needed a continuation page (reported in VERIFICATION, never clipped).
        var continuedPageIDs: [String]
    }

    func render(_ doc: PlanDocument, paper: Paper = .letter, mapPanels: [PlanMapPanel] = []) -> Output {
        let size = paper.size
        let mapPanels = doc.pages.allSatisfy { $0.id == "family-card" } ? [] : mapPanels
        let width = size.width - Self.margin * 2
        let bounds = CGRect(origin: .zero, size: size)
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
                if page.id == doc.pages.last?.id, !doc.sourceIDs.isEmpty {
                    blocks.append(Block(attributed: NSAttributedString(string: Self.exportText("sources", locale: doc.locale), attributes: [.font: UIFont.boldSystemFont(ofSize: 12)]), spacingAfter: 4))
                    blocks.append(Block(attributed: NSAttributedString(string: doc.sourceIDs.joined(separator: ", "), attributes: [.font: UIFont.systemFont(ofSize: 11)]), spacingAfter: 8))
                }
                if page.id == "essentials", mapPanels.isEmpty, doc.visualSnapshot?.homeCoordinate != nil || doc.visualSnapshot?.savedPlaces.contains(where: { $0.coordinate != nil }) == true {
                    blocks.append(Block(attributed: NSAttributedString(string: Self.exportText("mapUnavailable", locale: doc.locale), attributes: [.font: UIFont.systemFont(ofSize: 11)]), spacingAfter: 8))
                }
                var first = true
                while !blocks.isEmpty {
                    ctx.beginPage()
                    pageCount += 1
                    var y = Self.drawHeader(doc: doc, title: first ? page.title : page.title + " (" + Self.exportText("continued", locale: doc.locale) + ")", width: width)
                    let footerTop = size.height - Self.margin - 36
                    var drewAny = false
                    while let block = blocks.first {
                        let height = block.height(width: width)
                        if y + height > footerTop {
                            if drewAny { break }
                            // Split an oversized first block with Core Text's actual visible UTF-16 range.
                            // Never draw a long medical note into the footer or shrink all the text.
                            let (prefix, remainder) = block.split(width: width, height: max(24, footerTop - y))
                            prefix.draw(at: CGPoint(x: Self.margin, y: y), width: width)
                            blocks.removeFirst()
                            if let remainder { blocks.insert(remainder, at: 0) }
                            drewAny = true
                            break
                        }
                        block.draw(at: CGPoint(x: Self.margin, y: y), width: width)
                        y += height
                        drewAny = true
                        blocks.removeFirst()
                    }
                    if !blocks.isEmpty {
                        continued.append(page.id)
                        Self.drawText("→", at: CGPoint(x: size.width - Self.margin - 20, y: footerTop - 4),
                                      font: .preferredFont(forTextStyle: .footnote), width: 20)
                    }
                    Self.drawFooter(doc: doc, pageNumber: pageCount, size: size)
                    first = false
                }
            }
            for panel in mapPanels {
                ctx.beginPage(); pageCount += 1
                var y = Self.drawHeader(doc: doc, title: panel.title, width: width)
                let imageHeight = width * panel.image.size.height / panel.image.size.width
                panel.image.draw(in: CGRect(x: Self.margin, y: y, width: width, height: imageHeight)); y += imageHeight + 10
                var legend = panel.legend.map { Block(attributed: NSAttributedString(string: $0, attributes: [.font: UIFont.systemFont(ofSize: 11)]), spacingAfter: 3) }
                let footerTop = size.height - Self.margin - 36
                while !legend.isEmpty {
                    guard let block = legend.first else { break }
                    let available = footerTop - y
                    if available < 25 {
                        Self.drawFooter(doc: doc, pageNumber: pageCount, size: size)
                        ctx.beginPage(); pageCount += 1
                        y = Self.drawHeader(doc: doc, title: panel.title + " (" + Self.exportText("continued", locale: doc.locale) + ")", width: width)
                        continued.append("map-legend")
                        continue
                    }
                    let height = block.height(width: width)
                    if height > available {
                        let (prefix, remainder) = block.split(width: width, height: available)
                        prefix.draw(at: CGPoint(x: Self.margin, y: y), width: width)
                        legend.removeFirst(); if let remainder { legend.insert(remainder, at: 0) }
                        y = footerTop
                    } else { block.draw(at: CGPoint(x: Self.margin, y: y), width: width); y += height; legend.removeFirst() }
                }
                Self.drawFooter(doc: doc, pageNumber: pageCount, size: size)
            }
            if doc.pages.contains(where: { $0.id != "family-card" }), let snapshot = doc.visualSnapshot, let home = snapshot.home {
                for floor in home.floors {
                    ctx.beginPage(); pageCount += 1
                    let title = floor.label
                    let y = Self.drawHeader(doc: doc, title: title, width: width)
                    Self.drawHome(home, floorID: floor.id, routes: [], rect: CGRect(x: Self.margin, y: y, width: width, height: min(340, size.height - y - 140)))
                    Self.drawFooter(doc: doc, pageNumber: pageCount, size: size)
                }
                // Each route is a separate qualified exercise view; incompatible scenarios are never merged.
                for (index, result) in snapshot.routes.enumerated() {
                    guard let path = result.primary else { continue }
                    for floorID in Set(path.legs.map(\.floorID)).sorted() {
                        ctx.beginPage(); pageCount += 1
                        let scenario = snapshot.routeScenarioIDs?.indices.contains(index) == true ? snapshot.routeScenarioIDs![index] : "Exercise"
                        let who = result.request.personID.flatMap { snapshot.personLabels?[$0] } ?? ""
                        let scenarioTitle = snapshot.scenarioLabels?[scenario] ?? scenario
                        let y = Self.drawHeader(doc: doc, title: "\(scenarioTitle) · \(who) · \(home.floors.first { $0.id == floorID }?.label ?? floorID)", width: width)
                        Self.drawHome(home, floorID: floorID, routes: [path], rect: CGRect(x: Self.margin, y: y, width: width, height: min(340, size.height - y - 140)))
                        Self.drawFooter(doc: doc, pageNumber: pageCount, size: size)
                    }
                }
            }
        }
        return Output(data: data, pageCount: pageCount, continuedPageIDs: Array(Set(continued)).sorted())
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
        func split(width: CGFloat, height: CGFloat) -> (Block, Block?) {
            let setter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height - spacingAfter), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame).length
            // Normal line heights fit; this fallback still guarantees progress for malformed oversized font data.
            let count = min(attributed.length, max(1, visible))
            let prefix = Block(attributed: attributed.attributedSubstring(from: NSRange(location: 0, length: count)), spacingAfter: spacingAfter)
            let remainder = count < attributed.length ? Block(attributed: attributed.attributedSubstring(from: NSRange(location: count, length: attributed.length - count)), spacingAfter: spacingAfter) : nil
            return (prefix, remainder)
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

    static func drawHeader(doc: PlanDocument, title: String, width: CGFloat = contentWidth) -> CGFloat {
        var y = margin
        if doc.visualSnapshot?.fictional == true {
            y += drawText(exportText("example", locale: doc.locale), at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 11, weight: .bold), width: width) + 4
        }
        if let banner = doc.draftTranslationBanner {
            y += drawText(banner, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 11, weight: .bold), width: width,
                          color: UIColor(red: 0.6, green: 0.3, blue: 0, alpha: 1)) + 2
        }
        if let note = doc.fallbackNote {
            y += drawText(note, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 10), width: width, color: .darkGray) + 2
        }
        if let content = doc.contentReviewBanner {
            y += drawText(content, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 10), width: width, color: .darkGray) + 4
        }
        y += drawText(title, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 20, weight: .bold), width: width) + 10
        return y
    }

    static func drawFooter(doc: PlanDocument, pageNumber: Int, size: CGSize = pageSize) {
        let width = size.width - margin * 2
        let y = size.height - margin - 24
        let date = ISO8601DateFormatter.string(from: doc.generatedAt, timeZone: .current, formatOptions: [.withFullDate])
        drawText("\(doc.footer)  ·  \(date)  ·  \(doc.contentVersion)  ·  \(pageNumber)",
                 at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 8), width: width, color: .darkGray)
    }
}


extension PlanPDFRenderer {
    /// Same floor polygons, openings and exact route-leg points as the on-device canvas.
    static func drawHome(_ home: HomeModel, floorID: String, routes: [RoutePath], rect: CGRect) {
        let rooms = home.spaces.filter { $0.floorID == floorID }
        let pts = rooms.flatMap(\.polygon)
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(), let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return }
        let scale = min((rect.width - 30) / max(maxX - minX, 1), (rect.height - 30) / max(maxY - minY, 1))
        func point(_ p: Vec2) -> CGPoint { CGPoint(x: rect.minX + 15 + (p.x - minX) * scale, y: rect.minY + 15 + (maxY - p.y) * scale) }
        func polygon(_ points: [Vec2]) -> UIBezierPath { let path = UIBezierPath(); if let first = points.first { path.move(to: point(first)); for p in points.dropFirst() { path.addLine(to: point(p)) }; path.close() }; return path }
        for room in rooms {
            let path = polygon(room.polygon); UIColor(white: 0.95, alpha: 1).setFill(); path.fill(); UIColor.black.setStroke(); path.lineWidth = 1; path.stroke()
            let x = room.polygon.map(\.x).reduce(0,+) / Double(max(1,room.polygon.count)); let y = room.polygon.map(\.y).reduce(0,+) / Double(max(1,room.polygon.count))
            drawText(room.label, at: point(Vec2(x,y)), font: .systemFont(ofSize: 9), width: 90)
        }
        for obstacle in home.obstacles where obstacle.floorID == floorID { UIColor.gray.setFill(); polygon(obstacle.polygon).fill() }
        for portal in home.portals where portal.floorID == floorID {
            let path = UIBezierPath(); path.move(to: point(portal.a)); path.addLine(to: point(portal.b)); path.lineWidth = 5
            UIColor.white.setStroke(); path.stroke()
            path.lineWidth = portal.kind == .window ? 2 : 1
            UIColor.black.setStroke(); if portal.verification != .verified { path.setLineDash([3,3], count: 2, phase: 0) }; path.stroke()
        }
        for route in routes { for leg in route.legs where leg.floorID == floorID {
            let path = UIBezierPath(); if let first = leg.points.first { path.move(to: point(first)); for p in leg.points.dropFirst() { path.addLine(to: point(p)) } }; path.lineWidth = 2.5; UIColor.black.setStroke(); path.setLineDash([6,3], count: 2, phase: 0); path.stroke()
        } }
        for connector in home.connectors {
            if home.space(connector.fromSpaceID)?.floorID == floorID { drawText("↕", at: point(connector.fromPoint), font: .systemFont(ofSize: 16, weight: .bold), width: 30) }
            if home.space(connector.toSpaceID)?.floorID == floorID { drawText("↕", at: point(connector.toPoint), font: .systemFont(ofSize: 16, weight: .bold), width: 30) }
        }
        for annotation in home.annotations where annotation.floorID == floorID { if let p = annotation.position { drawText(annotation.label, at: point(p), font: .systemFont(ofSize: 8), width: 100) } }
    }
}
