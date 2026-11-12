import AppKit
import SwiftUI

struct GDockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    @State private var store: ContainersStore
    @State private var imagesStore: ImagesStore
    @State private var volumesStore: VolumesStore
    @State private var networksStore: NetworksStore
    @State private var composeStore: ComposeStore
    @State private var mcp: McpController
    @AppStorage(SettingsKey.keepInMenuBar) private var keepInMenuBar = false
    @State private var confirmSystemPrune = false
    @State private var isPruning = false

    init() {
        let store = ContainersStore()
        let mcp = McpController(store: store)
        _store = State(initialValue: store)
        _imagesStore = State(initialValue: ImagesStore(store: store))
        _volumesStore = State(initialValue: VolumesStore(store: store))
        _networksStore = State(initialValue: NetworksStore(store: store))
        _composeStore = State(initialValue: ComposeStore(store: store, registry: mcp.composeRegistry))
        _mcp = State(initialValue: mcp)
    }

    var body: some Scene {
        // A single-instance Window, so "Open window" from the menu bar never opens a second copy.
        Window("GDocker", id: "main") {
            MainWindow()
                .environment(store)
                .environment(imagesStore)
                .environment(volumesStore)
                .environment(networksStore)
                .environment(composeStore)
                .environment(mcp)
                .frame(minWidth: 1000, minHeight: 600)
                .task {
                    store.start()
                    await mcp.startIfEnabled()
                }
                .confirmationDialog(
                    Text("System Prune?", bundle: .l10n),
                    isPresented: $confirmSystemPrune,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) {
                        Task {
                            await performSystemPrune()
                        }
                    } label: {
                        Text("Prune System", bundle: .l10n)
                    }
                } message: {
                    Text("This will remove all stopped containers, unused networks, and dangling images. Volumes will not be removed.", bundle: .l10n)
                }
        }
        .commands {
            CommandMenu(Text("Docker", bundle: .l10n)) {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    confirmSystemPrune = true
                } label: {
                    Text("System Prune...", bundle: .l10n)
                }
                .disabled(!store.connected || store.client == nil || isPruning)
            }
        }
        Settings { SettingsView().environment(mcp) }
        MenuBarExtra(isInserted: $keepInMenuBar) {
            MenuBarContent().environment(store).environment(mcp)
        } label: {
            Image(systemName: "shippingbox")
        }
    }

    private func performSystemPrune() async {
        guard let client = store.client, !isPruning else { return }
        isPruning = true
        defer { isPruning = false }
        do {
            _ = try await client.systemPrune(all: false, volumes: false)
            store.lastError = nil
        } catch {
            store.lastError = error.localizedDescription
        }
        await store.refresh()
        await imagesStore.refresh()
        await volumesStore.refresh()
        await networksStore.refresh()
        await composeStore.refresh()
    }
}
