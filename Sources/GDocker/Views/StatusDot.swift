import GDockerCore
import SwiftUI

extension StatusKind {
    var color: Color {
        switch self {
        case .running: .green
        case .transitioning: .orange
        case .stopped: .gray
        case .failed: .red
        }
    }
}

struct StatusDot: View {
    let kind: StatusKind

    var body: some View {
        Circle().fill(kind.color).frame(width: 10, height: 10)
    }
}
