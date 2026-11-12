import Foundation

extension Bundle {
    /// Resource bundle for both `swift run` and the packaged `.app`.
    /// SPM's generated accessor looks next to the .app, which breaks code signing, so look in Contents/Resources first.
    static let l10n: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("GDocker_GDocker.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()
}
