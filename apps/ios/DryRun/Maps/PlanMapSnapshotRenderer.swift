import MapKit
import UIKit
import DryRunCore

/// Transient snapshot for an explicit plan preview/export, never a tile or image cache.
/// Apple's image is drawn whole: logos/legal attribution are not cropped or covered.
@MainActor
struct PlanMapPanel {
    let image: UIImage
    let title: String
    let legend: [String]
    var extentID: String? = nil
    /// The home marker is drawn on this panel (listed first in the key).
    var showsHome = false
    /// Marker style per legend number, so the key repeats exactly the symbol on the image.
    var markerKinds: [Int: PlanMapMarkerKind] = [:]
}

/// Home is a rounded square "H"; meeting places are filled circles; other saved places are open rings.
/// The shapes differ, so the map still reads in grayscale.
enum PlanMapMarkerKind: Hashable, Sendable {
    case home, meetup, resource
    init(_ purpose: SavedPlacePurpose) {
        switch purpose {
        case .outsideMeetingPoint, .backupMeetingPlace: self = .meetup
        default: self = .resource
        }
    }
}

@MainActor
struct PlanMapSnapshotRenderer {
    private static let bundledContent: ContentLibrary? = try? ContentLibrary.load(from: ContentLocator.contentRoot())
    func panels(for snapshot: PlanVisualSnapshot, title: String, localizer: Localizer? = nil) async -> [PlanMapPanel] {
        let localizer = localizer ?? Self.bundledContent?.localizer(for: "en") ?? Localizer(locale: "en", tables: [:], manifest: nil)
        var panels: [PlanMapPanel] = []
        for extent in PlanMapSelection.extents(homeCoordinate: snapshot.homeCoordinate, places: snapshot.savedPlaces) {
            let points: [MarkerPoint] = (extent.homeCoordinate.map { [MarkerPoint(label: "H", kind: .home, coordinate: $0)] } ?? [])
                + extent.places.compactMap { entry in entry.place.coordinate.map { MarkerPoint(label: "\(entry.number)", kind: PlanMapMarkerKind(entry.place.purpose), coordinate: $0) } }
            if let image = await image(points: points) {
                panels.append(PlanMapPanel(image: image, title: extent.title(neighborhood: title),
                    legend: extent.places.flatMap { PlanPlacePresentation.lines(for: $0.place, number: $0.number, localizer: localizer).map(\.text) }, extentID: extent.id,
                    showsHome: extent.homeCoordinate != nil,
                    markerKinds: Dictionary(extent.places.map { ($0.number, PlanMapMarkerKind($0.place.purpose)) }, uniquingKeysWith: { a, _ in a })))
            }
        }
        return panels
    }
    private func image(points: [MarkerPoint]) async -> UIImage? {
        guard !Task.isCancelled, let firstPoint = points.first else { return nil }
        var rect = MKMapRect.null
        for point in points { let p = MKMapPoint(point.coordinate.cl); rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1)) }
        let minimum = MKMapPointsPerMeterAtLatitude(firstPoint.coordinate.latitude) * 700
        rect = rect.insetBy(dx: -max(rect.width * 0.25, minimum), dy: -max(rect.height * 0.25, minimum))
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect; options.size = CGSize(width: 900, height: 560); options.scale = 2
        options.mapType = .standard; options.pointOfInterestFilter = .excludingAll
        let request = TransientMapSnapshotRequest(options: options)
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(8)); request.cancel() } catch { }
        }
        defer { deadline.cancel() }
        let image = await withTaskCancellationHandler(operation: { await request.image(points: points, size: options.size) }, onCancel: { Task { @MainActor in request.cancel() } })
        return Task.isCancelled ? nil : image
    }
}


@MainActor
private final class TransientMapSnapshotRequest {
    private let snapshotter: MKMapSnapshotter
    init(options: MKMapSnapshotter.Options) { snapshotter = MKMapSnapshotter(options: options) }
    /// The SDK Snapshot is not Sendable. Consume it entirely inside the documented main-queue
    /// completion and resume only with the rendered image; no snapshot crosses an actor boundary.
    func image(points: [MarkerPoint], size: CGSize) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        return await withCheckedContinuation { continuation in
            snapshotter.start(with: DispatchQueue.main) { snapshot, _ in
                // Rendered right here on the completion queue; only the finished UIImage leaves this closure.
                do {
                    guard let snapshot else { continuation.resume(returning: nil); return }
                    let image = UIGraphicsImageRenderer(size: size).image { _ in
                        snapshot.image.draw(in: CGRect(origin: .zero, size: size))
                        // Meeting places and resources first, the home last, so the home marker is never covered.
                        for point in points.sorted(by: { ($0.kind == .home ? 1 : 0) < ($1.kind == .home ? 1 : 0) }) {
                            let p = snapshot.point(for: point.coordinate.cl)
                            // Apple's complete image and attribution stay visible.
                            guard p.y < size.height - 44 else { continue }
                            let marker = MarkerPoint.image(point.kind, label: point.label, diameter: 30)
                            marker.draw(at: CGPoint(x: p.x - marker.size.width / 2, y: p.y - marker.size.height / 2))
                        }
                    }
                    continuation.resume(returning: image)
                }
            }
        }
    }
    func cancel() { snapshotter.cancel() }
}


struct MarkerPoint: Sendable {
    let label: String
    let kind: PlanMapMarkerKind
    let coordinate: GeographicCoordinate

    /// Same drawing as `PlanPDFRenderer.markerImage`, usable off the main actor inside the snapshot callback.
    static func image(_ kind: PlanMapMarkerKind, label: String, diameter d: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: d + 6, height: d + 6), format: format).image { _ in
            let rect = CGRect(x: 3, y: 3, width: d, height: d)
            let halo = kind == .home ? UIBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: 7) : UIBezierPath(ovalIn: rect.insetBy(dx: -3, dy: -3))
            UIColor.white.setFill(); halo.fill()
            let shape = kind == .home ? UIBezierPath(roundedRect: rect, cornerRadius: 5) : UIBezierPath(ovalIn: rect)
            if kind == .resource {
                UIColor.white.setFill(); shape.fill(); shape.lineWidth = 3; UIColor.black.setStroke(); shape.stroke()
            } else { UIColor.black.setFill(); shape.fill() }
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: d * 0.55, weight: .bold),
                                                        .foregroundColor: kind == .resource ? UIColor.black : UIColor.white]
            let size = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
        }
    }
}
