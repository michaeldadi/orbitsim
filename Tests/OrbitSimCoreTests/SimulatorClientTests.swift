import Foundation
import XCTest
@testable import OrbitSimCore

final class SimulatorClientTests: XCTestCase {
    func testParsesDuoConnectedScreensWithoutTreatingExternalPortsAsIntegrated() {
        let enumeration = """
        Port:
            Class: DisplayAdapter
            Connected Screens:
            (1) LCD:
                Screen ID: 1
                Name: LCD
                Device Name: primary
                Screen Type: Integrated
                Pixel Size: {1398, 2034}
            (2) TVOut:
                Screen ID: 2
                Name: TVOut
                Device Name: external-0
                Screen Type: TVOut
                Pixel Size: {720, 480}
            (3) LCD-1:
                Screen ID: 3
                Name: LCD-1
                Device Name: primary-1
                Screen Type: Integrated
                Pixel Size: {2007, 2853}

        Port:
            Class: Accelerator
        """
        let screens = SimulatorDisplayParser.connectedScreens(in: enumeration)
        XCTAssertEqual(screens.count, 3)
        XCTAssertEqual(screens.filter(\.isIntegrated).map(\.id), ["1", "3"])
        XCTAssertEqual(screens.filter(\.isIntegrated).map(\.pixelWidth), [1398, 2007])
        XCTAssertEqual(SimulatorDisplayParser.connectedScreens(in: "Port:\n  unknown"), [])
    }

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

    func testInvalidStatusBarValuesFailBeforeCallingSimctl() async {
        let invalidSettings = [
            StatusBarOverride(dataNetwork: "6g"),
            StatusBarOverride(wifiBars: 4),
            StatusBarOverride(cellularBars: 5),
            StatusBarOverride(batteryState: "unknown"),
        ]
        for settings in invalidSettings {
            do {
                try await SimulatorClient().overrideStatusBar("unused", settings: settings)
                XCTFail("Expected an invalid status bar value to fail")
            } catch OrbitSimError.invalidArgument {
                // Expected; a simctl failure would indicate validation did not run first.
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
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
