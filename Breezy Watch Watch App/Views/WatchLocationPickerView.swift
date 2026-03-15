
//
//  WatchLocationPickerView.swift
//  Breezy Watch Watch App
//
//  List of saved locations to switch between.
//

import SwiftUI

struct WatchLocationPickerView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            // Current Location (GPS)
            Button {
                viewModel.playHaptic(.click)
                viewModel.selectLocation(nil)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text("Current Location")
                            .font(.headline)
                        Text("GPS")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.selectedLocationID == nil {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .listRowBackground(viewModel.selectedLocationID == nil ? Color.blue.opacity(0.15) : nil)
            
            // Saved Locations
            ForEach(viewModel.savedLocations) { location in
                Button {
                    viewModel.playHaptic(.click)
                    viewModel.selectLocation(location.id)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(location.name)
                                .font(.headline)
                        }
                        Spacer()
                        if viewModel.selectedLocationID == location.id {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .listRowBackground(viewModel.selectedLocationID == location.id ? Color.blue.opacity(0.15) : nil)
            }
            .onDelete { indexSet in
                viewModel.removeLocation(at: indexSet)
            }
            
            // Add Button
            NavigationLink(destination: WatchCitySearchView().environmentObject(viewModel)) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                    Text("Add City")
                }
            }
            .simultaneousGesture(TapGesture().onEnded {
                viewModel.playHaptic(.click)
            })
        }
        .navigationTitle("Locations")
    }
}
