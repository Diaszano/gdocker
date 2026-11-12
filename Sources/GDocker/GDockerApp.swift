import SwiftUI

@main
struct GDockerApp: App {
    @State private var store = ContainersStore()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 600)
                .task { store.start() }
        }
    }
}
