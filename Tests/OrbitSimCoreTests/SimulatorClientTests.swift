import Foundation
import XCTest
@testable import OrbitSimCore

final class SimulatorClientTests: XCTestCase {
    func testRejectsExistingScreenshotWithoutOverwritingIt() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbitsim-test-\(UUID().uuidString).png")
        let original = Data([1, 2, 3])
        try original.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertThrowsError(try SimulatorClient.checkDestination(file, extension: "png"))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testInvalidLocationFailsBeforeCallingSimctl() async {
        do {
            try await SimulatorClient().setLocation("unused", latitude: 91, longitude: 0)
            XCTFail("Expected invalid coordinates to fail")
        } catch OrbitSimError.invalidArgument {
            // Expected; a failure from simctl would indicate validation did not run first.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInvalidPushPayloadFailsBeforeCallingSimctl() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbitsim-test-\(UUID().uuidString).json")
        try Data(#"{"message":"missing aps"}"#.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        do {
            try await SimulatorClient().sendPush("unused", bundleID: "com.example.App", payload: file)
            XCTFail("Expected invalid payload to fail")
        } catch OrbitSimError.invalidArgument {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCommandRunnerTimesOut() async {
        do {
            _ = try await CommandRunner().run(
                executable: "/bin/sleep", arguments: ["3"], timeoutSeconds: 0.1
            )
            XCTFail("Expected timeout")
        } catch OrbitSimError.commandTimedOut {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
