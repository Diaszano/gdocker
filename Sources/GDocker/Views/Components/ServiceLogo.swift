import GDockerCore
import SwiftUI

/// Centered 28×28 service badge for a container's image, matching the Penpot `Logos` & `Linha container` specs.
struct ServiceLogo: View {
    let image: String
    var size: CGFloat = 28

    private var kind: ServiceKind { ServiceKind.from(image: image) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(tint.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(tint.opacity(0.28), lineWidth: 0.75)
                )
            Image(systemName: symbolName)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }

    private var symbolName: String {
        switch kind {
        case .postgres: "cylinder.split.1x2"
        case .redis: "bolt.horizontal.circle"
        case .nginx: "network"
        case .rabbitmq: "tray.2"
        case .mongodb: "leaf"
        case .mysql: "cylinder"
        case .elasticsearch: "magnifyingglass.circle"
        case .kafka: "arrow.left.arrow.right.circle"
        case .traefik: "arrow.triangle.branch"
        case .grafana: "chart.xyaxis.line"
        case .prometheus: "flame"
        case .minio: "externaldrive.badge.icloud"
        case .generic: "shippingbox"
        }
    }

    private var tint: Color {
        switch kind {
        case .postgres: Color.ctp.accent
        case .redis: Color.ctp.err
        case .nginx: Color.ctp.ok
        case .rabbitmq: Color.ctp.warn
        case .mongodb: Color.ctp.ok
        case .mysql: Color.ctp.accent
        case .elasticsearch: Color.ctp.warn
        case .kafka: Color.ctp.text
        case .traefik: Color.ctp.accent
        case .grafana: Color.ctp.warn
        case .prometheus: Color.ctp.err
        case .minio: Color.ctp.err
        case .generic: Color.ctp.muted
        }
    }
}
