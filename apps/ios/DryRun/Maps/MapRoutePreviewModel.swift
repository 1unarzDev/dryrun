import Foundation
import Observation
import DryRunCore

@MainActor
protocol MapDirectionsPlanning: AnyObject {
    func cancel()
    func preview(from origin: GeographicCoordinate, to destination: GeographicCoordinate, mode: MapTravelMode) async throws -> MapTravelPreview
}
extension AppleMapDirectionsService: MapDirectionsPlanning { }

struct MapRoutePreviewState: Hashable {
    let destinationID: String
    let origin: GeographicCoordinate
    let destination: GeographicCoordinate
    let preview: MapTravelPreview
}

/// One explicit destination/origin/mode request. Cancellation invalidates GPS resolution and late SDK callbacks.
@MainActor
@Observable
final class MapRoutePreviewModel {
    private let service: any MapDirectionsPlanning
    private var task: Task<Void, Never>?
    private var generation = 0
    private(set) var result: MapRoutePreviewState?
    private(set) var isLoading = false
    private(set) var errorKey: String?

    init(service: any MapDirectionsPlanning = AppleMapDirectionsService()) { self.service = service }

    func cancel(clearPreview: Bool = false) {
        generation += 1
        task?.cancel(); task = nil; service.cancel(); isLoading = false; errorKey = nil
        if clearPreview { result = nil }
    }

    @discardableResult
    func start(destinationID: String, destination: GeographicCoordinate, mode: MapTravelMode,
               origin: @escaping @MainActor () async -> GeographicCoordinate?) -> Task<Void, Never> {
        cancel(clearPreview: true)
        let ticket = generation
        isLoading = true
        let request = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if ticket == generation { isLoading = false; task = nil } }
            let resolved = await origin()
            guard ticket == generation, !Task.isCancelled else { return }
            guard let resolved else { errorKey = "originMissing"; return }
            do {
                let preview = try await service.preview(from: resolved, to: destination, mode: mode)
                guard ticket == generation, !Task.isCancelled else { return }
                result = MapRoutePreviewState(destinationID: destinationID, origin: resolved, destination: destination, preview: preview)
            } catch {
                if ticket == generation, !Task.isCancelled { errorKey = "routeError" }
            }
        }
        task = request
        return request
    }
}
