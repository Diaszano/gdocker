import AppKit
import SwiftUI

enum SettingsKey {
    static let theme = "theme"
    static let keepInMenuBar = "keepInMenuBar"
    static let mcpPort = "mcpPort"
    static let mcpAutoStart = "mcpAutoStart"

    static let defaultMcpPort = 7391
    static let mcpPortRange = 1024...65535
}

enum Theme: String, CaseIterable {
    case system, latte, frappe, macchiato, mocha

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .latte: "Catppuccin Latte"
        case .frappe: "Catppuccin Frappé"
        case .macchiato: "Catppuccin Macchiato"
        case .mocha: "Catppuccin Mocha"
        }
    }

    /// Settings saved before the Catppuccin themes: light and dark map to each one's default flavor.
    static var saved: Theme {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.theme) ?? ""
        return Theme(rawValue: raw) ?? (raw == "light" ? .latte : raw == "dark" ? .macchiato : .system)
    }

    func flavor(systemDark: Bool) -> Flavor {
        switch self {
        case .system: systemDark ? .macchiato : .latte
        case .latte: .latte
        case .frappe: .frappe
        case .macchiato: .macchiato
        case .mocha: .mocha
        }
    }

    /// Sets the app-wide appearance, which also covers menus and alerts (unlike `preferredColorScheme`).
    @MainActor func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .latte: NSApp.appearance = NSAppearance(named: .aqua)
        case .frappe, .macchiato, .mocha: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        for window in NSApp.windows {
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor.ctp(\.bg)
        }
    }

    @MainActor static func applySaved() { saved.apply() }
}
