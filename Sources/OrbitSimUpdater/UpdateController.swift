import Foundation
import Sparkle

/// Starts signed update checks only in a release with a configured feed and EdDSA key.
@MainActor
public final class UpdateController {
    private let controller: SPUStandardUpdaterController?

    public init(bundle: Bundle = .main) {
        #if DEBUG
        controller = nil
        #else
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        if let feed, let url = URL(string: feed), url.scheme == "https", url.host != nil,
           let key, Data(base64Encoded: key)?.count == 32 {
            controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
            )
        } else {
            controller = nil
        }
        #endif
    }

    public var isConfigured: Bool { controller != nil }

    public func checkForUpdates() {
        guard let controller, controller.updater.canCheckForUpdates else { return }
        controller.updater.checkForUpdates()
    }
}
