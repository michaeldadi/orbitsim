import Foundation
import XCTest
@testable import OrbitSimCore

final class BuildProductIndexTests: XCTestCase {
    func testKeepsProductsFromTwoProjectsDistinctAndRejectsChangedBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbitsim-products-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try makeProduct(root: root, project: "Alpha", name: "First",
                                    bundleID: "com.example.first", platform: "iPhoneSimulator")
        _ = try makeProduct(root: root, project: "Beta", name: "Second",
                            bundleID: "com.example.second", platform: "iPhoneSimulator")
        _ = try makeProduct(root: root, project: "Gamma", name: "DeviceOnly",
                            bundleID: "com.example.device", platform: "iPhoneOS")

        let index = BuildProductIndex()
        let products = try index.scan(derivedDataRoot: root, platform: .simulator)
        XCTAssertEqual(Set(products.map(\.bundleID)), ["com.example.first", "com.example.second"])
        XCTAssertEqual(Set(products.map(\.project)), ["Alpha", "Beta"])
        XCTAssertEqual(Set(products.map(\.id)).count, 2)

        let selected = try XCTUnwrap(products.first { $0.bundleID == "com.example.first" })
        try index.validate(selected)
        try writeInfo(to: first, name: "First", bundleID: "com.example.changed",
                      platform: "iPhoneSimulator")
        XCTAssertThrowsError(try index.validate(selected))
    }

    private func makeProduct(root: URL, project: String, name: String,
                             bundleID: String, platform: String) throws -> URL {
        let suffix = platform == "iPhoneSimulator" ? "iphonesimulator" : "iphoneos"
        let app = root.appendingPathComponent("\(project)/Build/Products/Debug-\(suffix)/\(name).app",
                                             isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try writeInfo(to: app, name: name, bundleID: bundleID, platform: platform)
        return app
    }

    private func writeInfo(to app: URL, name: String, bundleID: String, platform: String) throws {
        let plist: [String: Any] = [
            "CFBundlePackageType": "APPL",
            "CFBundleDisplayName": name,
            "CFBundleIdentifier": bundleID,
            "CFBundleSupportedPlatforms": [platform],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                       format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Info.plist"), options: .atomic)
    }
}
