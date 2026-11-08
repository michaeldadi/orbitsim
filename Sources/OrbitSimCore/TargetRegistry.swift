import Foundation

public struct TargetRegistry: Sendable {
    public let simulators: SimulatorClient
    public let physicalDevices: PhysicalDeviceClient

    public init(
        simulators: SimulatorClient = SimulatorClient(),
        physicalDevices: PhysicalDeviceClient = PhysicalDeviceClient()
    ) {
        self.simulators = simulators
        self.physicalDevices = physicalDevices
    }

    public func allTargets() async throws -> [DeviceTarget] {
        async let simulatorTargets = simulators.targets()
        async let physicalTargets = physicalDevices.targets()
        return try await simulatorTargets + physicalTargets
    }

    public func resolve(_ id: String) async throws -> DeviceTarget {
        // Keep the common Simulator path independent of sometimes-slow USB discovery.
        if let target = try await simulators.targets().first(where: { $0.id == id }) {
            return target
        }
        if let target = try await physicalDevices.targets().first(where: { $0.id == id }) {
            return target
        }
        throw OrbitSimError.targetNotFound(id)
    }

    public func screenshot(
        _ id: String, to destination: URL, display: String? = nil,
        format: ScreenshotFormat = .png
    ) async throws {
        switch try await resolve(id).kind {
        case .simulator: try await simulators.screenshot(id, to: destination, display: display, format: format)
        case .physical:
            guard display == nil, format == .png else {
                throw OrbitSimError.unsupportedAction(
                    "Physical-device screenshots currently support only PNG without display selection"
                )
            }
            try await physicalDevices.screenshot(id, to: destination)
        }
    }

    /// Used only after the macOS save panel has approved replacement.
    public func screenshotReplacing(_ id: String, at destination: URL,
                                    display: String? = nil) async throws {
        guard destination.isFileURL, destination.pathExtension.lowercased() == "png" else {
            throw OrbitSimError.invalidArgument("Output must be a local .png file")
        }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".orbitsim-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await screenshot(id, to: temporary, display: display)
        try Data(contentsOf: temporary).write(to: destination, options: .atomic)
    }

    public func openURL(_ id: String, url: URL) async throws {
        switch try await resolve(id).kind {
        case .simulator: try await simulators.openURL(id, url: url)
        case .physical: try await physicalDevices.openURL(id, url: url)
        }
    }

    public func install(_ id: String, app: URL) async throws {
        switch try await resolve(id).kind {
        case .simulator: try await simulators.install(id, app: app)
        case .physical: try await physicalDevices.install(id, app: app)
        }
    }

    public func launch(_ id: String, bundleID: String) async throws {
        switch try await resolve(id).kind {
        case .simulator: try await simulators.launch(id, bundleID: bundleID)
        case .physical: try await physicalDevices.launch(id, bundleID: bundleID)
        }
    }

    public func uninstall(_ id: String, bundleID: String) async throws {
        switch try await resolve(id).kind {
        case .simulator: try await simulators.uninstall(id, bundleID: bundleID)
        case .physical: try await physicalDevices.uninstall(id, bundleID: bundleID)
        }
    }

    public func setLocation(_ id: String, latitude: Double, longitude: Double) async throws {
        switch try await resolve(id).kind {
        case .simulator: try await simulators.setLocation(id, latitude: latitude, longitude: longitude)
        case .physical: try await physicalDevices.setLocation(id, latitude: latitude, longitude: longitude)
        }
    }

    public func clearLocation(_ id: String) async throws {
        switch try await resolve(id).kind {
        case .simulator: try await simulators.clearLocation(id)
        case .physical: try await physicalDevices.clearLocation(id)
        }
    }
}
