//
//  MacFirstRunView.swift
//  BreezyMac
//
//  Mac-idiomatic first run: pick a location (reusing the iPhone picker) and
//  optionally enable notifications. Marks onboarding complete on dismissal.
//

import SwiftUI

struct MacFirstRunView: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: WeatherViewModel
    @ObservedObject var locationHelper: LocationHelper

    @State private var enableNotifications = true
    @State private var completed = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.teal, .orange)
                    .padding(.top, 28)

                Text("Welcome to Breezy")
                    .font(.title.weight(.bold))

                Text("Search for a city to see beautiful, customisable weather.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            LocationPickerView(viewModel: viewModel, locationHelper: locationHelper, isButtonBusy: .constant(false))
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Toggle("Enable weather notifications", isOn: $enableNotifications)
                .font(.callout)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)

            HStack {
                Spacer()
                Button("Done") {
                    finish()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .frame(width: 520)
        .onDisappear {
            finish()
        }
    }

    private func finish() {
        guard !completed else { return }
        completed = true

        if enableNotifications {
            Task {
                await NotificationManager.shared.requestAuthorization()
            }
        }

        UserDefaults.standard.set(true, forKey: "BreezyMac.HasCompletedFirstRun")
        UserDefaults.standard.set(true, forKey: "Breezy.HasCompletedOnboarding")
        isPresented = false
    }
}
