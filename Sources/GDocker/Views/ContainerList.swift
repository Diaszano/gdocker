import GDockerCore
import SwiftUI

struct ContainerList: View {
    @Environment(ContainersStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedID) {
            ForEach(store.visibleGroups) { group in
                Section {
                    ForEach(group.containers) { ContainerRow(container: $0).tag($0.id) }
                } header: {
                    if let project = group.project {
                        Text(verbatim: project.uppercased())
                    } else {
                        Text("No group", bundle: .l10n)
                    }
                }
            }
        }
        .searchable(text: $store.searchText, prompt: Text("Search containers", bundle: .l10n))
        .navigationTitle(Text("Containers", bundle: .l10n))
    }
}

private struct ContainerRow: View {
    let container: ContainerSummary

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(kind: container.statusKind)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: container.name).fontWeight(.semibold)
                Text(verbatim: container.image).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: container.status)
                .font(.caption)
                .foregroundStyle(container.statusKind == .transitioning || container.statusKind == .failed
                                 ? container.statusKind.color : Color.secondary)
        }
        .padding(.vertical, 2)
    }
}
