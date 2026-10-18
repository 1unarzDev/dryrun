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
}

@MainActor
struct PlanMapSnapshotRenderer {
    func panels(for snapshot: PlanVisualSnapshot, title: String) async -> [PlanMapPanel] {
        let selected = PlanMapSelection.panels(homeCoordinate: snapshot.homeCoordinate, places: snapshot.savedPlaces)
        guard selected.origin != nil else { return [] }
        var panels: [PlanMapPanel] = []
        let localPoints = (snapshot.homeCoordinate.map { [("H", $0)] } ?? []) + selected.local.compactMap { entry in entry.place.coordinate.map { ("\(entry.number)", $0) } }
        if !localPoints.isEmpty, let image = await image(points: localPoints) {
            panels.append(PlanMapPanel(image: image, title: title, legend: selected.local.map { "\($0.number). \($0.place.label)" }))
        }
        // A distant meetup never makes the neighborhood panel unreadably small.
        for entry in selected.distant {
            let place = entry.place
            if let coordinate = place.coordinate, let image = await image(points: [("\(entry.number)", coordinate)]) {
                panels.append(PlanMapPanel(image: image, title: place.label, legend: ["\(entry.number). \(place.addressText ?? place.label)"]))
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
        do {
            let result = try await withTaskCancellationHandler(operation: { try await request.start() }, onCancel: { Task { @MainActor in request.cancel() } })
            guard !Task.isCancelled else { return nil }
            return UIGraphicsImageRenderer(size: options.size).image { _ in
                result.image.draw(in: CGRect(origin: .zero, size: options.size))
                for (label, coordinate) in points {
                    let p = result.point(for: coordinate.cl)
                    // Required notices generally occupy the bottom band. Never paint over it.
                    guard p.y < options.size.height - 44 else { continue }
                    let circle = UIBezierPath(ovalIn: CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26))
                    UIColor.black.setFill(); circle.fill()
                    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.white]
                    let size = label.size(withAttributes: attrs)
                    label.draw(at: CGPoint(x: p.x - size.width / 2, y: p.y - size.height / 2), withAttributes: attrs)
                }
            }
        } catch { return nil }
    }
}


@MainActor
private final class TransientMapSnapshotRequest {
    private let snapshotter: MKMapSnapshotter
    init(options: MKMapSnapshotter.Options) { snapshotter = MKMapSnapshotter(options: options) }
    func start() async throws -> MKMapSnapshotter.Snapshot { try await snapshotter.start() }
    func cancel() { snapshotter.cancel() }
}
