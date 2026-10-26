import DryRunCore

/// A selected source record and its private draft, shared by Apple, official and saved-place entry points.
/// Current activation is evaluated only from the original public source, never from a saved-place label.
struct MapPlanningDestination: Identifiable, Hashable {
    let place: SavedPlace
    var officialResource: PublicResource? = nil
    var id: String { place.id }
}
