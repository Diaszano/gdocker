import SwiftUI

struct GDockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: ContainersStore
    @State private var mcp: McpController
    @AppStorage(SettingsKey.keepInMenuBar) private var keepInMenuBar = false

    init() {
        let store = ContainersStore()
        _store = State(initialValue: store)
        _mcp = State(initialValue: McpController(store: store))
    }

    var body: some Scene {
        // A single-instance Window, so "Open window" from the menu bar never opens a second copy.
        Window("GDocker", id: "main") {
            MainWindow()
                .environment(store)
                .environment(mcp)
                .frame(minWidth: 1000, minHeight: 600)
                .task {
                    store.start()
                    await mcp.startIfEnabled()
                }
        }
        Settings { SettingsView().environment(mcp) }
        MenuBarExtra(isInserted: $keepInMenuBar) {
            MenuBarContent().environment(store).environment(mcp)
        } label: {
            Image(systemName: "shippingbox")
        }
    }
}
