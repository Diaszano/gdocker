import SwiftUI

struct SettingsView: View {
    @Environment(McpController.self) private var mcp
    @AppStorage(SettingsKey.theme) private var theme = Theme.system
    @AppStorage(SettingsKey.keepInMenuBar) private var keepInMenuBar = false
    @AppStorage(SettingsKey.compactMenuBarIcon) private var compactMenuBarIcon = false
    @AppStorage(SettingsKey.mcpAutoStart) private var mcpAutoStart = true
    @AppStorage(SettingsKey.mcpPort) private var mcpPort = SettingsKey.defaultMcpPort

    private var portIsValid: Bool { SettingsKey.mcpPortRange.contains(mcpPort) }

    var body: some View {
        Form {
            Section {
                Picker(selection: $theme) {
                    ForEach(Theme.allCases, id: \.self) { Text($0.title, bundle: .l10n).tag($0) }
                } label: {
                    Text("Theme", bundle: .l10n)
                }
                Toggle(isOn: $keepInMenuBar) {
                    Text("Keep running in the menu bar when the window is closed", bundle: .l10n)
                }
                Toggle(isOn: $compactMenuBarIcon) {
                    Text("Compact menu bar icon (icon only)", bundle: .l10n)
                }
                .disabled(!keepInMenuBar)
            }
            Section(header: Text("MCP server", bundle: .l10n)) {
                Toggle(isOn: $mcpAutoStart) {
                    Text("Start the MCP server when the app opens", bundle: .l10n)
                }
                TextField(value: $mcpPort, format: .number.grouping(.never)) {
                    Text("MCP port", bundle: .l10n)
                }
                .onSubmit { if portIsValid { Task { await mcp.restart() } } }
                if !portIsValid {
                    Text("Choose a port between 1024 and 65535", bundle: .l10n)
                        .font(.caption).foregroundStyle(Color.ctp.err)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: theme) { _, new in new.apply() }
    }
}
