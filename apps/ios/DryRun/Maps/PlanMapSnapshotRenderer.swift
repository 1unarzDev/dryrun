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
}

@MainActor
struct PlanMapSnapshotRenderer {
    private static let bundledContent: ContentLibrary? = try? ContentLibrary.load(from: ContentLocator.contentRoot())
    func panels(for snapshot: PlanVisualSnapshot, title: String, localizer: Localizer? = nil) async -> [PlanMapPanel] {
        let localizer = localizer ?? Self.bundledContent?.localizer(for: "en") ?? Localizer(locale: "en", tables: [:], manifest: nil)
        var panels: [PlanMapPanel] = []
        for extent in PlanMapSelection.extents(homeCoordinate: snapshot.homeCoordinate, places: snapshot.savedPlaces) {
            let points = (extent.homeCoordinate.map { [("H", $0)] } ?? []) + extent.places.compactMap { entry in entry.place.coordinate.map { ("\(entry.number)", $0) } }
            if let image = await image(points: points) {
                panels.append(PlanMapPanel(image: image, title: extent.title(neighborhood: title),
                    legend: extent.places.flatMap { PlanPlacePresentation.lines(for: $0.place, number: $0.number, localizer: localizer).map(\.text) }, extentID: extent.id))
            }
        }
        return panels
    }
    private func image(points: [(String, GeographicCoordinate)]) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        var rect = MKMapRect.null
        for (_, coordinate) in points { let p = MKMapPoint(coordinate.cl); rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1)) }
        let minimum = MKMapPointsPerMeterAtLatitude(points[0].1.latitude) * 700
        rect = rect.insetBy(dx: -max(rect.width * 0.25, minimum), dy: -max(rect.height * 0.25, minimum))
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect; options.size = CGSize(width: 900, height: 520); options.scale = 1
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
    func image(points: [(String, GeographicCoordinate)], size: CGSize) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        return await withCheckedContinuation { continuation in
            snapshotter.start(with: DispatchQueue.main) { snapshot, _ in
                MainActor.assumeIsolated {
                    guard let snapshot else { continuation.resume(returning: nil); return }
                    let image = UIGraphicsImageRenderer(size: size).image { _ in
                        snapshot.image.draw(in: CGRect(origin: .zero, size: size))
                        for (label, coordinate) in points {
                            let p = snapshot.point(for: coordinate.cl)
                            // Apple's complete image and attribution stay visible.
                            guard p.y < size.height - 44 else { continue }
                            UIColor.black.setFill()
                            UIBezierPath(ovalIn: CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26)).fill()
                            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.white]
                            let labelSize = label.size(withAttributes: attrs)
                            label.draw(at: CGPoint(x: p.x - labelSize.width / 2, y: p.y - labelSize.height / 2), withAttributes: attrs)
                        }
                    }
                    continuation.resume(returning: image)
                }
            }
        }
    }
    func cancel() { snapshotter.cancel() }
}
