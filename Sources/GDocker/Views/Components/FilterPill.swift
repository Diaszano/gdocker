import SwiftUI

/// Capsule filter pill with optional status dot, matching Penpot `Componentes > Filtro`.
struct FilterPill: View {
    let title: LocalizedStringKey
    let dotColor: Color?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                }
                Text(title, bundle: .l10n)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.ctp.text : Color.ctp.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.ctp.accent.opacity(0.16) : Color.ctp.side)
                    .overlay(
                        Capsule().strokeBorder(
                            isSelected ? Color.ctp.accent : Color.ctp.muted.opacity(0.28),
                            lineWidth: 1
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
