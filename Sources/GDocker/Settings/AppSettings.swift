import AppKit
import SwiftUI

enum SettingsKey {
    static let theme = "theme"
    static let keepInMenuBar = "keepInMenuBar"
}

enum Theme: String, CaseIterable {
    case system, light, dark

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Sets the app-wide appearance, which also covers menus and alerts (unlike `preferredColorScheme`).
    @MainActor func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    @MainActor static func applySaved() {
        let saved = UserDefaults.standard.string(forKey: SettingsKey.theme) ?? ""
        (Theme(rawValue: saved) ?? .system).apply()
    }
}
