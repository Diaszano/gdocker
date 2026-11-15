import SwiftUI

/// 28×28 square bordered icon button matching Penpot `Componentes > Botão ícone`.
struct IconActionButton: View {
    let systemImage: String
    var tint: Color = Color.ctp.text
    var size: CGFloat = 28
    var help: LocalizedStringKey? = nil
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.43, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovered ? tint.opacity(0.14) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(tint.opacity(hovered ? 0.55 : 0.28), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help.map { Text($0, bundle: .l10n) } ?? Text(verbatim: ""))
    }
}
