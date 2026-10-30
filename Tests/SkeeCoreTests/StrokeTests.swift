import Foundation
import Testing
@testable import SkeeCore

/// A lane like the Duo's inner display: crease across the middle.
let duoLane = StrokeGeometry(creaseY: 445, laneMinX: 40, laneMaxX: 586, bottomY: 860)

/// Thumb slide sampled at 120 Hz. `speed(t)` is upward speed in pt/s,
/// `drift(t)` sideways speed.
func slide(from y0: Double = 840, x0: Double = 313, seconds: Double,
           speed: (Double) -> Double, drift: (Double) -> Double = { _ in 0 }) -> [TouchSample] {
    var out: [TouchSample] = []
    var x = x0, y = y0, t = 0.0
    let dt = 1.0 / 120
    while t <= seconds {
        out.append(TouchSample(t: t, x: x, y: y))
        y -= speed(t) * dt
        x += drift(t) * dt
        t += dt
    }
    return out
}

@Suite("Thumb stroke")
struct StrokeTests {
    @Test func aSmoothAcceleratingSlideIsACleanThrow() {
        let s = slide(seconds: 0.28) { t in 400 + 6000 * t }   // 400 -> ~2080 pt/s
        guard case .release(let l) = analyzeStroke(s, in: duoLane) else { Issue.record("not a throw"); return }
        #expect(l.skid < 0.15)
        #expect(abs(l.aim) < 0.05)
        #expect(abs(l.spin) < 0.1)
        #expect(l.power > 0.5)
    }

    @Test func fasterReleaseIsMorePower() {
        let slow = analyzeStroke(slide(seconds: 0.28) { t in 300 + 3000 * t }, in: duoLane)
        let fast = analyzeStroke(slide(seconds: 0.28) { t in 300 + 6500 * t }, in: duoLane)
        guard case .release(let a) = slow, case .release(let b) = fast else { Issue.record("not throws"); return }
        #expect(b.power > a.power + 0.2)
    }

    @Test func aStopAndGoSlideSkids() {
        // Thumb hitches twice on the way up.
        let s = slide(seconds: 0.3) { t in 1000 + 800 * sin(t * 50) }
        guard case .release(let l) = analyzeStroke(s, in: duoLane) else { Issue.record("not a throw"); return }
        #expect(l.skid > 0.4)
    }

    @Test func curvingAtTheReleaseSpins() {
        let s = slide(seconds: 0.28, speed: { t in 500 + 5500 * t }, drift: { t in t > 0.18 ? 2500 * (t - 0.18) * 10 : 0 })
        guard case .release(let l) = analyzeStroke(s, in: duoLane) else { Issue.record("not a throw"); return }
        #expect(l.spin > 0.3)
        #expect(l.aim > 0)
    }

    @Test func touchingPastTheCreaseIsAFoul() {
        let s = slide(seconds: 0.4) { _ in 1400 }   // 840 - 560 = 280 < 445
        #expect(analyzeStroke(s, in: duoLane) == .foul)
        #expect(crossedCrease(s, in: duoLane))
    }

    @Test func aTapIsNotAThrow() {
        let s = [TouchSample(t: 0, x: 300, y: 800), TouchSample(t: 0.05, x: 301, y: 799)]
        #expect(analyzeStroke(s, in: duoLane) == .none)
    }

    @Test func draggingDownIsNotAThrow() {
        let s = slide(from: 600, seconds: 0.2) { _ in -900 }
        #expect(analyzeStroke(s, in: duoLane) == .none)
    }

    @Test func releasePointSetsTheStartingLine() {
        let s = slide(x0: 90, seconds: 0.25) { t in 500 + 5000 * t }
        guard case .release(let l) = analyzeStroke(s, in: duoLane) else { Issue.record("not a throw"); return }
        #expect(l.start < -0.7)
    }

    @Test func analysisIsDeterministic() {
        let s = slide(seconds: 0.3) { t in 1600 + 900 * sin(t * 30) }
        #expect(analyzeStroke(s, in: duoLane) == analyzeStroke(s, in: duoLane))
    }
}
