import Foundation

public struct PhysicalDeviceClient: Sendable {
    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    public func targets() async throws -> [DeviceTarget] {
        let result = try await run(["list", "devices"])
        guard let data = result.stdout.data(using: .utf8),
              let payload = try? JSONDecoder().decode(DeviceList.self, from: data) else {
            throw OrbitSimError.invalidResponse(tool: "devicectl")
        }
        return payload.result.devices.compactMap { device in
            guard device.properties.hardware.reality == "physical",
                  let udid = device.properties.hardware.udid else { return nil }
            return DeviceTarget(
                id: udid,
                name: device.properties.state.name,
                kind: .physical,
                state: device.properties.connection.state == "connected" ? .connected : .unavailable,
                platform: device.properties.hardware.platform,
                osVersion: device.properties.software.osVersionNumber?.stringValue
            )
        }.sorted { $0.name < $1.name }
    }

    public func screenshot(_ id: String, to destination: URL) async throws {
        try SimulatorClient.checkDestination(destination, extension: "png")
        _ = try await run([
            "device", "capture", "screenshot", "--device", id,
            "--destination", destination.path,
        ], timeoutSeconds: 90)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: destination.path)
    }

    public func openURL(_ id: String, url: URL) async throws {
        _ = try await run(["device", "process", "openURL", "--device", id, url.absoluteString])
    }

    public func install(_ id: String, app: URL) async throws {
        guard app.isFileURL, app.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: app.path) else {
            throw OrbitSimError.invalidArgument("Expected an existing local .app bundle")
        }
        _ = try await run(["device", "install", "app", "--device", id, app.path], timeoutSeconds: 120)
    }

    public func launch(_ id: String, bundleID: String) async throws {
        guard bundleID.contains("."), !bundleID.hasPrefix("-") else {
            throw OrbitSimError.invalidArgument("Expected an application bundle identifier")
        }
        _ = try await run(["device", "process", "launch", "--device", id, bundleID], timeoutSeconds: 60)
    }

    public func uninstall(_ id: String, bundleID: String) async throws {
        guard bundleID.contains("."), !bundleID.hasPrefix("-") else {
            throw OrbitSimError.invalidArgument("Expected an application bundle identifier")
        }
        _ = try await run(["device", "uninstall", "app", "--device", id, bundleID], timeoutSeconds: 60)
    }

    public func setLocation(_ id: String, latitude: Double, longitude: Double) async throws {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw OrbitSimError.invalidArgument("Latitude or longitude is out of range")
        }
        _ = try await run([
            "device", "simulate", "location", "coordinate", "--device", id,
            "--latitude", String(latitude), "--longitude", String(longitude),
        ])
    }

    public func clearLocation(_ id: String) async throws {
        _ = try await run(["device", "simulate", "location", "clear", "--device", id])
    }

    private func run(_ arguments: [String], timeoutSeconds: Double = 30) async throws -> CommandResult {
        let result = try await runner.run(
            executable: "/usr/bin/xcrun",
            arguments: ["devicectl", "--json-output", "-"] + arguments,
            timeoutSeconds: timeoutSeconds
        )
        guard result.exitCode == 0 else {
            throw OrbitSimError.commandFailed(
                tool: "devicectl", code: result.exitCode,
                detail: String(result.stderr.prefix(2_000)).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }
}

private struct DeviceList: Decodable {
    let result: Result
    struct Result: Decodable { let devices: [Device] }
    struct Device: Decodable { let properties: Properties }
    struct Properties: Decodable {
        let connection: Connection
        let hardware: Hardware
        let software: Software
        let state: State
    }
    struct Connection: Decodable { let state: String? }
    struct Hardware: Decodable {
        let udid: String?
        let reality: String?
        let platform: String
    }
    struct Software: Decodable { let osVersionNumber: Version? }
    struct Version: Decodable { let stringValue: String }
    struct State: Decodable { let name: String }
}
