import SwiftUI

struct GDockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = ContainersStore()
    @AppStorage(SettingsKey.keepInMenuBar) private var keepInMenuBar = false

    var body: some Scene {
        // A single-instance Window, so "Open window" from the menu bar never opens a second copy.
        Window("GDocker", id: "main") {
            MainWindow()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 600)
                .task { store.start() }
        }
        Settings { SettingsView() }
        MenuBarExtra(isInserted: $keepInMenuBar) {
            MenuBarContent().environment(store)
        } label: {
            Image(systemName: "shippingbox")
        }
    }
}
