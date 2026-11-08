import Foundation

/// A screen reported by `simctl io <device> enumerate` while attached to a Simulator.
public struct SimulatorDisplay: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let deviceName: String
    public let kind: String
    public let pixelWidth: Int
    public let pixelHeight: Int

    public var isIntegrated: Bool { kind == "Integrated" }
}

/// `simctl io enumerate` has no JSON output in Xcode 27.2. Parse only its
/// connected-screen block; reject an unrecognized format instead of guessing.
public enum SimulatorDisplayParser {
    public static func connectedScreens(in output: String) -> [SimulatorDisplay] {
        struct Partial {
            var id: String?
            var name: String?
            var deviceName: String?
            var kind: String?
            var width: Int?
            var height: Int?

            var display: SimulatorDisplay? {
                guard let id, let name, let deviceName, let kind,
                      let width, let height else { return nil }
                return SimulatorDisplay(id: id, name: name, deviceName: deviceName,
                                        kind: kind, pixelWidth: width, pixelHeight: height)
            }
        }

        var screens: [SimulatorDisplay] = []
        var current = Partial()
        var inConnectedScreens = false

        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text == "Connected Screens:" {
                inConnectedScreens = true
                continue
            }
            guard inConnectedScreens else { continue }
            if !line.first!.isWhitespace {
                if let display = current.display { screens.append(display) }
                break
            }

            let field = text.split(separator: ":", maxSplits: 1).map(String.init)
            guard field.count == 2 else { continue }
            let value = field[1].trimmingCharacters(in: .whitespaces)
            switch field[0] {
            case "Screen ID":
                if let display = current.display { screens.append(display) }
                current = Partial(id: value)
            case "Name": current.name = value
            case "Device Name": current.deviceName = value
            case "Screen Type": current.kind = value
            case "Pixel Size":
                let dimensions = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                if dimensions.count == 2 {
                    current.width = dimensions[0]
                    current.height = dimensions[1]
                }
            default: break
            }
        }
        if let display = current.display, !screens.contains(where: { $0.id == display.id }) {
            screens.append(display)
        }
        return screens
    }
}
