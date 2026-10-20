import AppKit
import QuartzCore
import SmoothWheelCore

/// Wires the event tap to the engine and owns the app's state.
@MainActor
@Observable
final class AppController {
    struct FrontApp: Equatable {
        var name: String
        var bundleID: String
    }

    let settings = Settings()
    let permissions = Permissions()
    let loginItem = LoginItem()
    /// The app the menu's "Disable in …" toggle applies to.
    private(set) var frontApp: FrontApp?

    @ObservationIgnored private let tap = ScrollTap()
    @ObservationIgnored private let engine = ScrollEngine(duration: 0.4)
    @ObservationIgnored private var acceleration = Acceleration()
    @ObservationIgnored private var gestureExcluded = false

    init() {
        tap.handler = { [unowned self] event in handle(event) }
        trackFrontApp()
        if !(permissions.trusted && tap.start()) {
            permissions.prompt()
            permissions.whenTrusted { [weak self] in
                let started = self?.tap.start() ?? false
                Log.write("accessibility granted, tap started=\(started)")
            }
        }
        Log.write("launch trusted=\(permissions.trusted) tap=\(tap.isRunning)")
    }

    /// Returns true when the event was taken over (and should be swallowed).
    private func handle(_ event: CGEvent) -> Bool {
        if Log.enabled { log(event) }
        guard settings.enabled,
              case let .smooth(dx, dy, flags) = WheelEvents.classify(event, shiftHorizontal: settings.shiftHorizontal)
        else { return false }

        // Look up the app under the pointer once per gesture, not on every notch.
        if engine.isIdle {
            gestureExcluded = !settings.excludedBundleIDs.isEmpty
                && settings.isExcluded(AppUnderCursor.bundleID(at: event.location))
        }
        if gestureExcluded { return false }

        acceleration.maximum = settings.accelerationMax
        let boost = acceleration.factor(at: CACurrentMediaTime(), direction: dy != 0 ? dy : 2 * dx)
        let step = settings.stepSize * boost
        engine.duration = settings.animationMs / 1000
        engine.stopTime = settings.stopTime
        engine.add(dx: Double(dx) * step, dy: Double(dy) * step, flags: flags)
        return true
    }

    private func trackFrontApp() {
        setFrontApp(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.setFrontApp(app) }
        }
    }

    private func setFrontApp(_ app: NSRunningApplication?) {
        // Opening our own settings window activates us; keep pointing at the user's app.
        guard let app, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
        frontApp = FrontApp(name: app.localizedName ?? id, bundleID: id)
    }

    private func log(_ e: CGEvent) {
        Log.write(String(
            format: "wheel lines=%lld,%lld fixed=%.3f,%.3f point=%lld,%lld continuous=%lld phase=%lld momentum=%lld ours=%d flags=0x%llx",
            e.getIntegerValueField(.scrollWheelEventDeltaAxis1), e.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
            e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
            e.getIntegerValueField(.scrollWheelEventIsContinuous),
            e.getIntegerValueField(.scrollWheelEventScrollPhase),
            e.getIntegerValueField(.scrollWheelEventMomentumPhase),
            e.getIntegerValueField(.eventSourceUserData) == WheelEvents.marker ? 1 : 0,
            e.flags.rawValue
        ))
    }
}
