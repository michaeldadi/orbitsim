import Foundation

public struct CommandResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

/// Runs a tool without a shell, so target names and URLs remain literal arguments.
public struct CommandRunner: Sendable {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: Double = 30
    ) async throws -> CommandResult {
        try await Task.detached(priority: .userInitiated) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("orbitsim-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let stdoutURL = directory.appendingPathComponent("stdout")
            let stderrURL = directory.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            let stderrHandle = try FileHandle(forWritingTo: stderrURL)
            defer {
                try? stdoutHandle.close()
                try? stderrHandle.close()
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle

            let watchdog = ProcessWatchdog(process: process)
            try process.run()
            let timer = Task.detached {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                if !Task.isCancelled { watchdog.terminate() }
            }
            process.waitUntilExit()
            timer.cancel()

            let output = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
            let errors = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
            if watchdog.didTimeOut {
                throw OrbitSimError.commandTimedOut(tool: arguments.first ?? executable)
            }
            return CommandResult(stdout: output, stderr: errors, exitCode: process.terminationStatus)
        }.value
    }
}

private final class ProcessWatchdog: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var timedOut = false

    init(process: Process) { self.process = process }

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        guard process.isRunning else { return }
        timedOut = true
        process.terminate()
    }
}
