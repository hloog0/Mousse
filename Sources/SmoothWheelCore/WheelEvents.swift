import CoreGraphics

/// Classifies incoming scroll-wheel events and builds the smooth replacements we post.
public enum WheelEvents {
    /// Stamped into `eventSourceUserData` on everything we post, so our own tap lets it through.
    public static let marker: Int64 = 0x534D_5748 // "SMWH"

    public enum Decision: Equatable, Sendable {
        /// Leave the event alone (trackpad, Magic Mouse, our own output, or nothing to scroll).
        case pass
        /// Swallow it: it's one wheel notch, in this direction (−1, 0 or 1) per axis.
        case smooth(dx: Int, dy: Int, flags: CGEventFlags)
    }

    public static func classify(_ event: CGEvent, shiftHorizontal: Bool) -> Decision {
        if event.getIntegerValueField(.eventSourceUserData) == marker { return .pass }
        // Trackpads and Magic Mouse report gesture phases; a wheel never does. The "continuous"
        // flag can't be trusted: Logi Options+ re-sends M750 notches as phaseless continuous events.
        if event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
            || event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return .pass }

        var dy = direction(event, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventDeltaAxis1)
        var dx = direction(event, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventDeltaAxis2)
        var flags = event.flags
        if shiftHorizontal, flags.contains(.maskShift), dx == 0, dy != 0 {
            // We do the conversion ourselves, so drop Shift to stop apps converting it again.
            dx = dy
            dy = 0
            flags.remove(.maskShift)
        }
        guard dx != 0 || dy != 0 else { return .pass }
        return .smooth(dx: dx, dy: dy, flags: flags)
    }

    /// Each event is one notch. macOS (or the mouse driver) scales its size with spin speed,
    /// but we apply our own step and acceleration, so only the sign matters.
    private static func direction(_ event: CGEvent, _ point: CGEventField, _ fixed: CGEventField, _ lines: CGEventField) -> Int {
        var value = Double(event.getIntegerValueField(point))
        if value == 0 { value = event.getDoubleValueField(fixed) }
        if value == 0 { value = Double(event.getIntegerValueField(lines)) }
        return value > 0 ? 1 : value < 0 ? -1 : 0
    }

    /// A trackpad-style continuous scroll of whole pixels, tagged with `marker`.
    public static func makeScroll(
        dx: Int32, dy: Int32, phase: CGScrollPhase, flags: CGEventFlags, source: CGEventSource?
    ) -> CGEvent? {
        guard let event = CGEvent(
            scrollWheelEvent2Source: source, units: .pixel,
            wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0
        ) else { return nil }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.flags = flags
        return event
    }
}
