import GDockerCore
import SwiftUI

struct LogsTab: View {
    @Bindable var model: LogsModel

    var body: some View {
        let lines = model.visibleLines
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ctp.muted)
                    TextField(text: $model.filter, prompt: Text("Filter logs", bundle: .l10n)) { EmptyView() }
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.ctp.side)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.ctp.muted.opacity(0.24), lineWidth: 1))
                )

                Button {
                    model.follow.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.follow ? Color.ctp.accent : Color.ctp.muted)
                            .frame(width: 7, height: 7)
                        Text("Follow", bundle: .l10n)
                            .font(.system(size: 12, weight: model.follow ? .semibold : .regular))
                            .foregroundStyle(model.follow ? Color.ctp.text : Color.ctp.muted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.ctp.side))
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)

                Toggle(isOn: $model.showTimestamps) {
                    Text("Timestamps", bundle: .l10n)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ctp.muted)
                }
                .toggleStyle(.checkbox)
                .fixedSize(horizontal: true, vertical: false)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { LogRow(line: $0).id($0.id) }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.ctp.side)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ctp.muted.opacity(0.16), lineWidth: 1))
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
                    .foregroundStyle(Color.ctp.muted)
            }
            Text(verbatim: line.text)
                .foregroundStyle(line.stream == .stderr ? Color.ctp.err : Color.ctp.text)
                .textSelection(.enabled)
        }
        .font(.system(size: 12, design: .monospaced))
    }
}
