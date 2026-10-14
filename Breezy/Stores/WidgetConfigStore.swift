//
//  WidgetConfigStore.swift
//  Breezy
//
//  Stores named Widget Studio designs in the shared app group so both the app
//  (builder) and the Home Screen widget extension (render + per-slot picker)
//  see the same set.
//

import Foundation
import SwiftUI
import WidgetKit
import Combine

class WidgetConfigStore: ObservableObject {
    static let shared = WidgetConfigStore()

    private let suiteName = "group.com.breezy.weather"
    private let designsKey = "Breezy.CustomWidgetDesigns"
    private let selectedKey = "Breezy.CustomWidgetSelectedID"
    /// Pre-multi-design storage location; migrated once, then ignored.
    private let legacyKey = "Breezy.CustomWidgetConfig"

    @Published var designs: [CustomWidgetConfiguration] = []
    @Published var selectedID: UUID?

    var selectedDesign: CustomWidgetConfiguration? {
        designs.first { $0.id == selectedID } ?? designs.first
    }

    init() {
        load()
    }

    func load() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }

        // One-time migration from the single-config era.
        if defaults.data(forKey: designsKey) == nil,
           let legacyData = defaults.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode(CustomWidgetConfiguration.self, from: legacyData) {
            designs = [legacy]
            selectedID = legacy.id
            persist()
            defaults.removeObject(forKey: legacyKey)
            return
        }

        if let data = defaults.data(forKey: designsKey),
           let decoded = try? JSONDecoder().decode([CustomWidgetConfiguration].self, from: data) {
            designs = decoded
        }
        if let idString = defaults.string(forKey: selectedKey) {
            selectedID = UUID(uuidString: idString)
        }
    }

    /// Insert or update, and make it the active design.
    func save(_ config: CustomWidgetConfiguration) {
        if let index = designs.firstIndex(where: { $0.id == config.id }) {
            designs[index] = config
        } else {
            designs.append(config)
        }
        selectedID = config.id
        persist()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func select(_ id: UUID) {
        guard designs.contains(where: { $0.id == id }) else { return }
        selectedID = id
        persistSelection()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func delete(_ config: CustomWidgetConfiguration) {
        designs.removeAll { $0.id == config.id }
        if selectedID == config.id {
            selectedID = designs.first?.id
        }
        persist()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func duplicate(_ config: CustomWidgetConfiguration) {
        var copy = config
        copy.id = UUID()
        copy.name = "\(config.name) Copy"
        save(copy)
    }

    private func persist() {
        persistDesigns()
        persistSelection()
    }

    private func persistDesigns() {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(designs) else { return }
        defaults.set(data, forKey: designsKey)
    }

    private func persistSelection() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if let selectedID {
            defaults.set(selectedID.uuidString, forKey: selectedKey)
        } else {
            defaults.removeObject(forKey: selectedKey)
        }
    }
}
