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
            let records = try index.scan(derivedDataRoot: root)
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
        case "screenshot":
            let id = try required("--target", in: arguments)
            let output = try required("--output", in: arguments)
            let destination = URL(fileURLWithPath: output).standardizedFileURL
            try await registry.screenshot(id, to: destination, display: optional("--display", in: arguments))
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
            print(try await registry.simulators.displays(id))
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
            if arguments.contains("--clear") {
                try await registry.simulators.clearStatusBar(id)
            } else {
                let time = optional("--time", in: arguments)
                let batteryText = optional("--battery", in: arguments)
                guard batteryText == nil || Int(batteryText!) != nil else {
                    throw OrbitSimError.invalidArgument("--battery must be an integer from 0 to 100")
                }
                try await registry.simulators.overrideStatusBar(id, time: time,
                    batteryLevel: batteryText.flatMap(Int.init))
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
          orbitsim status [--json]
          orbitsim builds [--root <DerivedData-directory>] [--json]
          orbitsim screenshot --target <id> --output <file.png> [--display <id>]
          orbitsim record --target <simulator-id> --output <file.mp4|file.mov> --seconds <1-120> [--codec h264|hevc] [--display <id>]
          orbitsim install --target <id> --app <file.app>
          orbitsim launch --target <id> --bundle <bundle-id>
          orbitsim uninstall --target <id> --bundle <bundle-id>
          orbitsim terminate --target <simulator-id> --bundle <bundle-id>
          orbitsim open-url --target <id> --url <url>
          orbitsim add-media --target <simulator-id> --file <media-file>
          orbitsim push --target <simulator-id> --bundle <bundle-id> --payload <json-file>
          orbitsim privacy --target <simulator-id> --action grant|revoke|reset --service <service> --bundle <bundle-id>
          orbitsim displays --target <simulator-id>
          orbitsim boot|shutdown --target <simulator-id>
          orbitsim appearance --target <simulator-id> --style dark|light
          orbitsim location --target <id> --latitude <n> --longitude <n>
          orbitsim clear-location --target <id>
          orbitsim status-bar --target <simulator-id> --time <value> [--battery <0-100>]
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
