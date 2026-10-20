import CoreGraphics
import Testing
@testable import MousseCore

struct WheelEventsTests {
    /// What a plain notched wheel produces: line units, not continuous.
    private func wheelNotch(dy: Int32, dx: Int32 = 0, flags: CGEventFlags = []) -> CGEvent {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)!
        e.flags = flags
        return e
    }

    /// A continuous pixel scroll with the given gesture phases (0 = none).
    private func pixelScroll(dy: Int32, phase: Int64 = 0, momentum: Int64 = 0) -> CGEvent {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)!
        e.flags = [] // new events can inherit system flag bits (e.g. non-coalesced); keep the test exact
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        return e
    }

    @Test func eachWheelEventIsOneNotch() {
        #expect(WheelEvents.classify(wheelNotch(dy: -1), shiftHorizontal: true) == .smooth(dx: 0, dy: -1, flags: []))
        // macOS scales fast spins up to many lines; it's still one notch to us.
        #expect(WheelEvents.classify(wheelNotch(dy: 18), shiftHorizontal: true) == .smooth(dx: 0, dy: 1, flags: []))
        #expect(WheelEvents.classify(wheelNotch(dy: 0, dx: -2), shiftHorizontal: true) == .smooth(dx: -1, dy: 0, flags: []))
    }

    /// What the M750 actually sends with Logi Options+ running (seen in the log).
    @Test func phaselessContinuousNotchIsSmoothed() {
        #expect(WheelEvents.classify(pixelScroll(dy: -12), shiftHorizontal: true) == .smooth(dx: 0, dy: -1, flags: []))
        #expect(WheelEvents.classify(pixelScroll(dy: 184), shiftHorizontal: true) == .smooth(dx: 0, dy: 1, flags: []))
    }

    @Test func trackpadGesturesPassThrough() {
        let began = Int64(CGScrollPhase.began.rawValue), changed = Int64(CGScrollPhase.changed.rawValue)
        #expect(WheelEvents.classify(pixelScroll(dy: 7, phase: began), shiftHorizontal: true) == .pass)
        #expect(WheelEvents.classify(pixelScroll(dy: 7, phase: changed), shiftHorizontal: true) == .pass)
        #expect(WheelEvents.classify(pixelScroll(dy: 30, momentum: 2), shiftHorizontal: true) == .pass)
    }

    @Test func ownEventsPassThrough() {
        let e = wheelNotch(dy: 3)
        e.setIntegerValueField(.eventSourceUserData, value: WheelEvents.marker)
        #expect(WheelEvents.classify(e, shiftHorizontal: true) == .pass)
    }

    @Test func shiftTurnsWheelHorizontal() {
        let e = wheelNotch(dy: 2, flags: [.maskShift, .maskCommand])
        #expect(WheelEvents.classify(e, shiftHorizontal: true) == .smooth(dx: 1, dy: 0, flags: .maskCommand))
        #expect(WheelEvents.classify(e, shiftHorizontal: false) == .smooth(dx: 0, dy: 1, flags: [.maskShift, .maskCommand]))
    }

    @Test func synthesizedEventLooksLikeTrackpad() throws {
        let e = try #require(WheelEvents.makeScroll(dx: 3, dy: -7, phase: .changed, flags: .maskCommand, source: nil))
        #expect(e.type == .scrollWheel)
        #expect(e.getIntegerValueField(.scrollWheelEventIsContinuous) == 1)
        #expect(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -7)
        #expect(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 3)
        #expect(e.getIntegerValueField(.scrollWheelEventScrollPhase) == Int64(CGScrollPhase.changed.rawValue))
        #expect(e.getIntegerValueField(.eventSourceUserData) == WheelEvents.marker)
        #expect(e.flags == .maskCommand)
        #expect(WheelEvents.classify(e, shiftHorizontal: true) == .pass)
    }
}
