import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.applySaved()
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            // The closing window is still visible during this notification; look again on the next turn.
            DispatchQueue.main.async { MainActor.assumeIsolated { AppDelegate.hideDockIconIfNoWindows() } }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: SettingsKey.keepInMenuBar)
    }

    private static func hideDockIconIfNoWindows() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.keepInMenuBar) else { return }
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
