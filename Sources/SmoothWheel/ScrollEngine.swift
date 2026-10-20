import AppKit
import QuartzCore
import SmoothWheelCore

/// Drives the `Smoother` from the display's refresh and posts the resulting
/// trackpad-style scroll events. Idle (display link paused) whenever nothing is moving.
@MainActor
final class ScrollEngine: NSObject {
    private var smoother: Smoother
    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval?
    private var inGesture = false
    private var flags: CGEventFlags = []
    private let source = CGEventSource(stateID: .hidSystemState)
    /// Held while animating so App Nap can't delay our frames (a windowless app is a prime target).
    private var activity: NSObjectProtocol?

    init(duration: Double) {
        smoother = Smoother(duration: duration)
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    var isIdle: Bool { smoother.isIdle && !inGesture }

    var duration: Double {
        get { smoother.duration }
        set { smoother.duration = newValue }
    }

    /// Seconds to come to rest once the wheel stops; nil lets the glide play out in full.
    var stopTime: Double? {
        get { smoother.stopTime }
        set { smoother.stopTime = newValue }
    }

    /// Queue a notch's worth of movement, in pixels.
    func add(dx: Double, dy: Double, flags: CGEventFlags) {
        self.flags = flags
        smoother.add(dx: dx, dy: dy)
        startLink()
    }

    @objc private func tick(_ link: CADisplayLink) {
        // Real elapsed time, so the feel is the same at 60 Hz and 120 Hz (ProMotion).
        let dt = lastFrame.map { min(link.targetTimestamp - $0, 0.05) } ?? (link.targetTimestamp - link.timestamp)
        lastFrame = link.targetTimestamp

        let step = smoother.advance(by: dt)
        Log.write(String(format: "frame dt=%.2fms late=%.2fms dx=%d dy=%d",
                         dt * 1000, (CACurrentMediaTime() - link.timestamp) * 1000, step.dx, step.dy))
        if !step.isZero {
            post(dx: step.dx, dy: step.dy, phase: inGesture ? .changed : .began)
            inGesture = true
        }
        if smoother.isIdle {
            if inGesture { post(dx: 0, dy: 0, phase: .ended) }
            inGesture = false
            link.isPaused = true
            lastFrame = nil
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            activity = nil
        }
    }

    private func post(dx: Int, dy: Int, phase: CGScrollPhase) {
        WheelEvents.makeScroll(dx: Int32(dx), dy: Int32(dy), phase: phase, flags: flags, source: source)?
            .post(tap: .cgSessionEventTap)
    }

    private func startLink() {
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical], reason: "Animating a scroll"
            )
        }
        if link == nil {
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
            let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        link?.isPaused = false
    }

    /// A display link is bound to one screen; rebuild it when displays come and go.
    @objc private func screensChanged() {
        link?.invalidate()
        link = nil
        lastFrame = nil
        if !smoother.isIdle { startLink() }
    }
}
