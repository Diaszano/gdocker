import SwiftUI

/// Icon + label tab bar with bottom accent indicator, matching Penpot `Componentes > Aba`.
struct TabStrip<Tab: Hashable>: View {
    struct Item: Identifiable {
        let tab: Tab
        let title: LocalizedStringKey
        let systemImage: String
        var id: Tab { tab }
    }

    @Binding var selection: Tab
    let items: [Item]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(items) { item in
                let active = item.tab == selection
                Button {
                    selection = item.tab
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 11, weight: active ? .semibold : .regular))
                            Text(item.title, bundle: .l10n)
                                .font(.system(size: 12, weight: active ? .semibold : .medium))
                        }
                        .foregroundStyle(active ? Color.ctp.accent : Color.ctp.muted)
                        Rectangle()
                            .fill(active ? Color.ctp.accent : Color.clear)
                            .frame(height: 2)
                    }
                    .padding(.top, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}
