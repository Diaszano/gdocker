import GDockerCore
import SwiftUI

extension StatusKind {
    var color: Color {
        switch self {
        case .running: Color.ctp.ok
        case .transitioning: Color.ctp.warn
        case .stopped: Color.ctp.muted
        case .failed: Color.ctp.err
        }
    }
}

struct StatusDot: View {
    let kind: StatusKind

    var body: some View {
        Circle().fill(kind.color).frame(width: 10, height: 10)
    }
}
