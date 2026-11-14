import GDockerCore
import SwiftUI

/// Pill badge with a status dot and tinted background, matching Penpot `Componentes > Status`.
struct StatusBadge: View {
    let color: Color
    let label: LocalizedStringKey

    init(color: Color, label: LocalizedStringKey) {
        self.color = color
        self.label = label
    }

    init(kind: StatusKind, label: LocalizedStringKey) {
        self.color = kind.color
        self.label = label
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label, bundle: .l10n)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}
