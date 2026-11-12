import GDockerCore
import SwiftUI

struct LogsTab: View {
    @Bindable var model: LogsModel

    var body: some View {
        let lines = model.visibleLines
        return VStack(spacing: 8) {
            HStack(spacing: 16) {
                TextField(text: $model.filter, prompt: Text("Filter logs", bundle: .l10n)) { EmptyView() }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Toggle(isOn: $model.follow) { Text("Follow", bundle: .l10n) }
                Toggle(isOn: $model.showTimestamps) { Text("Timestamps", bundle: .l10n) }
                Spacer()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { LogRow(line: $0).id($0.id) }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(white: 0.118))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: lines.last?.id) { _, last in
                    guard model.follow, let last else { return }
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .padding(16)
    }
}

private struct LogRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let timestamp = line.timestamp {
                Text(timestamp.formatted(.dateTime.hour().minute().second()))
                    .foregroundStyle(Color(white: 0.5))
            }
            Text(verbatim: line.text)
                .foregroundStyle(line.stream == .stderr ? Color(red: 0.96, green: 0.53, blue: 0.44) : Color(white: 0.83))
                .textSelection(.enabled)
        }
        .font(.system(size: 12, design: .monospaced))
    }
}
