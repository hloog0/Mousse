import AppKit
import ApplicationServices

/// Finds which app owns the window under a screen point. Scrolling goes to the window under
/// the cursor, which isn't always the frontmost app, so exclusions are checked against this.
@MainActor
enum AppUnderCursor {
    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        // We're inside an event tap: never wait long on a hung app.
        AXUIElementSetMessagingTimeout(element, 0.05)
        return element
    }()
    private static var bundleIDs: [pid_t: String] = [:]

    /// `point` is in global display coordinates (top-left origin), as in `CGEvent.location`.
    static func bundleID(at point: CGPoint) -> String? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        if let cached = bundleIDs[pid] { return cached }
        let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        bundleIDs[pid] = id
        return id
    }
}
