import AppKit
import SwiftUI

/// Catppuccin flavors. Latte's ok/err/warn/muted/accent and Frappé's err/muted are darkened or lightened
/// from the official values so every text and icon pair passes WCAG (4.5:1 text, 3:1 icons).
enum Flavor: CaseIterable {
    case latte, frappe, macchiato, mocha

    var isDark: Bool { self != .latte }

    var bg: UInt32 { pick(0xEFF1F5, 0x303446, 0x24273A, 0x1E1E2E) }
    var side: UInt32 { pick(0xE6E9EF, 0x292C3C, 0x1E2030, 0x181825) }
    var code: UInt32 { pick(0xDCE0E8, 0x232634, 0x181926, 0x11111B) }
    var line: UInt32 { pick(0xBCC0CC, 0x51576D, 0x494D64, 0x45475A) }
    var hover: UInt32 { pick(0xCCD0DA, 0x414559, 0x363A4F, 0x313244) }
    var text: UInt32 { pick(0x4C4F69, 0xC6D0F5, 0xCAD3F5, 0xCDD6F4) }
    var muted: UInt32 { pick(0x545768, 0xACB4D2, 0xA5ADCB, 0xA6ADC8) }
    var accent: UInt32 { pick(0x1C5EE1, 0x8CAAEE, 0x8AADF4, 0x89B4FA) }
    var ok: UInt32 { pick(0x2D701E, 0xA6D189, 0xA6DA95, 0xA6E3A1) }
    var err: UInt32 { pick(0xB50D31, 0xEC9E9F, 0xED8796, 0xF38BA8) }
    var warn: UInt32 { pick(0x8A5812, 0xE5C890, 0xEED49F, 0xF9E2AF) }

    private func pick(_ latte: UInt32, _ frappe: UInt32, _ macchiato: UInt32, _ mocha: UInt32) -> UInt32 {
        switch self {
        case .latte: latte
        case .frappe: frappe
        case .macchiato: macchiato
        case .mocha: mocha
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }

    /// Resolves per draw to the flavor of the saved theme, so it follows the system appearance for `.system`.
    static func ctp(_ role: KeyPath<Flavor, UInt32>) -> NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: Theme.saved.flavor(systemDark: dark)[keyPath: role])
        }
    }
}

extension Color {
    enum ctp {
        static let bg = Color(nsColor: .ctp(\.bg))
        static let side = Color(nsColor: .ctp(\.side))
        static let text = Color(nsColor: .ctp(\.text))
        static let muted = Color(nsColor: .ctp(\.muted))
        static let accent = Color(nsColor: .ctp(\.accent))
        static let ok = Color(nsColor: .ctp(\.ok))
        static let err = Color(nsColor: .ctp(\.err))
        static let warn = Color(nsColor: .ctp(\.warn))
    }
}
