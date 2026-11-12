import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.theme) private var theme = Theme.system
    @AppStorage(SettingsKey.keepInMenuBar) private var keepInMenuBar = false

    var body: some View {
        Form {
            Picker(selection: $theme) {
                ForEach(Theme.allCases, id: \.self) { Text($0.title, bundle: .l10n).tag($0) }
            } label: { Text("Theme", bundle: .l10n) }
            Toggle(isOn: $keepInMenuBar) {
                Text("Keep running in the menu bar when the window is closed", bundle: .l10n)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: theme) { _, new in new.apply() }
    }
}
