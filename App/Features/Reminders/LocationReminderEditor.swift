import SwiftUI
import MapKit
import SyncCore

/// Place a geofenced reminder (AppSpec §5.7, P3-7). Pan the map to set the region center, name it, pick
/// a radius + entry/exit triggers, then Add. Produces a ``SyncCore/ReminderRegion`` for the caller to
/// persist via `ReminderMutation.createLocation`. The CoreLocation monitoring is wired separately.
struct LocationReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (ReminderRegion) -> Void

    private static let defaultCenter = CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198)

    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: defaultCenter, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
    @State private var center = defaultCenter
    @State private var name = ""
    @State private var radius: Double = 150
    @State private var onEntry = true
    @State private var onExit = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack {
                        Map(position: $camera)
                            .frame(height: 220)
                            .onMapCameraChange { context in center = context.region.center }
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Pan the map to place the reminder's center.")
                }

                Section("Place") {
                    TextField("Name (e.g. Home, Office)", text: $name)
                    LabeledContent("Latitude", value: String(format: "%.4f", center.latitude))
                    LabeledContent("Longitude", value: String(format: "%.4f", center.longitude))
                }

                Section("Trigger") {
                    Stepper("Radius: \(Int(radius)) m", value: $radius, in: 50...1000, step: 50)
                    Toggle("When I arrive", isOn: $onEntry)
                    Toggle("When I leave", isOn: $onExit)
                }
            }
            .navigationTitle("Location Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(ReminderRegion(
                            center: GeoPoint(lat: center.latitude, lon: center.longitude,
                                             name: name.isEmpty ? nil : name),
                            radius: radius, onEntry: onEntry, onExit: onExit))
                        dismiss()
                    }
                    .disabled(!onEntry && !onExit)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
