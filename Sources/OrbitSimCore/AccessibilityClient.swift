import AppKit
import ApplicationServices
import Foundation

public struct SimulatorElement: Codable, Sendable {
    public let identifier: String
    public let role: String
    public let text: String?
    public let frame: SimulatorElementFrame?

    public init(identifier: String, role: String, text: String?, frame: SimulatorElementFrame?) {
        self.identifier = identifier
        self.role = role
        self.text = text
        self.frame = frame
    }
}

/// Screen coordinates in points, as reported by the macOS Accessibility bridge.
public struct SimulatorElementFrame: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

/// Reads the accessibility bridge exposed by a visible Device Hub window.
/// This path requires the caller's macOS Accessibility grant and cannot
/// operate on headless Simulators or distinguish duplicate booted names.
@MainActor
public struct AccessibilityClient {
    private let simulators: SimulatorClient

    public init(simulators: SimulatorClient = SimulatorClient()) {
        self.simulators = simulators
    }

    public func elements(targetID: String, includeText: Bool = false) async throws -> [SimulatorElement] {
        let root = try await targetWindow(targetID)
        var result: [SimulatorElement] = []
        visit(root) { element in
            guard let identifier = stringAttribute(element, kAXIdentifierAttribute as String),
                  !identifier.isEmpty else { return }
            let role = stringAttribute(element, kAXRoleAttribute as String) ?? "unknown"
            let text = includeText
                ? (stringAttribute(element, kAXDescriptionAttribute as String)
                    ?? stringAttribute(element, kAXValueAttribute as String))
                : nil
            if !result.contains(where: { $0.identifier == identifier && $0.role == role && $0.text == text }) {
                result.append(SimulatorElement(identifier: identifier, role: role,
                                               text: text, frame: frame(of: element)))
            }
        }
        return result.sorted { $0.identifier < $1.identifier }
    }

    public func press(targetID: String, identifier: String) async throws {
        let match = try await uniqueElement(targetID: targetID, identifier: identifier)
        let status = AXUIElementPerformAction(match, kAXPressAction as CFString)
        guard status == .success else {
            throw OrbitSimError.unsupportedAction("Could not press \(identifier) (Accessibility status \(status.rawValue))")
        }
    }

    public func typeText(targetID: String, identifier: String, text: String) async throws {
        guard text.utf8.count <= 4_096 else {
            throw OrbitSimError.invalidArgument("Text must be at most 4096 UTF-8 bytes")
        }
        let match = try await uniqueElement(targetID: targetID, identifier: identifier)
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(match, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            throw OrbitSimError.unsupportedAction("Element \(identifier) is not an editable field")
        }
        let status = AXUIElementSetAttributeValue(match, kAXValueAttribute as CFString, text as CFTypeRef)
        // Device Hub's iOS bridge can report cannotComplete after the field
        // actually commits the value. Read back the value before deciding.
        for _ in 0..<10 {
            if stringAttribute(match, kAXValueAttribute as String) == text { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw OrbitSimError.unsupportedAction(
            "Could not verify text in \(identifier) (Accessibility status \(status.rawValue))"
        )
    }

    public func wait(targetID: String, identifier: String, timeoutSeconds: Double) async throws {
        guard !identifier.isEmpty, (0.1...60).contains(timeoutSeconds) else {
            throw OrbitSimError.invalidArgument("Wait requires an identifier and 0.1–60 seconds")
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSeconds))
        while ContinuousClock.now < deadline {
            let visible = try await elements(targetID: targetID)
            if visible.contains(where: { $0.identifier == identifier }) { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw OrbitSimError.commandTimedOut(tool: "accessibility wait")
    }

    private func targetWindow(_ targetID: String) async throws -> AXUIElement {
        guard AXIsProcessTrusted() else {
            throw OrbitSimError.unsupportedAction(
                "Enable Accessibility for OrbitSim or orbitsim in System Settings → Privacy & Security → Accessibility"
            )
        }
        let targets = try await simulators.targets()
        guard let target = targets.first(where: { $0.id == targetID && $0.state == .booted }) else {
            throw OrbitSimError.targetNotFound(targetID)
        }
        guard targets.filter({ $0.state == .booted && $0.name == target.name }).count == 1 else {
            throw OrbitSimError.unsupportedAction(
                "Multiple booted Simulators share this name; the visible window cannot be mapped to a unique target"
            )
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dt.Devices"
        }) else {
            throw OrbitSimError.unsupportedAction("Open the selected Simulator in Device Hub first")
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let rawWindow = attribute(application, kAXMainWindowAttribute as String) else {
            throw OrbitSimError.unsupportedAction("Device Hub has no main Simulator window")
        }
        let window = rawWindow as! AXUIElement
        let title = stringAttribute(window, kAXTitleAttribute as String) ?? ""
        guard title == target.name || title.hasPrefix("\(target.name) – ") else {
            throw OrbitSimError.unsupportedAction(
                "Device Hub's main window is \(title); select the \(target.name) window first"
            )
        }
        var selectedRows: [[String]] = []
        visit(window) { element in
            guard stringAttribute(element, kAXRoleAttribute as String) == (kAXRowRole as String),
                  (attribute(element, kAXSelectedAttribute as String) as? Bool) == true else { return }
            selectedRows.append(descendantText(element, depth: 0))
        }
        guard selectedRows.count == 1,
              selectedRows[0].contains(target.name),
              selectedRows[0].contains("Simulator") else {
            throw OrbitSimError.unsupportedAction(
                "Device Hub must have the matching Simulator row selected before accessibility actions"
            )
        }
        return window
    }

    private func uniqueElement(targetID: String, identifier: String) async throws -> AXUIElement {
        guard !identifier.isEmpty else {
            throw OrbitSimError.invalidArgument("An accessibility identifier is required")
        }
        let root = try await targetWindow(targetID)
        var matches: [AXUIElement] = []
        visit(root) { element in
            guard stringAttribute(element, kAXIdentifierAttribute as String) == identifier else { return }
            if !matches.contains(where: { CFEqual($0, element) }) { matches.append(element) }
        }
        guard matches.count == 1, let match = matches.first else {
            throw OrbitSimError.unsupportedAction(matches.isEmpty
                ? "No visible element has identifier \(identifier)"
                : "Multiple visible elements have identifier \(identifier)")
        }
        return match
    }

    private func descendantText(_ element: AXUIElement, depth: Int) -> [String] {
        guard depth < 6 else { return [] }
        var result: [String] = []
        for key in [kAXDescriptionAttribute as String, kAXValueAttribute as String] {
            if let value = stringAttribute(element, key), !value.isEmpty { result.append(value) }
        }
        if let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] {
            for child in children { result += descendantText(child, depth: depth + 1) }
        }
        return result
    }

    private func visit(_ root: AXUIElement, body: (AXUIElement) -> Void) {
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        var visited: [CFHashCode: [AXUIElement]] = [:]
        var visitedCount = 0
        while let (element, depth) = stack.popLast(), visitedCount < 2_000 {
            let hash = CFHash(element)
            guard depth <= 24,
                  !(visited[hash]?.contains(where: { CFEqual($0, element) }) ?? false) else { continue }
            visited[hash, default: []].append(element)
            visitedCount += 1
            body(element)
            if let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] {
                for child in children.prefix(100).reversed() {
                    stack.append((child, depth + 1))
                }
            }
        }
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func stringAttribute(_ element: AXUIElement, _ key: String) -> String? {
        attribute(element, key) as? String
    }

    private func frame(of element: AXUIElement) -> SimulatorElementFrame? {
        guard let rawPosition = attribute(element, kAXPositionAttribute as String),
              let rawSize = attribute(element, kAXSizeAttribute as String),
              CFGetTypeID(rawPosition as CFTypeRef) == AXValueGetTypeID(),
              CFGetTypeID(rawSize as CFTypeRef) == AXValueGetTypeID() else {
            return nil
        }
        let position = rawPosition as! AXValue
        let size = rawSize as! AXValue
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(size, .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else {
            return nil
        }
        return SimulatorElementFrame(x: origin.x, y: origin.y,
                                     width: dimensions.width, height: dimensions.height)
    }
}
