import SwiftUI

struct MainWindow: View {
    @Environment(ContainersStore.self) private var store

    var body: some View {
        NavigationSplitView {
            List {
                Section(header: Text(verbatim: "Docker")) {
                    HStack {
                        Text("Containers", bundle: .l10n)
                        Spacer()
                        Text(verbatim: "\(store.all.count)").foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    Circle().fill(store.connected ? Color.green : Color.red).frame(width: 8, height: 8)
                    store.connected
                        ? Text("Docker connected", bundle: .l10n)
                        : Text("Docker disconnected", bundle: .l10n)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } content: {
            ContainerList()
                .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 480)
        } detail: {
            if let selected = store.selected {
                Text(verbatim: selected.name)
            } else {
                Text("Select a container", bundle: .l10n).foregroundStyle(.secondary)
            }
        }
    }
}
