import Testing
@testable import SmoothWheelCore

struct SmootherTests {
    /// Runs the smoother to rest, returning every step and the elapsed time.
    private func drain(_ s: inout Smoother, fps: Double = 120) -> (steps: [Smoother.Step], seconds: Double) {
        var steps: [Smoother.Step] = []
        while !s.isIdle && steps.count < 10_000 {
            steps.append(s.advance(by: 1 / fps))
        }
        return (steps, Double(steps.count) / fps)
    }

    @Test func easeCurveRunsFromZeroToOneAndPeaksAtOneFifth() {
        #expect(Smoother.ease(0) == 0)
        #expect(Smoother.ease(1) == 1)
        let samples = stride(from: 0.0, through: 1.0, by: 0.01).map(Smoother.ease)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        // Fastest stretch (largest step between samples) is around u = 0.2.
        let steps = zip(samples, samples.dropFirst()).map { $1 - $0 }
        let fastest = Double(steps.firstIndex(of: steps.max()!)!) / 100
        #expect(abs(fastest - 0.2) <= 0.01)
    }

    @Test func notchTravelsExactDistanceInAnimationTime() {
        var s = Smoother(duration: 0.4)
        s.add(dx: 0, dy: 100)
        let (steps, seconds) = drain(&s)
        #expect(steps.reduce(0) { $0 + $1.dy } == 100)
        #expect(abs(seconds - 0.4) <= 1.0 / 60)
    }

    @Test func easesInThenOut() {
        var s = Smoother(duration: 0.4)
        s.add(dx: 0, dy: 300)
        let dys = drain(&s).steps.map(\.dy)
        let peak = dys.firstIndex(of: dys.max()!)!
        #expect(dys.first! < dys.max()! / 2)
        #expect((6...18).contains(peak), "fastest frame was #\(peak); ease-in should end ~frame 12")
    }

    @Test func neverOvershootsOrGoesBackwards() {
        var s = Smoother(duration: 0.4)
        s.add(dx: -120, dy: 300)
        var x = 0, y = 0
        for step in drain(&s).steps {
            #expect(step.dx <= 0 && step.dy >= 0)
            x += step.dx; y += step.dy
            #expect(x >= -120 && y <= 300)
        }
        #expect(x == -120 && y == 300)
    }

    @Test func fractionalDistancesAreConserved() {
        var s = Smoother(duration: 0.2)
        s.add(dx: 12.4, dy: -37.6)
        let steps = drain(&s).steps
        #expect(steps.reduce(0) { $0 + $1.dx } == 12)
        #expect(steps.reduce(0) { $0 + $1.dy } == -38)
    }

    @Test func notchesDuringAnimationAccumulate() {
        var s = Smoother(duration: 0.4)
        s.add(dx: 0, dy: 100)
        var total = (0..<10).reduce(0) { acc, _ in acc + s.advance(by: 1 / 120).dy }
        s.add(dx: 0, dy: 150)
        total += drain(&s).steps.reduce(0) { $0 + $1.dy }
        #expect(total == 250)
    }

    /// Overlapping notch animations add up to a steady glide, not a pulse per notch.
    @Test func steadyNotchesGiveSteadySpeed() {
        var s = Smoother(duration: 0.4)
        var speeds: [Int] = []
        for frame in 0..<240 {                                 // 2 s at 120 Hz
            if frame % 12 == 0 { s.add(dx: 0, dy: 100) }       // a notch every 100 ms
            let dy = s.advance(by: 1 / 120).dy
            if frame >= 60 { speeds.append(dy) }               // skip the spin-up
        }
        #expect(speeds.min()! > 0)
        #expect(Double(speeds.max()!) / Double(speeds.min()!) < 2,
                "per-frame movement ranged \(speeds.min()!)…\(speeds.max()!) px")
    }

    @Test func reversalTurnsAroundImmediately() {
        var s = Smoother(duration: 0.4)
        s.add(dx: 0, dy: 200)
        for _ in 0..<5 { _ = s.advance(by: 1 / 120) }
        s.add(dx: 0, dy: -50)
        let steps = drain(&s).steps
        #expect(steps.allSatisfy { $0.dy <= 0 })
        #expect(steps.reduce(0) { $0 + $1.dy } == -50)
    }

    /// Spins the wheel: `notches` notches of 100 px, `every` frames apart, then lets it settle.
    /// Returns per-frame movement and the frame index of the last notch.
    private func spin(_ s: inout Smoother, notches: Int, every: Int) -> (dys: [Int], lastNotchFrame: Int) {
        var dys: [Int] = []
        let lastNotchFrame = (notches - 1) * every
        for frame in 0..<10_000 {
            if frame <= lastNotchFrame && frame % every == 0 { s.add(dx: 0, dy: 100) }
            else if s.isIdle { break }
            dys.append(s.advance(by: 1 / 120).dy)
        }
        return (dys, lastNotchFrame)
    }

    @Test func brakingCutsTheGlideAfterTheWheelStops() {
        var full = Smoother(duration: 0.4)
        var braked = Smoother(duration: 0.4, stopTime: 0.15)
        let a = spin(&full, notches: 12, every: 4)      // a notch every 33 ms
        let b = spin(&braked, notches: 12, every: 4)
        let glideFull = a.dys.count - a.lastNotchFrame, glideBraked = b.dys.count - b.lastNotchFrame
        #expect(Double(glideBraked) < Double(glideFull) * 0.6, "glide \(glideBraked) vs \(glideFull) frames")

        // While the wheel is turning, braking changes nothing.
        #expect(Array(a.dys.prefix(b.lastNotchFrame + 1)) == Array(b.dys.prefix(b.lastNotchFrame + 1)))
        // After it stops: never backwards, and never faster than when it stopped.
        let after = b.dys.suffix(from: b.lastNotchFrame)
        #expect(after.allSatisfy { $0 >= 0 })
        let peakAfterStop = after.dropFirst(10).max() ?? 0
        #expect(peakAfterStop <= after.prefix(10).max()! + 1)
    }

    @Test func brakingKeepsMostOfASingleNotch() {
        var s = Smoother(duration: 0.4, stopTime: 0.15)
        s.add(dx: 0, dy: 100)
        let total = drain(&s).steps.reduce(0) { $0 + $1.dy }
        #expect((85...100).contains(total), "single notch moved \(total) px")
    }

    @Test func finishTimeIsIndependentOfRefreshRate() {
        var a = Smoother(duration: 0.4), b = Smoother(duration: 0.4)
        a.add(dx: 0, dy: 80)
        b.add(dx: 0, dy: 80)
        let t60 = drain(&a, fps: 60).seconds, t120 = drain(&b, fps: 120).seconds
        #expect(abs(t60 - t120) <= 1.0 / 60 + 1e-9)
    }
}

struct AccelerationTests {
    /// Feeds notches `gap` seconds apart and returns the boost on the last one.
    private func boost(gap: Double, count: Int = 8, maximum: Double = 3) -> Double {
        var a = Acceleration(maximum: maximum)
        var factor = 1.0
        for i in 0..<count { factor = a.factor(at: Double(i) * gap, direction: 1) }
        return factor
    }

    @Test func slowNotchesGetNoBoost() {
        #expect(boost(gap: 0.1) == 1)    // 10 per second
        #expect(boost(gap: 0.07) == 1)   // ~14 per second
    }

    @Test func boostGrowsWithSpinSpeedUpToMaximum() {
        let medium = boost(gap: 0.03), fast = boost(gap: 0.02), flat = boost(gap: 0.01)
        #expect(1 < medium && medium < fast && fast <= flat)
        #expect(flat == 3)
    }

    @Test func oneQuickPairDoesNotSpikeTheBoost() {
        var a = Acceleration()
        for i in 0..<5 { _ = a.factor(at: Double(i) * 0.08, direction: 1) } // slow spin
        #expect(a.factor(at: 0.322, direction: 1) < 2)                      // then a 2 ms burst
    }

    @Test func directionChangeOrPauseStartsOver() {
        var a = Acceleration()
        for i in 0..<5 { _ = a.factor(at: Double(i) * 0.01, direction: 1) }
        #expect(a.factor(at: 0.05, direction: -1) == 1)
        #expect(a.factor(at: 0.5, direction: -1) == 1)
    }

    @Test func maximumOfOneTurnsItOff() {
        #expect(boost(gap: 0.005, maximum: 1) == 1)
    }
}
