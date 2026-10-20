import Foundation

/// Turns wheel notches into a stream of whole-pixel deltas.
///
/// Every notch is its own animation over `duration`. Its speed follows a smooth bell,
/// v(u) ∝ u·(1 − u)⁴: it starts at rest, peaks a fifth of the way in, then eases out to
/// exactly zero at the end. Notches that overlap add together, so a run of them blends into
/// one glide. When the wheel stops, the leftover glide can be cut short (`stopTime`).
///
/// Pure value type: no timers and no events. The engine feeds it notches with `add`
/// and asks for the next frame's movement with `advance(by:)`.
public struct Smoother: Sendable {
    public struct Step: Equatable, Sendable {
        public var dx: Int
        public var dy: Int
        public init(dx: Int, dy: Int) { self.dx = dx; self.dy = dy }
        public var isZero: Bool { dx == 0 && dy == 0 }
    }

    /// Seconds each notch takes to play out.
    public var duration: Double
    /// Once the wheel stops, the leftover glide is replaced by a slowdown from the current speed
    /// that comes to rest in this many seconds. nil lets every notch play out in full.
    public var stopTime: Double?

    private struct Item {
        var dx: Double
        var dy: Double
        var start: Double
        /// Fraction of this notch already emitted (0…1).
        var done = 0.0
    }

    private static let defaultNotchSpacing = 0.1

    private var clock = 0.0
    private var items: [Item] = []
    private var directionX = 0.0, directionY = 0.0
    /// Distance travelled but not yet emitted because it's under a whole pixel.
    private var carryX = 0.0, carryY = 0.0

    // Stop detection and braking.
    private var lastNotch = 0.0
    /// Recent time between notches (smoothed), to tell a pause in the spin from a stop.
    private var notchSpacing = defaultNotchSpacing
    private var braked = false
    /// Speed of the last frame, px/s.
    private var velocityX = 0.0, velocityY = 0.0

    /// The slowdown that replaces the glide after a stop: speed falls as (1 − t/T)² from
    /// `speedX/Y`, so it starts without a jolt and ends exactly at T, having covered v·T/3.
    private struct Coast {
        var speedX: Double
        var speedY: Double
        var length: Double
        var elapsed = 0.0

        func distance(at t: Double) -> (x: Double, y: Double) {
            let u = min(t / length, 1)
            let f = length / 3 * (1 - pow(1 - u, 3))
            return (speedX * f, speedY * f)
        }
    }
    private var coast: Coast?

    public init(duration: Double, stopTime: Double? = nil) {
        self.duration = duration
        self.stopTime = stopTime
    }

    public var isIdle: Bool { items.isEmpty && coast == nil }

    public mutating func add(dx: Double, dy: Double) {
        // A reversal drops whatever was still in flight so the page turns around at once.
        if dx * directionX < 0 || dy * directionY < 0 {
            reset()
        }
        if dx != 0 { directionX = dx }
        if dy != 0 { directionY = dy }
        if isIdle {
            clock = 0
            notchSpacing = Self.defaultNotchSpacing
        } else {
            notchSpacing = notchSpacing * 0.7 + (clock - lastNotch) * 0.3
        }
        lastNotch = clock
        braked = false
        items.append(Item(dx: dx, dy: dy, start: clock))
    }

    public mutating func advance(by dt: Double) -> Step {
        let dt = max(dt, 0)
        clock += dt
        var moveX = 0.0, moveY = 0.0
        for i in items.indices {
            let progress = Self.ease((clock - items[i].start) / max(duration, 0.001))
            let delta = progress - items[i].done
            moveX += delta * items[i].dx
            moveY += delta * items[i].dy
            items[i].done = progress
        }
        items.removeAll { $0.done >= 1 }

        if var c = coast {
            let before = c.distance(at: c.elapsed)
            c.elapsed += dt
            let after = c.distance(at: c.elapsed)
            moveX += after.x - before.x
            moveY += after.y - before.y
            coast = c.elapsed >= c.length ? nil : c
        }
        if dt > 0 {
            velocityX = moveX / dt
            velocityY = moveY / dt
        }
        brakeIfWheelStopped()

        return Step(dx: Self.emit(&carryX, moveX, finished: isIdle),
                    dy: Self.emit(&carryY, moveY, finished: isIdle))
    }

    /// No notch for about two notch-spacings means the wheel has stopped: swap the remaining
    /// animations for a slowdown from the current speed, if that ends sooner than the glide would.
    private mutating func brakeIfWheelStopped() {
        guard let stopTime, !braked, !items.isEmpty else { return }
        let stopDelay = min(max(2 * notchSpacing, 0.06), 0.2)
        guard clock - lastNotch > stopDelay else { return }
        braked = true

        var leftX = 0.0, leftY = 0.0
        for item in items {
            leftX += item.dx * (1 - item.done)
            leftY += item.dy * (1 - item.done)
        }
        if let c = coast {
            let travelled = c.distance(at: c.elapsed), total = c.distance(at: c.length)
            leftX += total.x - travelled.x
            leftY += total.y - travelled.y
        }
        guard hypot(leftX, leftY) > hypot(velocityX, velocityY) * stopTime / 3 else { return }
        items.removeAll()
        coast = Coast(speedX: velocityX, speedY: velocityY, length: stopTime)
    }

    public mutating func reset() {
        items.removeAll()
        coast = nil
        carryX = 0
        carryY = 0
    }

    /// Whole pixels to post now; the remainder carries over (and is rounded off at the end).
    private static func emit(_ carry: inout Double, _ move: Double, finished: Bool) -> Int {
        carry += move
        let whole = finished ? carry.rounded() : carry.rounded(.towardZero)
        carry = finished ? 0 : carry - whole
        return Int(whole)
    }

    /// Fraction of a notch's distance covered at time u ∈ [0, 1] of its animation: the integral
    /// of the speed bell 30·u·(1 − u)⁴, which is 1 − (1 − u)⁵·(1 + 5u).
    static func ease(_ u: Double) -> Double {
        if u <= 0 { return 0 }
        if u >= 1 { return 1 }
        return 1 - pow(1 - u, 5) * (1 + 5 * u)
    }
}

/// Bigger steps for a fast-spinning wheel. The boost follows the (smoothed) notch rate: none
/// below `slowRate` notches per second, rising along a smoothstep to `maximum` at `fastRate`.
/// A change of direction or a pause starts over.
public struct Acceleration: Sendable {
    /// Largest multiplier; 1 turns acceleration off.
    public var maximum: Double
    /// Notches per second where the boost begins.
    public var slowRate: Double
    /// Notches per second where the boost reaches `maximum`.
    public var fastRate: Double

    private var last: (time: Double, direction: Int)?
    /// Smoothed time between notches, so a single burst doesn't spike the boost.
    private var spacing: Double?

    public init(maximum: Double = 3, slowRate: Double = 15, fastRate: Double = 60) {
        self.maximum = maximum
        self.slowRate = slowRate
        self.fastRate = fastRate
    }

    public mutating func factor(at time: Double, direction: Int) -> Double {
        defer { last = (time, direction) }
        guard let last, last.direction == direction, time - last.time < 0.3 else {
            spacing = nil
            return 1
        }
        let gap = max(time - last.time, 0.001)
        let smoothed = spacing.map { 0.5 * $0 + 0.5 * gap } ?? gap
        spacing = smoothed

        let t = min(max((1 / smoothed - slowRate) / (fastRate - slowRate), 0), 1)
        return 1 + (max(maximum, 1) - 1) * t * t * (3 - 2 * t)
    }
}
