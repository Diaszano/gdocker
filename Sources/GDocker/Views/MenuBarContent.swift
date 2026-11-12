import AppKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(ContainersStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            store.connected ? Text("Docker connected", bundle: .l10n) : Text("Docker disconnected", bundle: .l10n)
        }
        Divider()
        ForEach(store.all.filter { $0.statusKind == .running }) { container in
            Menu(container.name) {
                Button { Task { await store.perform(.restart, on: container.id) } } label: {
                    Text("Restart", bundle: .l10n)
                }
                Button { Task { await store.perform(.stop, on: container.id) } } label: {
                    Text("Stop", bundle: .l10n)
                }
            }
        }
        Divider()
        Button {
            // The Dock icon was hidden while the window was closed; bring it back before showing the window.
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            NSApp.activate()
        } label: { Text("Open window", bundle: .l10n) }
        Button { NSApp.terminate(nil) } label: { Text("Quit", bundle: .l10n) }
            .keyboardShortcut("q")
    }
}
