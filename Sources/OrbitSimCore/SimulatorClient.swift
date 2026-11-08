import Foundation

public struct SimulatorClient: Sendable {
    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    public func targets() async throws -> [DeviceTarget] {
        let result = try await run(["list", "devices", "--json"])
        guard let data = result.stdout.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SimulatorList.self, from: data) else {
            throw OrbitSimError.invalidResponse(tool: "simctl")
        }
        var discovered: [DeviceTarget] = []
        for (runtime, devices) in payload.devices {
            let platform: String
            if runtime.contains("xrOS") {
                platform = "visionOS"
            } else if runtime.contains("watchOS") {
                platform = "watchOS"
            } else {
                platform = "iOS"
            }
            for device in devices where device.isAvailable {
                discovered.append(DeviceTarget(
                    id: device.udid,
                    name: device.name,
                    kind: .simulator,
                    state: device.state == "Booted" ? .booted : .shutdown,
                    platform: platform,
                    runtimeIdentifier: runtime
                ))
            }
        }
        return discovered.sorted {
            if $0.state != $1.state { return $0.state == .booted }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }
    }

    public func boot(_ id: String) async throws {
        _ = try await run(["boot", id], timeoutSeconds: 90)
    }

    public func shutdown(_ id: String) async throws {
        _ = try await run(["shutdown", id], timeoutSeconds: 90)
    }

    public func screenshot(
        _ id: String, to destination: URL, display: String? = nil,
        format: ScreenshotFormat = .png
    ) async throws {
        guard destination.isFileURL, format.fileExtensions.contains(destination.pathExtension.lowercased()) else {
            throw OrbitSimError.invalidArgument(
                "Output extension must match screenshot type \(format.rawValue)"
            )
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw OrbitSimError.destinationExists(destination.path)
        }
        var arguments = ["io", id, "screenshot", "--type=\(format.rawValue)"]
        if let display {
            guard !display.isEmpty, !display.hasPrefix("-") else {
                throw OrbitSimError.invalidArgument("Display identifier is invalid")
            }
            arguments.append("--display=\(display)")
        }
        arguments.append(destination.path)
        _ = try await run(arguments, timeoutSeconds: 90)
    }

    public func openURL(_ id: String, url: URL) async throws {
        _ = try await run(["openurl", id, url.absoluteString])
    }

    public func setAppearance(_ id: String, dark: Bool) async throws {
        _ = try await run(["ui", id, "appearance", dark ? "dark" : "light"])
    }

    public func setLocation(_ id: String, latitude: Double, longitude: Double) async throws {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw OrbitSimError.invalidArgument("Latitude or longitude is out of range")
        }
        _ = try await run(["location", id, "set", "\(latitude),\(longitude)"])
    }

    public func clearLocation(_ id: String) async throws {
        _ = try await run(["location", id, "clear"])
    }

    public func install(_ id: String, app: URL) async throws {
        try Self.requireLocalFile(app, extension: "app")
        _ = try await run(["install", id, app.path], timeoutSeconds: 120)
    }

    public func launch(_ id: String, bundleID: String) async throws {
        try Self.requireBundleID(bundleID)
        _ = try await run(["launch", id, bundleID], timeoutSeconds: 60)
    }

    public func terminate(_ id: String, bundleID: String) async throws {
        try Self.requireBundleID(bundleID)
        _ = try await run(["terminate", id, bundleID])
    }

    public func uninstall(_ id: String, bundleID: String) async throws {
        try Self.requireBundleID(bundleID)
        _ = try await run(["uninstall", id, bundleID], timeoutSeconds: 60)
    }

    public func addMedia(_ id: String, file: URL) async throws {
        guard file.isFileURL, FileManager.default.fileExists(atPath: file.path) else {
            throw OrbitSimError.invalidArgument("Media must be an existing local file")
        }
        _ = try await run(["addmedia", id, file.path], timeoutSeconds: 90)
    }

    public func setPrivacy(
        _ id: String, action: PrivacyAction, service: PrivacyService, bundleID: String
    ) async throws {
        try Self.requireBundleID(bundleID)
        _ = try await run(["privacy", id, action.rawValue, service.rawValue, bundleID])
    }

    public func clearStatusBar(_ id: String) async throws {
        _ = try await run(["status_bar", id, "clear"])
    }

    public func overrideStatusBar(_ id: String, time: String? = nil, batteryLevel: Int? = nil) async throws {
        var arguments = ["status_bar", id, "override"]
        if let time {
            guard !time.isEmpty, time.count <= 40 else {
                throw OrbitSimError.invalidArgument("Status bar time must be 1–40 characters")
            }
            arguments += ["--time", time]
        }
        if let batteryLevel {
            guard (0...100).contains(batteryLevel) else {
                throw OrbitSimError.invalidArgument("Battery level must be 0–100")
            }
            arguments += ["--batteryLevel", String(batteryLevel)]
        }
        guard arguments.count > 3 else {
            throw OrbitSimError.invalidArgument("Provide a time or battery level")
        }
        _ = try await run(arguments)
    }

    public func sendPush(_ id: String, bundleID: String, payload: URL) async throws {
        try Self.requireBundleID(bundleID)
        guard payload.isFileURL, let data = try? Data(contentsOf: payload), data.count <= 4_096,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["aps"] is [String: Any] else {
            throw OrbitSimError.invalidArgument("Push payload must be an existing JSON object with aps and at most 4096 bytes")
        }
        _ = try await run(["push", id, bundleID, payload.path])
    }

    public func displays(_ id: String) async throws -> String {
        try await run(["io", id, "enumerate"]).stdout
    }

    public func connectedDisplays(_ id: String) async throws -> [SimulatorDisplay] {
        let screens = SimulatorDisplayParser.connectedScreens(in: try await displays(id))
        guard !screens.isEmpty else { throw OrbitSimError.invalidResponse(tool: "simctl io enumerate") }
        return screens
    }

    private func run(_ arguments: [String], timeoutSeconds: Double = 30) async throws -> CommandResult {
        let result = try await runner.run(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl"] + arguments,
            timeoutSeconds: timeoutSeconds
        )
        guard result.exitCode == 0 else {
            throw OrbitSimError.commandFailed(
                tool: "simctl", code: result.exitCode,
                detail: String(result.stderr.prefix(2_000)).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }

    static func checkDestination(_ destination: URL, extension expected: String) throws {
        guard destination.isFileURL, destination.pathExtension.lowercased() == expected else {
            throw OrbitSimError.invalidArgument("Output must be a local .\(expected) file")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw OrbitSimError.destinationExists(destination.path)
        }
    }


    private static func requireLocalFile(_ file: URL, extension expected: String) throws {
        guard file.isFileURL, file.pathExtension.lowercased() == expected,
              FileManager.default.fileExists(atPath: file.path) else {
            throw OrbitSimError.invalidArgument("Expected an existing local .\(expected) file")
        }
    }

    private static func requireBundleID(_ value: String) throws {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
              segments.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) }) else {
            throw OrbitSimError.invalidArgument("Expected a bundle identifier such as com.example.App")
        }
    }
}

public enum PrivacyAction: String, Sendable {
    case grant, revoke, reset
}

public enum ScreenshotFormat: String, Sendable {
    case png, jpeg, tiff, bmp, gif

    var fileExtensions: Set<String> {
        switch self {
        case .jpeg: ["jpg", "jpeg"]
        case .tiff: ["tif", "tiff"]
        case .png: ["png"]
        case .bmp: ["bmp"]
        case .gif: ["gif"]
        }
    }
}

public enum PrivacyService: String, Sendable {
    case calendar, contacts, location, photos, microphone, motion, reminders, siri
}

private struct SimulatorList: Decodable {
    let devices: [String: [SimulatorDevice]]
}

private struct SimulatorDevice: Decodable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool
}
