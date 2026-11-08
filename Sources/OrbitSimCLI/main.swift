import Foundation
import OrbitSimCore

@main
struct OrbitSimCommand {
    static func main() async {
        do {
            try await execute(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("orbitsim: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func execute(_ arguments: [String]) async throws {
        let registry = TargetRegistry()
        guard let command = arguments.first else {
            printUsage()
            return
        }
        switch command {
        case "help", "--help", "-h":
            printUsage()
        case "version", "--version":
            print("orbitsim 0.1.0-dev")
        case "status":
            let targets = try await registry.allTargets()
            let report = StatusReport(
                protocolVersion: 1,
                appVersion: "0.1.0-dev",
                macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                targetCount: targets.count,
                activeTargetIDs: targets.filter { $0.state == .booted || $0.state == .connected }.map(\.id)
            )
            if arguments.contains("--json") {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(report), as: UTF8.self))
            } else {
                print("OrbitSim \(report.appVersion) • \(report.macOS) • \(report.targetCount) targets (\(report.activeTargetIDs.count) active)")
            }
        case "builds":
            let root = optional("--root", in: arguments).map { URL(fileURLWithPath: $0).standardizedFileURL }
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Developer/Xcode/DerivedData")
            let index = BuildLogIndex()
            let scanned = try index.scan(derivedDataRoot: root)
            let records: [BuildRecord]
            if arguments.contains("--history") {
                let file = optional("--history-file", in: arguments).map {
                    URL(fileURLWithPath: $0).standardizedFileURL
                } ?? BuildHistoryStore.defaultFileURL
                let store = BuildHistoryStore(fileURL: file)
                try store.upsert(scanned)
                records = try store.records(limit: 500)
            } else {
                records = scanned
            }
            let report = BuildReport(records: records, statistics: index.statistics(for: records))
            if arguments.contains("--json") {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(report), as: UTF8.self))
            } else {
                print("\(records.count) builds • p75 \(report.statistics.p75Seconds.map { String(format: "%.1fs", $0) } ?? "n/a") • p95 \(report.statistics.p95Seconds.map { String(format: "%.1fs", $0) } ?? "n/a")")
                for record in records.prefix(20) {
                    print("\(record.scheme)\t\(String(format: "%.1fs", record.durationSeconds))\t\(record.statusCode)\t\(record.project)")
                }
            }
        case "targets":
            let targets = try await registry.allTargets()
            if arguments.contains("--json") {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(targets), as: UTF8.self))
            } else {
                for target in targets {
                    print("\(target.kind.rawValue)\t\(target.state.rawValue)\t\(target.name)\t\(target.id)")
                }
            }
        case "elements":
            let id = try required("--target", in: arguments)
            let elements = try await AccessibilityClient().elements(
                targetID: id, includeText: arguments.contains("--include-text")
            )
            if arguments.contains("--json") {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(elements), as: UTF8.self))
            } else {
                for element in elements {
                    print("\(element.identifier)\t\(element.role)\t\(element.text ?? "")")
                }
            }
        case "interact":
            let id = try required("--target", in: arguments)
            let identifier = try required("--element", in: arguments)
            let action = try required("--action", in: arguments)
            switch action {
            case "press":
                try await AccessibilityClient().press(targetID: id, identifier: identifier)
            case "type":
                try await AccessibilityClient().typeText(
                    targetID: id, identifier: identifier, text: required("--text", in: arguments)
                )
            default:
                throw OrbitSimError.invalidArgument("--action must be press or type")
            }
        case "wait":
            let id = try required("--target", in: arguments)
            let identifier = try required("--element", in: arguments)
            let seconds = Double(try required("--seconds", in: arguments)) ?? 0
            try await AccessibilityClient().wait(targetID: id, identifier: identifier,
                                                 timeoutSeconds: seconds)
        case "screenshot":
            let id = try required("--target", in: arguments)
            let output = try required("--output", in: arguments)
            let destination = URL(fileURLWithPath: output).standardizedFileURL
            let type = optional("--type", in: arguments) ?? "png"
            guard let format = ScreenshotFormat(rawValue: type) else {
                throw OrbitSimError.invalidArgument("--type must be png, jpeg, tiff, or bmp")
            }
            try await registry.screenshot(id, to: destination,
                                          display: optional("--display", in: arguments), format: format)
            print(destination.path)
        case "record":
            let id = try required("--target", in: arguments)
            try await requireSimulator(id, registry: registry)
            let output = try required("--output", in: arguments)
            let secondsText = try required("--seconds", in: arguments)
            guard let seconds = Int(secondsText) else {
                throw OrbitSimError.invalidArgument("--seconds must be an integer")
            }
            let codecText = optional("--codec", in: arguments) ?? "h264"
            guard let codec = SimulatorVideoRecorder.Codec(rawValue: codecText) else {
                throw OrbitSimError.invalidArgument("--codec must be h264 or hevc")
            }
            let destination = URL(fileURLWithPath: output).standardizedFileURL
            try await SimulatorVideoRecorder().record(targetID: id, to: destination,
                                                      durationSeconds: seconds, codec: codec,
                                                      display: optional("--display", in: arguments))
            print(destination.path)
        case "gif":
            let id = try required("--target", in: arguments)
            try await requireSimulator(id, registry: registry)
            let output = try required("--output", in: arguments)
            let secondsText = try required("--seconds", in: arguments)
            let fpsText = optional("--fps", in: arguments) ?? "10"
            guard let seconds = Int(secondsText), let fps = Int(fpsText) else {
                throw OrbitSimError.invalidArgument("--seconds and --fps must be integers")
            }
            let destination = URL(fileURLWithPath: output).standardizedFileURL
            try await SimulatorGIFRecorder().record(targetID: id, to: destination,
                                                     durationSeconds: seconds, framesPerSecond: fps,
                                                     display: optional("--display", in: arguments))
            print(destination.path)
        case "install":
            let id = try required("--target", in: arguments)
            let app = URL(fileURLWithPath: try required("--app", in: arguments)).standardizedFileURL
            try await registry.install(id, app: app)
        case "launch":
            let id = try required("--target", in: arguments)
            try await registry.launch(id, bundleID: required("--bundle", in: arguments))
        case "uninstall":
            let id = try required("--target", in: arguments)
            try await registry.uninstall(id, bundleID: required("--bundle", in: arguments))
        case "terminate":
            let id = try required("--target", in: arguments)
            try await requireSimulator(id, registry: registry)
            try await registry.simulators.terminate(id, bundleID: required("--bundle", in: arguments))
        case "add-media":
            let id = try required("--target", in: arguments)
            try await requireSimulator(id, registry: registry)
            let file = URL(fileURLWithPath: try required("--file", in: arguments)).standardizedFileURL
            try await registry.simulators.addMedia(id, file: file)
        case "push":
            let id = try required("--target", in: arguments)
            try await requireSimulator(id, registry: registry)
            let file = URL(fileURLWithPath: try required("--payload", in: arguments)).standardizedFileURL
            try await registry.simulators.sendPush(id, bundleID: required("--bundle", in: arguments), payload: file)
        case "privacy":
            let id = try required("--target", in: arguments)
            try await requireSimulator(id, registry: registry)
            let actionText = try required("--action", in: arguments)
            let serviceText = try required("--service", in: arguments)
            guard let action = PrivacyAction(rawValue: actionText),
                  let service = PrivacyService(rawValue: serviceText) else {
                throw OrbitSimError.invalidArgument("Use a supported privacy action and service")
            }
            try await registry.simulators.setPrivacy(id, action: action, service: service,
                                                     bundleID: required("--bundle", in: arguments))
        case "displays":
            let id = try required("--target", in: arguments)
            try await requireSimulator(id, registry: registry)
            if arguments.contains("--json") {
                let screens = try await registry.simulators.connectedDisplays(id)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(screens), as: UTF8.self))
            } else {
                print(try await registry.simulators.displays(id))
            }
        case "open-url":
            let id = try required("--target", in: arguments)
            let text = try required("--url", in: arguments)
            guard let url = URL(string: text), url.scheme != nil else {
                throw OrbitSimError.invalidArgument("--url must be an absolute URL")
            }
            try await registry.openURL(id, url: url)
        case "boot":
            let id = try required("--target", in: arguments)
            let target = try await registry.resolve(id)
            guard target.kind == .simulator else {
                throw OrbitSimError.unsupportedAction("Boot is available only for Simulators")
            }
            try await registry.simulators.boot(id)
        case "shutdown":
            let id = try required("--target", in: arguments)
            let target = try await registry.resolve(id)
            guard target.kind == .simulator else {
                throw OrbitSimError.unsupportedAction("Shutdown is available only for Simulators")
            }
            try await registry.simulators.shutdown(id)
        case "appearance":
            let id = try required("--target", in: arguments)
            let style = try required("--style", in: arguments)
            guard style == "dark" || style == "light" else {
                throw OrbitSimError.invalidArgument("--style must be dark or light")
            }
            let target = try await registry.resolve(id)
            guard target.kind == .simulator else {
                throw OrbitSimError.unsupportedAction("Appearance control is available only for Simulators")
            }
            try await registry.simulators.setAppearance(id, dark: style == "dark")
        case "contrast":
            let id = try required("--target", in: arguments)
            try await requireSimulator(id, registry: registry)
            if let state = optional("--state", in: arguments) {
                guard state == "enabled" || state == "disabled" else {
                    throw OrbitSimError.invalidArgument("--state must be enabled or disabled")
                }
                try await registry.simulators.setIncreaseContrast(id, enabled: state == "enabled")
            }
            print(try await registry.simulators.increaseContrast(id) ? "enabled" : "disabled")
        case "text-size":
            let id = try required("--target", in: arguments)
            try await requireSimulator(id, registry: registry)
            if let value = optional("--size", in: arguments) {
                guard let size = SimulatorContentSize(rawValue: value) else {
                    throw OrbitSimError.invalidArgument("Unsupported --size; see orbitsim help")
                }
                try await registry.simulators.setContentSize(id, size: size)
            }
            print(try await registry.simulators.contentSize(id).rawValue)
        case "location":
            let id = try required("--target", in: arguments)
            let latitudeText = try required("--latitude", in: arguments)
            let longitudeText = try required("--longitude", in: arguments)
            guard let latitude = Double(latitudeText), let longitude = Double(longitudeText) else {
                throw OrbitSimError.invalidArgument("Latitude and longitude must be numbers")
            }
            try await registry.setLocation(id, latitude: latitude, longitude: longitude)
        case "clear-location":
            let id = try required("--target", in: arguments)
            try await registry.clearLocation(id)
        case "status-bar":
            let id = try required("--target", in: arguments)
            try await requireSimulator(id, registry: registry)
            if arguments.contains("--list") {
                print(try await registry.simulators.statusBarOverrides(id))
            } else if arguments.contains("--clear") {
                try await registry.simulators.clearStatusBar(id)
            } else {
                let settings = try StatusBarOverride(
                    time: optional("--time", in: arguments),
                    dataNetwork: optional("--network", in: arguments),
                    wifiMode: optional("--wifi-mode", in: arguments),
                    wifiBars: integer("--wifi-bars", in: arguments),
                    cellularMode: optional("--cellular-mode", in: arguments),
                    cellularBars: integer("--cellular-bars", in: arguments),
                    operatorName: optional("--carrier", in: arguments),
                    batteryState: optional("--battery-state", in: arguments),
                    batteryLevel: integer("--battery", in: arguments)
                )
                try await registry.simulators.overrideStatusBar(id, settings: settings)
            }
        case "doctor":
            let targets = try await registry.allTargets()
            print("Simulator and device tools available. \(targets.count) targets discovered.")
            let booted = targets.filter { $0.kind == .simulator && $0.state == .booted }
            if booted.isEmpty {
                print("No booted Simulator; boot a specific target before capture or app actions.")
            } else if booted.count > 1 {
                print("\(booted.count) Simulators are booted; pass --target with the intended ID.")
            }
            if !targets.contains(where: { $0.kind == .physical && $0.state == .connected }) {
                print("No connected physical device; USB pairing is required for physical-device actions.")
            }
        default:
            throw OrbitSimError.invalidArgument("Unknown command: \(command). Run orbitsim help.")
        }
    }

    private static func required(_ flag: String, in arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1),
              !arguments[index + 1].hasPrefix("--") else {
            throw OrbitSimError.invalidArgument("Missing \(flag)")
        }
        return arguments[index + 1]
    }

    private static func optional(_ flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1),
              !arguments[index + 1].hasPrefix("--") else { return nil }
        return arguments[index + 1]
    }

    private static func integer(_ flag: String, in arguments: [String]) throws -> Int? {
        guard let value = optional(flag, in: arguments) else { return nil }
        guard let number = Int(value) else {
            throw OrbitSimError.invalidArgument("\(flag) must be an integer")
        }
        return number
    }

    private static func requireSimulator(_ id: String, registry: TargetRegistry) async throws {
        guard try await registry.resolve(id).kind == .simulator else {
            throw OrbitSimError.unsupportedAction("This action is available only for Simulators")
        }
    }

    private static func printUsage() {
        print("""
        OrbitSim developer tools

        Usage:
          orbitsim targets [--json]
          orbitsim elements --target <simulator-id> [--json] [--include-text]
          orbitsim interact --target <simulator-id> --element <accessibility-id> --action press|type [--text <value>]
          orbitsim wait --target <simulator-id> --element <accessibility-id> --seconds <0.1-60>
          orbitsim status [--json]
          orbitsim builds [--root <DerivedData-directory>] [--history] [--history-file <sqlite-file>] [--json]
          orbitsim screenshot --target <id> --output <file> [--type png|jpeg|tiff|bmp] [--display <id>]
          orbitsim record --target <simulator-id> --output <file.mp4|file.mov> --seconds <1-120> [--codec h264|hevc] [--display <id>]
          orbitsim gif --target <simulator-id> --output <file.gif> --seconds <1-30> [--fps <1-10>] [--display <id>]
          orbitsim install --target <id> --app <file.app>
          orbitsim launch --target <id> --bundle <bundle-id>
          orbitsim uninstall --target <id> --bundle <bundle-id>
          orbitsim terminate --target <simulator-id> --bundle <bundle-id>
          orbitsim open-url --target <id> --url <url>
          orbitsim add-media --target <simulator-id> --file <media-file>
          orbitsim push --target <simulator-id> --bundle <bundle-id> --payload <json-file>
          orbitsim privacy --target <simulator-id> --action grant|revoke|reset --service <service> --bundle <bundle-id>
          orbitsim displays --target <simulator-id> [--json]
          orbitsim boot|shutdown --target <simulator-id>
          orbitsim appearance --target <simulator-id> --style dark|light
          orbitsim contrast --target <simulator-id> [--state enabled|disabled]
          orbitsim text-size --target <simulator-id> [--size extra-small|small|medium|large|extra-large|extra-extra-large|extra-extra-extra-large|accessibility-medium|accessibility-large|accessibility-extra-large|accessibility-extra-extra-large|accessibility-extra-extra-extra-large]
          orbitsim location --target <id> --latitude <n> --longitude <n>
          orbitsim clear-location --target <id>
          orbitsim status-bar --target <simulator-id> [--time <value>] [--network hide|wifi|3g|4g|lte|lte-a|lte+|5g|5g+|5g-uwb|5g-uc] [--wifi-mode searching|failed|active] [--wifi-bars <0-3>] [--cellular-mode notSupported|searching|failed|active] [--cellular-bars <0-4>] [--carrier <name>] [--battery-state charging|charged|discharging] [--battery <0-100>]
          orbitsim status-bar --target <simulator-id> --list
          orbitsim status-bar --target <simulator-id> --clear
          orbitsim doctor
          orbitsim version

        Mutating actions always require an explicit target ID.
        """)
    }
}

private struct StatusReport: Encodable {
    let protocolVersion: Int
    let appVersion: String
    let macOS: String
    let targetCount: Int
    let activeTargetIDs: [String]
}

private struct BuildReport: Encodable {
    let records: [BuildRecord]
    let statistics: BuildStatistics
}
