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

    public func increaseContrast(_ id: String) async throws -> Bool {
        let value = try await run(["ui", id, "increase_contrast"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "enabled": return true
        case "disabled": return false
        case "unsupported": throw OrbitSimError.unsupportedAction("Increase Contrast is not supported by this Simulator")
        default: throw OrbitSimError.invalidResponse(tool: "simctl ui increase_contrast")
        }
    }

    public func setIncreaseContrast(_ id: String, enabled: Bool) async throws {
        _ = try await run(["ui", id, "increase_contrast", enabled ? "enabled" : "disabled"])
    }

    public func contentSize(_ id: String) async throws -> SimulatorContentSize {
        let value = try await run(["ui", id, "content_size"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let size = SimulatorContentSize(rawValue: value) { return size }
        if value == "unsupported" {
            throw OrbitSimError.unsupportedAction("Content size is not supported by this Simulator")
        }
        throw OrbitSimError.invalidResponse(tool: "simctl ui content_size")
    }

    public func setContentSize(_ id: String, size: SimulatorContentSize) async throws {
        _ = try await run(["ui", id, "content_size", size.rawValue])
    }

    public func setLocation(_ id: String, latitude: Double, longitude: Double) async throws {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw OrbitSimError.invalidArgument("Latitude or longitude is out of range")
        }
        _ = try await run(["location", id, "set", "\(latitude),\(longitude)"])
    }

    public func startRoute(
        _ id: String, waypoints: [SimulatorWaypoint], speedMetersPerSecond: Double = 20,
        updateIntervalSeconds: Double = 1
    ) async throws {
        guard (2...100).contains(waypoints.count) else {
            throw OrbitSimError.invalidArgument("A route needs 2–100 waypoints")
        }
        guard speedMetersPerSecond.isFinite, (0.1...500).contains(speedMetersPerSecond),
              updateIntervalSeconds.isFinite, (0.1...60).contains(updateIntervalSeconds) else {
            throw OrbitSimError.invalidArgument("Route speed or interval is out of range")
        }
        let arguments = ["location", id, "start",
                         "--speed=\(speedMetersPerSecond)",
                         "--interval=\(updateIntervalSeconds)"] + waypoints.map(\.simctlArgument)
        _ = try await run(arguments)
    }

    public func clearLocation(_ id: String) async throws {
        _ = try await run(["location", id, "clear"])
    }

    public func install(_ id: String, app: URL) async throws {
        try Self.requireLocalFile(app, extension: "app")
        _ = try await run(["install", id, app.path], timeoutSeconds: 120)
    }

    public func launch(_ id: String, bundleID: String,
                       terminateRunningProcess: Bool = false) async throws {
        try Self.requireBundleID(bundleID)
        var arguments = ["launch"]
        if terminateRunningProcess { arguments.append("--terminate-running-process") }
        arguments += [id, bundleID]
        _ = try await run(arguments, timeoutSeconds: 60)
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

    public func statusBarOverrides(_ id: String) async throws -> String {
        try await run(["status_bar", id, "list"]).stdout
    }

    public func overrideStatusBar(_ id: String, time: String? = nil, batteryLevel: Int? = nil) async throws {
        try await overrideStatusBar(id, settings: StatusBarOverride(time: time, batteryLevel: batteryLevel))
    }

    public func overrideStatusBar(_ id: String, settings: StatusBarOverride) async throws {
        var arguments = ["status_bar", id, "override"]
        if let time = settings.time {
            guard !time.isEmpty, time.count <= 40 else {
                throw OrbitSimError.invalidArgument("Status bar time must be 1–40 characters")
            }
            arguments += ["--time", time]
        }
        if let dataNetwork = settings.dataNetwork {
            guard StatusBarOverride.dataNetworks.contains(dataNetwork) else {
                throw OrbitSimError.invalidArgument("Unsupported data network type")
            }
            arguments += ["--dataNetwork", dataNetwork]
        }
        if let wifiMode = settings.wifiMode {
            guard StatusBarOverride.radioModes.contains(wifiMode) else {
                throw OrbitSimError.invalidArgument("Unsupported Wi-Fi mode")
            }
            arguments += ["--wifiMode", wifiMode]
        }
        if let wifiBars = settings.wifiBars {
            guard (0...3).contains(wifiBars) else {
                throw OrbitSimError.invalidArgument("Wi-Fi bars must be 0–3")
            }
            arguments += ["--wifiBars", String(wifiBars)]
        }
        if let cellularMode = settings.cellularMode {
            guard StatusBarOverride.cellularModes.contains(cellularMode) else {
                throw OrbitSimError.invalidArgument("Unsupported cellular mode")
            }
            arguments += ["--cellularMode", cellularMode]
        }
        if let cellularBars = settings.cellularBars {
            guard (0...4).contains(cellularBars) else {
                throw OrbitSimError.invalidArgument("Cellular bars must be 0–4")
            }
            arguments += ["--cellularBars", String(cellularBars)]
        }
        if let operatorName = settings.operatorName {
            guard operatorName.count <= 40 else {
                throw OrbitSimError.invalidArgument("Carrier name must be at most 40 characters")
            }
            arguments += ["--operatorName", operatorName]
        }
        if let batteryState = settings.batteryState {
            guard StatusBarOverride.batteryStates.contains(batteryState) else {
                throw OrbitSimError.invalidArgument("Unsupported battery state")
            }
            arguments += ["--batteryState", batteryState]
        }
        if let batteryLevel = settings.batteryLevel {
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

public struct StatusBarOverride: Sendable {
    public static let dataNetworks: Set<String> = ["hide", "wifi", "3g", "4g", "lte", "lte-a", "lte+", "5g", "5g+", "5g-uwb", "5g-uc"]
    public static let radioModes: Set<String> = ["searching", "failed", "active"]
    public static let cellularModes: Set<String> = ["notSupported", "searching", "failed", "active"]
    public static let batteryStates: Set<String> = ["charging", "charged", "discharging"]

    public let time: String?
    public let dataNetwork: String?
    public let wifiMode: String?
    public let wifiBars: Int?
    public let cellularMode: String?
    public let cellularBars: Int?
    public let operatorName: String?
    public let batteryState: String?
    public let batteryLevel: Int?

    public init(time: String? = nil, dataNetwork: String? = nil,
                wifiMode: String? = nil, wifiBars: Int? = nil,
                cellularMode: String? = nil, cellularBars: Int? = nil,
                operatorName: String? = nil, batteryState: String? = nil,
                batteryLevel: Int? = nil) {
        self.time = time
        self.dataNetwork = dataNetwork
        self.wifiMode = wifiMode
        self.wifiBars = wifiBars
        self.cellularMode = cellularMode
        self.cellularBars = cellularBars
        self.operatorName = operatorName
        self.batteryState = batteryState
        self.batteryLevel = batteryLevel
    }
}

public struct SimulatorWaypoint: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw OrbitSimError.invalidArgument("Waypoint latitude or longitude is out of range")
        }
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(_ text: String) throws {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let latitude = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let longitude = Double(parts[1].trimmingCharacters(in: .whitespaces)) else {
            throw OrbitSimError.invalidArgument("Waypoint must be latitude,longitude")
        }
        try self.init(latitude: latitude, longitude: longitude)
    }

    var simctlArgument: String {
        String(format: "%.8f,%.8f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }
}

public enum PrivacyAction: String, Sendable {
    case grant, revoke, reset
}

public enum SimulatorContentSize: String, CaseIterable, Sendable, Identifiable {
    case extraSmall = "extra-small"
    case small
    case medium
    case large
    case extraLarge = "extra-large"
    case extraExtraLarge = "extra-extra-large"
    case extraExtraExtraLarge = "extra-extra-extra-large"
    case accessibilityMedium = "accessibility-medium"
    case accessibilityLarge = "accessibility-large"
    case accessibilityExtraLarge = "accessibility-extra-large"
    case accessibilityExtraExtraLarge = "accessibility-extra-extra-large"
    case accessibilityExtraExtraExtraLarge = "accessibility-extra-extra-extra-large"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .extraSmall: "Extra Small"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        case .extraExtraLarge: "Extra Extra Large"
        case .extraExtraExtraLarge: "Extra Extra Extra Large"
        case .accessibilityMedium: "Accessibility Medium"
        case .accessibilityLarge: "Accessibility Large"
        case .accessibilityExtraLarge: "Accessibility Extra Large"
        case .accessibilityExtraExtraLarge: "Accessibility Extra Extra Large"
        case .accessibilityExtraExtraExtraLarge: "Accessibility Extra Extra Extra Large"
        }
    }
}

public enum ScreenshotFormat: String, Sendable {
    case png, jpeg, tiff, bmp

    var fileExtensions: Set<String> {
        switch self {
        case .jpeg: ["jpg", "jpeg"]
        case .tiff: ["tif", "tiff"]
        case .png: ["png"]
        case .bmp: ["bmp"]
        }
    }
}

public enum PrivacyService: String, CaseIterable, Sendable, Identifiable {
    case all, calendar, contacts, location, photos, microphone, motion, reminders, siri
    case contactsLimited = "contacts-limited"
    case locationAlways = "location-always"
    case photosAdd = "photos-add"
    case mediaLibrary = "media-library"

    public var id: String { rawValue }
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
