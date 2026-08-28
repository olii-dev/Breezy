//
//  MacSettingsHost.swift
//  BreezyMac
//
//  Hosts the full iPhone Settings surface (Design Studio, themes, widget
//  studio, notifications, units, provider switch) inside the native macOS
//  Settings window, backed by the shared engine so changes apply everywhere.
//

import SwiftUI

struct MacSettingsHost: View {
    @ObservedObject private var viewModel = MacShared.viewModel

    var body: some View {
        SettingsView(viewModel: viewModel)
            .frame(width: 620, height: 660)
    }
}
