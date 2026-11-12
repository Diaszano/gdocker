import SwiftUI

struct InspectTab: View {
    let rawJSON: String

    var body: some View {
        ScrollView {
            Text(verbatim: rawJSON)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }
}
