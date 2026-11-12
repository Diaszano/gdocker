import SwiftUI

struct GDockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: ContainersStore
    @State private var imagesStore: ImagesStore
    @State private var volumesStore: VolumesStore
    @State private var networksStore: NetworksStore
    @State private var mcp: McpController
    @AppStorage(SettingsKey.keepInMenuBar) private var keepInMenuBar = false

    init() {
        let store = ContainersStore()
        _store = State(initialValue: store)
        _imagesStore = State(initialValue: ImagesStore(store: store))
        _volumesStore = State(initialValue: VolumesStore(store: store))
        _networksStore = State(initialValue: NetworksStore(store: store))
        _mcp = State(initialValue: McpController(store: store))
    }

    var body: some Scene {
        // A single-instance Window, so "Open window" from the menu bar never opens a second copy.
        Window("GDocker", id: "main") {
            MainWindow()
                .environment(store)
                .environment(imagesStore)
                .environment(volumesStore)
                .environment(networksStore)
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
