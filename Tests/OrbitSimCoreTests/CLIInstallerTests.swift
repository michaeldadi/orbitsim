import Foundation
import XCTest
@testable import OrbitSimCore

final class CLIInstallerTests: XCTestCase {
    func testInstallsIdempotentLinkAndRefusesUnrelatedExistingFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbitsim-cli-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("OrbitSim.app")
        let contents = app.appendingPathComponent("Contents")
        let support = contents.appendingPathComponent("SharedSupport")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "io.github.michaeldadi.orbitsim.test",
                     "CFBundleName": "OrbitSim",
                     "CFBundlePackageType": "APPL",
                     "CFBundleShortVersionString": OrbitSimVersion.app]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let executable = support.appendingPathComponent("orbitsim")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let directory = root.appendingPathComponent("bin")
        let installer = CLIInstaller()
        let link = try installer.install(from: app, into: directory)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path),
                       executable.path)
        XCTAssertEqual(try installer.install(from: app, into: directory), link)

        let unrelated = root.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: unrelated.appendingPathComponent("orbitsim"))
        XCTAssertThrowsError(try installer.install(from: app, into: unrelated))
        XCTAssertEqual(try String(contentsOf: unrelated.appendingPathComponent("orbitsim"),
                                  encoding: .utf8), "keep")
    }
}
