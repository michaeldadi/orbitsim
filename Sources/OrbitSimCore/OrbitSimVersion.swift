import Foundation

public enum OrbitSimVersion {
    public static let app = "0.1.0"
    public static let protocolVersion = 1
}

public struct CLIInstaller: Sendable {
    public init() {}

    @discardableResult
    public func install(from appBundle: URL, into directory: URL) throws -> URL {
        guard appBundle.isFileURL, directory.isFileURL else {
            throw OrbitSimError.invalidArgument("CLI installation needs local paths")
        }
        let version = Bundle(url: appBundle)?.infoDictionary?["CFBundleShortVersionString"] as? String
        guard version == OrbitSimVersion.app else {
            throw OrbitSimError.invalidArgument("App and CLI versions do not match")
        }
        let executable = appBundle.appendingPathComponent("Contents/SharedSupport/orbitsim")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw OrbitSimError.invalidArgument("This app does not contain the CLI")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        let link = directory.appendingPathComponent("orbitsim")
        if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) {
            guard existing == executable.path else {
                throw OrbitSimError.destinationExists(link.path)
            }
            return link
        }
        guard !FileManager.default.fileExists(atPath: link.path) else {
            throw OrbitSimError.destinationExists(link.path)
        }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
        return link
    }
}
