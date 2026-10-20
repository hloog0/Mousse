import CoreGraphics
import Foundation

/// A session-level event tap on scroll-wheel events. Runs on the main run loop, so the
/// handler is always called on the main thread.
@MainActor
final class ScrollTap {
    /// Return true to swallow the event.
    var handler: (CGEvent) -> Bool = { _ in false }

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Fails (returns false) until the app has Accessibility permission.
    @discardableResult
    func start() -> Bool {
        if port != nil { return true }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventType.scrollWheel.rawValue,
            callback: scrollTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a tap off if a callback is ever too slow; turn it straight back on.
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        case .scrollWheel:
            return handler(event) ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

private func scrollTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<ScrollTap>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated { tap.handle(type: type, event: event) }
}
