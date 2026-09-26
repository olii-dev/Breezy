//
//  TripSetupView.swift
//  Breezy
//
//  From / To / stops / Plan route + recent trips.
//

import SwiftUI

struct TripSetupView: View {
    @ObservedObject var tripVM: TripViewModel
    @ObservedObject var weatherViewModel: WeatherViewModel
    @ObservedObject var locationHelper: LocationHelper
    let theme: WeatherTheme

    @State private var pickingField: TripEndpointField?
    @State private var editingStopDwell: TripStop?

    var body: some View {
        VStack(spacing: DesignSystem.spacingL) {
            header
            endpointCard
            stopsCard
            planButton
            recentSection
        }
        .sheet(item: $pickingField) { field in
            TripLocationSearchSheet(
                title: field.title,
                weatherViewModel: weatherViewModel,
                locationHelper: locationHelper,
                showCurrentLocation: field == .origin || field == .stop,
                onPick: { location in
                    switch field {
                    case .origin:
                        tripVM.setEndpoint(location, asOrigin: true)
                    case .destination:
                        tripVM.setEndpoint(location, asOrigin: false)
                    case .stop:
                        tripVM.addStop(location)
                    }
                    pickingField = nil
                }
            )
        }
        .sheet(item: $editingStopDwell) { stop in
            TripDwellEditor(
                stop: stop,
                theme: theme,
                glassOpacity: weatherViewModel.glassOpacity,
                onSave: { minutes in
                    tripVM.updateDwell(for: stop.id, minutes: minutes)
                    editingStopDwell = nil
                }
            )
            .presentationDetents([.medium])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weather on your drive")
                .font(.title2.weight(.bold))
                .foregroundStyle(theme.textColor)
            Text("See conditions along the route at the time you’ll actually be there.")
                .font(.subheadline)
                .foregroundStyle(theme.textColor.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DesignSystem.spacingS)
    }

    private var endpointCard: some View {
        VStack(spacing: 0) {
            endpointRow(
                label: "From",
                value: tripVM.origin?.name,
                systemImage: "location.fill"
            ) {
                pickingField = .origin
            }

            Divider().opacity(0.25)

            endpointRow(
                label: "To",
                value: tripVM.destination?.name,
                systemImage: "flag.fill"
            ) {
                pickingField = .destination
            }

            Divider().opacity(0.25)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Departs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textColor.opacity(0.6))
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { tripVM.departure },
                            set: { tripVM.departureChanged($0) }
                        ),
                        in: tripVM.departureRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .tint(theme.textColor)
                }
                Spacer()
            }
            .padding(DesignSystem.spacingM)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                .fill(.ultraThinMaterial.opacity(weatherViewModel.glassOpacity))
        )
    }

    private func endpointRow(label: String, value: String?, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .foregroundStyle(theme.textColor.opacity(0.8))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textColor.opacity(0.6))
                    Text(value ?? "Choose location")
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.textColor.opacity(value == nil ? 0.45 : 1))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.textColor.opacity(0.4))
            }
            .padding(DesignSystem.spacingM)
        }
        .buttonStyle(.plain)
    }

    private var stopsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
            HStack {
                Text("Stops")
                    .font(.headline)
                    .foregroundStyle(theme.textColor)
                Spacer()
                Button {
                    pickingField = .stop
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textColor.opacity(0.85))
                }
                .buttonStyle(.borderless)
            }

            Text("Dwell is how long you stay before driving on — later weather along the trip shifts. Drag the handle to reorder.")
                .font(.caption)
                .foregroundStyle(theme.textColor.opacity(0.6))

            if tripVM.stops.isEmpty {
                Button {
                    pickingField = .stop
                } label: {
                    Text("Tap to add a coffee / fuel stop")
                        .font(.footnote)
                        .foregroundStyle(theme.textColor.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            } else {
                List {
                    ForEach(tripVM.stops) { stop in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(stop.endpoint.name)
                                    .foregroundStyle(theme.textColor)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Button(role: .destructive) {
                                    tripVM.removeStop(stop)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(theme.textColor.opacity(0.55))
                                }
                                .buttonStyle(.borderless)
                            }

                            Button {
                                editingStopDwell = stop
                            } label: {
                                Label("Dwell · \(stop.dwellMinutes) min", systemImage: "clock")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(theme.textColor)
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                                            .fill(.ultraThinMaterial.opacity(min(1, weatherViewModel.glassOpacity + 0.12)))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                                                    .stroke(theme.textColor.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                    .onMove(perform: tripVM.reorderStops)
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .environment(\.editMode, .constant(.active))
                .frame(minHeight: CGFloat(tripVM.stops.count) * 108)
                .scrollContentBackground(.hidden)

                Button {
                    pickingField = .stop
                } label: {
                    Text("Add another stop")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textColor.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                .fill(.ultraThinMaterial.opacity(weatherViewModel.glassOpacity))
        )
    }

    private var planButton: some View {
        Button {
            tripVM.planRoute()
        } label: {
            HStack {
                if tripVM.isLoadingRoute {
                    ProgressView()
                        .tint(theme.textColor)
                }
                Text(tripVM.isLoadingRoute ? "Planning…" : "Plan route")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(theme.textColor)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                    .fill(.ultraThinMaterial.opacity(min(1, weatherViewModel.glassOpacity + 0.2)))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                            .stroke(theme.textColor.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .disabled(tripVM.origin == nil || tripVM.destination == nil || tripVM.isLoadingRoute)
        .opacity(tripVM.origin == nil || tripVM.destination == nil ? 0.5 : 1)
    }

    @ViewBuilder
    private var recentSection: some View {
        if !tripVM.recentTrips.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                Text("Recent")
                    .font(.headline)
                    .foregroundStyle(theme.textColor)

                ForEach(tripVM.recentTrips) { trip in
                    Button {
                        tripVM.openRecent(trip)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(theme.textColor)
                                Text(trip.departure, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(theme.textColor.opacity(0.6))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(theme.textColor.opacity(0.4))
                        }
                        .padding(DesignSystem.spacingM)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                .fill(.ultraThinMaterial.opacity(weatherViewModel.glassOpacity * 0.85))
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            tripVM.deleteRecent(trip)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

enum TripEndpointField: String, Identifiable {
    case origin
    case destination
    case stop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .origin: return "From"
        case .destination: return "To"
        case .stop: return "Add stop"
        }
    }
}

struct TripDwellEditor: View {
    let stop: TripStop
    let theme: WeatherTheme
    let glassOpacity: Double
    let onSave: (Int) -> Void

    @State private var minutes: Double
    @Environment(\.dismiss) private var dismiss

    init(stop: TripStop, theme: WeatherTheme, glassOpacity: Double, onSave: @escaping (Int) -> Void) {
        self.stop = stop
        self.theme = theme
        self.glassOpacity = glassOpacity
        self.onSave = onSave
        _minutes = State(initialValue: Double(stop.dwellMinutes))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(stop.endpoint.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.textColor)
                Text("\(Int(minutes)) minutes")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(theme.textColor)
                Slider(value: $minutes, in: 0...180, step: 5)
                    .tint(theme.textColor)
                Spacer()
            }
            .padding()
            .background(AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor]).ignoresSafeArea())
            .navigationTitle("Dwell time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Int(minutes))
                    }
                }
            }
        }
    }
}
