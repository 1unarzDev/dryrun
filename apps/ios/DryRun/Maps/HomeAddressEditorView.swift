import SwiftUI
import MapKit
import DryRunCore

/// Focused address editor reused from preparation, home, and Plan. Manual text remains valid offline.
@MainActor
struct HomeAddressEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var unit = ""
    @State private var draft = PrivateLocation()
    @State private var completion = AddressCompletionService()
    @State private var camera: MapCameraPosition = .automatic
    @State private var center: GeographicCoordinate?
    @State private var saving = false
    @State private var error: String?
    @State private var initialized = false
    @State private var resolving = false
    @State private var moving = false
    @State private var confirmingMove = false
    @State private var resolutionGeneration = 0
    private func t(_ key: String) -> String { model.localizer("map.\(key)") }
    private var coordinate: GeographicCoordinate? {
        guard let lat = draft.latitude, let lon = draft.longitude else { return nil }
        return GeographicCoordinate(latitude: lat, longitude: lon)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(t("addressPrivacy")).font(.caption); TextField(t("addressOptional"), text: Binding(get: { address }, set: { value in
                        invalidateResolution(); address = value
                        draft = PrivateLocation(addressLine: value, unit: unit); completion.update(value)
                    })).textContentType(.fullStreetAddress).accessibilityIdentifier("address.line")
                    TextField(t("unit"), text: $unit).accessibilityIdentifier("address.unit")
                }
                if !completion.suggestions.isEmpty {
                    Section(t("suggestions")) {
                        ForEach(completion.suggestions) { suggestion in
                            Button { select(suggestion) } label: { VStack(alignment: .leading) { Text(suggestion.title); Text(suggestion.subtitle).font(.caption) } }
                        }
                    }
                }
                if let coordinate {
                    Section(t("confirmPin")) {
                        Map(position: $camera) { Marker(t("home"), coordinate: coordinate.cl) }
                            .frame(height: 230)
                            .onMapCameraChange(frequency: .onEnd) { context in center = GeographicCoordinate(latitude: context.region.center.latitude, longitude: context.region.center.longitude) }
                        Button(t("correctPin")) { if let center { draft.latitude = center.latitude; draft.longitude = center.longitude } }
                        Text([draft.city, draft.administrativeArea, draft.postalCode, draft.countryCode].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                    }
                }
                Section(t("manualPin")) {
                    TextField(t("latitude"), text: Binding(get: { draft.latitude.map { String($0) } ?? "" }, set: { invalidateResolution(); draft.latitude = Double($0) })).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("address.latitude")
                    TextField(t("longitude"), text: Binding(get: { draft.longitude.map { String($0) } ?? "" }, set: { invalidateResolution(); draft.longitude = Double($0) })).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("address.longitude")
                    TextField(t("countryCode"), text: Binding(get: { draft.countryCode ?? "" }, set: { invalidateResolution(); draft.countryCode = $0.uppercased() })).textInputAutocapitalization(.characters)
                    Text(t("unknownMetadata")).font(.caption)
                }
                if model.household?.privateLocation != nil {
                    Section(t("addressChange")) {
                        Picker(t("addressChange"), selection: $moving) { Text(t("correction")).tag(false); Text(t("moving")).tag(true) }
                        if moving { Text(t("moveNote")).font(.caption) }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(t("homeAddress"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(model.localizer("ui.save")) { if moving { confirmingMove = true } else { save() } }.disabled(saving || resolving).accessibilityIdentifier("address.save") }
                }
                .task {
                    guard !initialized else { return }; initialized = true
                    draft = model.household?.privateLocation ?? PrivateLocation(); address = draft.addressLine ?? ""; unit = draft.unit ?? ""
                    if let coordinate { camera = .region(MKCoordinateRegion(center: coordinate.cl, latitudinalMeters: 700, longitudinalMeters: 700)) }
                }
                .onDisappear { invalidateResolution() }
                .confirmationDialog(t("moving"), isPresented: $confirmingMove, titleVisibility: .visible) { Button(t("moving"), role: .destructive) { save() } } message: { Text(t("moveNote")) }
        }
    }
    private func invalidateResolution() { resolutionGeneration += 1; resolving = false; completion.cancel() }
    private func select(_ suggestion: AddressSuggestion) {
        resolutionGeneration += 1; let ticket = resolutionGeneration; let selectedQuery = address
        resolving = true; error = nil
        Task {
            defer { if ticket == resolutionGeneration { resolving = false } }
            do {
                var result = try await completion.resolve(suggestion)
                guard ticket == resolutionGeneration, address == selectedQuery else { return }
                result.unit = unit; draft = result; address = result.addressLine ?? ""; completion.cancel()
                if let coordinate { camera = .region(MKCoordinateRegion(center: coordinate.cl, latitudinalMeters: 700, longitudinalMeters: 700)) }
            } catch is CancellationError { }
            catch { if ticket == resolutionGeneration { self.error = t("searchError") } }
        }
    }
    private func save() {
        guard var household = model.household else { return }
        if (draft.latitude != nil || draft.longitude != nil) && coordinate == nil { error = t("invalidPin"); return }
        draft.addressLine = address.isEmpty ? nil : address; draft.unit = unit.isEmpty ? nil : unit
        household.regionID = HomeLocationChange.regionID(previous: household.privateLocation, updated: draft, existingRegionID: household.regionID)
        household.privateLocation = draft
        // Apple administrative names never become trusted county/FIPS identifiers.
        saving = true
        Task {
            let saved = moving ? await model.moveHome(to: draft) : await model.updateHousehold(household)
            if saved { dismiss() } else { error = t("saveError") }; saving = false
        }
    }
}
