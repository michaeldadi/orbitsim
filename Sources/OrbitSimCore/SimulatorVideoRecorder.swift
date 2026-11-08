import Darwin
import Foundation

public struct SimulatorVideoRecorder: Sendable {
    public enum Codec: String, Sendable {
        case h264, hevc
    }

    public init() {}

    /// Records for a bounded time and sends SIGINT so simctl finalizes the movie.
    public func record(
        targetID: String,
        to destination: URL,
        durationSeconds: Int,
        codec: Codec = .h264,
        display: String? = nil
    ) async throws {
        guard destination.isFileURL,
              ["mp4", "mov"].contains(destination.pathExtension.lowercased()) else {
            throw OrbitSimError.invalidArgument("Recording output must be a local .mp4 or .mov file")
        }
        guard (1...120).contains(durationSeconds) else {
            throw OrbitSimError.invalidArgument("Recording duration must be 1–120 seconds")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw OrbitSimError.destinationExists(destination.path)
        }
        guard display == nil || !(display?.isEmpty ?? true) else {
            throw OrbitSimError.invalidArgument("Display identifier cannot be empty")
        }

        try await Task.detached(priority: .userInitiated) {
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("orbitsim-record-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: temporary.path, contents: nil,
                                           attributes: [.posixPermissions: 0o600])
            defer { try? FileManager.default.removeItem(at: temporary) }
            let log = try FileHandle(forWritingTo: temporary)
            defer { try? log.close() }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            var arguments = ["simctl", "io", targetID, "recordVideo", "--codec=\(codec.rawValue)"]
            if let display { arguments.append("--display=\(display)") }
            arguments.append(destination.path)
            process.arguments = arguments
            process.standardOutput = log
            process.standardError = log
            try process.run()

            // A recording can fail before the first frame. Stop waiting in that case.
            for _ in 0..<(durationSeconds * 10) {
                if !process.isRunning || Task.isCancelled { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGINT) }

            let watchdog = Task.detached {
                try? await Task.sleep(for: .seconds(10))
                if !Task.isCancelled && process.isRunning {
                    process.terminate()
                    try? await Task.sleep(for: .seconds(2))
                    if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
                }
            }
            process.waitUntilExit()
            watchdog.cancel()

            let detail = ((try? String(contentsOf: temporary, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else {
                throw OrbitSimError.commandFailed(tool: "simctl recordVideo", code: process.terminationStatus,
                                                  detail: String(detail.prefix(2_000)))
            }
            guard let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
                throw OrbitSimError.invalidResponse(tool: "simctl recordVideo")
            }
        }.value
    }
}
