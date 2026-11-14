import AppKit
import GDockerCore
import SwiftUI

@MainActor
private enum ServiceLogoCache {
    static var images: [String: NSImage] = [:]

    static func image(forSlug slug: String) -> NSImage? {
        if let cached = images[slug] {
            return cached
        }
        let url =
            Bundle.l10n.url(forResource: slug, withExtension: "png", subdirectory: "ServiceLogos")
            ?? Bundle.l10n.url(forResource: slug, withExtension: "png")
        guard let url, let loaded = NSImage(contentsOf: url) else {
            return nil
        }
        images[slug] = loaded
        return loaded
    }
}

/// Centered 28×28 service badge using the Penpot `Logos` brand icon set with SF Symbol fallback.
struct ServiceLogo: View {
    let image: String
    var size: CGFloat = 28

    private var kind: ServiceKind { ServiceKind.from(image: image) }
    private var logoSlug: String? { ServiceKind.logoSlug(for: image) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.ctp.hover)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.ctp.muted.opacity(0.22), lineWidth: 0.75)
                )

            if let slug = logoSlug, let nsImage = ServiceLogoCache.image(forSlug: slug) {
                let iconSize = size * 0.64
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
            } else {
                Image(systemName: kind == .kafka ? "arrow.left.arrow.right.circle" : "shippingbox")
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(kind == .kafka ? Color.ctp.text : Color.ctp.muted)
            }
        }
        .frame(width: size, height: size)
    }
}
