import Foundation

public enum TargetKind: String, Codable, Sendable {
    case simulator
    case physical
}

public enum TargetState: String, Codable, Sendable {
    case booted
    case shutdown
    case connected
    case unavailable
    case unknown
}

public struct DeviceTarget: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: TargetKind
    public let state: TargetState
    public let platform: String
    public let osVersion: String?
    public let runtimeIdentifier: String?

    public init(
        id: String,
        name: String,
        kind: TargetKind,
        state: TargetState,
        platform: String,
        osVersion: String? = nil,
        runtimeIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.state = state
        self.platform = platform
        self.osVersion = osVersion
        self.runtimeIdentifier = runtimeIdentifier
    }
}

public enum OrbitSimError: Error, LocalizedError, Sendable {
    case commandFailed(tool: String, code: Int32, detail: String)
    case commandTimedOut(tool: String)
    case invalidResponse(tool: String)
    case targetNotFound(String)
    case unsupportedAction(String)
    case destinationExists(String)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(tool, code, detail):
            return "\(tool) exited with status \(code): \(detail)"
        case let .commandTimedOut(tool):
            return "\(tool) timed out"
        case let .invalidResponse(tool):
            return "\(tool) returned an invalid response"
        case let .targetNotFound(id):
            return "No available target matches \(id)"
        case let .unsupportedAction(message):
            return message
        case let .destinationExists(path):
            return "Destination already exists: \(path)"
        case let .invalidArgument(message):
            return message
        }
    }
}
