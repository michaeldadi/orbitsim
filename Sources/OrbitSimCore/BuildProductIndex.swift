import Foundation

public enum BuildProductPlatform: String, Codable, Sendable {
    case simulator
    case physical

    var productDirectorySuffix: String {
        switch self {
        case .simulator: "-iphonesimulator"
        case .physical: "-iphoneos"
        }
    }

    var supportedPlatform: String {
        switch self {
        case .simulator: "iPhoneSimulator"
        case .physical: "iPhoneOS"
        }
    }
}

public struct BuildProduct: Identifiable, Codable, Sendable {
    public let id: String
    public let project: String
    public let configuration: String
    public let name: String
    public let bundleID: String
    public let platform: BuildProductPlatform
    public let modifiedAt: Date
    public let appURL: URL
}

/// Finds direct Xcode app products. It never installs or chooses one implicitly.
public struct BuildProductIndex: Sendable {
    public init() {}

    public func scan(derivedDataRoot: URL, platform: BuildProductPlatform) throws -> [BuildProduct] {
        guard derivedDataRoot.isFileURL,
              (try? derivedDataRoot.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw OrbitSimError.invalidArgument("DerivedData root must be an existing local directory")
        }
        let childFolders = (try FileManager.default.contentsOfDirectory(
            at: derivedDataRoot, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )).filter {
            guard let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }
        var products: [BuildProduct] = []
        for projectFolder in [derivedDataRoot] + childFolders {
            let productsFolder = projectFolder.appendingPathComponent("Build/Products", isDirectory: true)
            guard let configurations = try? FileManager.default.contentsOfDirectory(
                at: productsFolder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for configuration in configurations where
                configuration.lastPathComponent.hasSuffix(platform.productDirectorySuffix) {
                guard let values = try? configuration.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true,
                      let apps = try? FileManager.default.contentsOfDirectory(
                        at: configuration, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                      ) else { continue }
                for app in apps where app.pathExtension.lowercased() == "app" {
                    if let product = product(at: app, project: projectFolder.lastPathComponent,
                                             configuration: configuration.lastPathComponent,
                                             platform: platform) {
                        products.append(product)
                    }
                }
            }
        }
        return products.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.appURL.path < $1.appURL.path
        }
    }

    public func validate(_ product: BuildProduct) throws {
        guard let current = self.product(at: product.appURL, project: product.project,
                                    configuration: product.configuration, platform: product.platform),
              current.bundleID == product.bundleID,
              current.modifiedAt == product.modifiedAt,
              current.appURL.standardizedFileURL == product.appURL.standardizedFileURL else {
            throw OrbitSimError.invalidArgument("The selected build changed or is no longer available; refresh recent builds")
        }
    }

    private func product(at app: URL, project: String, configuration: String,
                         platform: BuildProductPlatform) -> BuildProduct? {
        guard let values = try? app.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]),
              values.isDirectory == true, values.isSymbolicLink != true,
              let data = try? Data(contentsOf: app.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["CFBundlePackageType"] as? String == "APPL",
              let bundleID = plist["CFBundleIdentifier"] as? String, bundleID.contains("."),
              let supported = plist["CFBundleSupportedPlatforms"] as? [String],
              supported.contains(platform.supportedPlatform) else { return nil }
        let name = (plist["CFBundleDisplayName"] as? String) ??
            (plist["CFBundleName"] as? String) ?? app.deletingPathExtension().lastPathComponent
        return BuildProduct(
            id: app.standardizedFileURL.path,
            project: project,
            configuration: configuration,
            name: name,
            bundleID: bundleID,
            platform: platform,
            modifiedAt: values.contentModificationDate ?? .distantPast,
            appURL: app.standardizedFileURL
        )
    }
}
