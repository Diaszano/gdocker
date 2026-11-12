import SwiftUI

@main
struct GDockerApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text("Containers", bundle: .l10n)
                Text("Docker disconnected", bundle: .l10n).foregroundStyle(.secondary)
            }
            .frame(minWidth: 400, minHeight: 200)
        }
    }
}
