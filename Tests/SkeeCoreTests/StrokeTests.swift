import Foundation
import Testing
@testable import SkeeCore

/// A lane like the Duo's inner display: crease at y = 445. For tests, lane
/// metres map linearly to the screen at 260 pt/m (the shell does the real
/// perspective mapping).
let duoLane = StrokeGeometry(creaseY: 445, laneHalfWidth: 0.31)
let ptPerM = 260.0
func screenY(_ s: Double) -> Double { 840 - s * ptPerM }

/// A thumb slide sampled at 120 Hz. `speed(t)` is the ball's speed up the
/// lane in m/s while held; `drift(t)` its sideways speed.
func slide(from s0: Double = 0.05, x0: Double = 0, seconds: Double,
           speed: (Double) -> Double, drift: (Double) -> Double = { _ in 0 }) -> [StrokeSample] {
    var out: [StrokeSample] = []
    var x = x0, s = s0, t = 0.0
    let dt = 1.0 / 120
    while t <= seconds {
        out.append(StrokeSample(t: t, screenX: 313 + x * ptPerM, screenY: screenY(s), x: x, s: s))
        s += speed(t) * dt
        x += drift(t) * dt
        t += dt
    }
    return out
}

@Suite("Thumb stroke")
struct StrokeTests {
    @Test func theThrowCarriesTheBallsSpeedAtRelease() {
        // Thumb builds from 1 to ~3.4 m/s.
        let s = slide(seconds: 0.4) { t in 1 + 6 * t }
        guard case .release(let l) = analyzeStroke(s, in: duoLane) else { Issue.record("not a throw"); return }
        let tuning = StrokeTuning.standard
        // Thumb speed on the glass at release, times metres per point.
        #expect(abs(l.speed - (1 + 6 * 0.4) * ptPerM * tuning.metersPerPoint) < 0.1)
        #expect(abs(l.from - s.last!.s) < 0.01)
        #expect(l.skid < 0.15)
        #expect(abs(l.aim) < 0.05 && abs(l.spin) < 0.1)
    }

    @Test func fasterThumbFasterBall() {
        guard case .release(let a) = analyzeStroke(slide(seconds: 0.35) { t in 1 + 3 * t }, in: duoLane),
              case .release(let b) = analyzeStroke(slide(seconds: 0.35) { t in 1 + 7 * t }, in: duoLane)
        else { Issue.record("not throws"); return }
        #expect(b.speed > a.speed + 1)
    }

    @Test func aStopAndGoSlideSkids() {
        let s = slide(seconds: 0.35) { t in 1.6 + 1.2 * sin(t * 50) }
        guard case .release(let l) = analyzeStroke(s, in: duoLane) else { Issue.record("not a throw"); return }
        #expect(l.skid > 0.4)
    }

    @Test func curvingAtTheReleaseSpins() {
        let s = slide(seconds: 0.35, speed: { t in 1 + 6 * t }, drift: { t in t > 0.22 ? 30 * (t - 0.22) : 0 })
        guard case .release(let l) = analyzeStroke(s, in: duoLane) else { Issue.record("not a throw"); return }
        #expect(l.spin > 0.3)
        #expect(l.aim > 0)
    }

    @Test func farPastTheCreaseIsAFoul() {
        let s = slide(seconds: 0.5) { _ in 3.5 }   // ends ~1.8 m up: screenY ~370
        #expect(analyzeStroke(s, in: duoLane) == .foul)
    }

    @Test func dippingIntoTheCreaseIsNotAFoul() {
        // The thumb sinks into the fold as it lets go: that's the feel we
        // want, not a foul. Ends ~30 pt past the crease, inside the give.
        let s = slide(from: 0.3, seconds: 0.5) { t in 1 + 6.5 * t }
        #expect(s.last!.screenY < duoLane.creaseY)
        #expect(s.last!.screenY > duoLane.foulY)
        guard case .release = analyzeStroke(s, in: duoLane) else { Issue.record("dip counted as foul"); return }
    }

    @Test func aTapIsNotAThrow() {
        let s = [StrokeSample(t: 0, screenX: 300, screenY: 800, x: 0, s: 0.1), StrokeSample(t: 0.05, screenX: 300, screenY: 799, x: 0, s: 0.101)]
        #expect(analyzeStroke(s, in: duoLane) == .none)
    }

    @Test func pullingBackIsNotAThrow() {
        let s = slide(from: 0.8, seconds: 0.2) { _ in -2 }
        #expect(analyzeStroke(s, in: duoLane) == .none)
    }

    @Test func releasePointSetsTheStartingLine() {
        let s = slide(x0: -0.25, seconds: 0.3) { t in 1 + 6 * t }
        guard case .release(let l) = analyzeStroke(s, in: duoLane) else { Issue.record("not a throw"); return }
        #expect(l.start < -0.7)
    }

    @Test func analysisIsDeterministic() {
        let s = slide(seconds: 0.3) { t in 1.6 + 0.9 * sin(t * 30) }
        #expect(analyzeStroke(s, in: duoLane) == analyzeStroke(s, in: duoLane))
    }
}

@Suite("Release point")
struct ReleaseTests {
    @Test func powerStillMeansSpeedFromTheLine() {
        let l = Launch(power: 0.5, aim: 0)
        #expect(l.from == 0)
        #expect(l.speed == LaneSpec.standard.releaseSpeed(power: 0.5))
    }

    @Test func oldSavesStillDecode() throws {
        let json = #"{"power":0.6,"aim":0,"start":0,"fold":0}"#
        let l = try JSONDecoder().decode(Launch.self, from: Data(json.utf8))
        #expect(l == Launch(power: 0.6, aim: 0))
        let round = try JSONDecoder().decode(Launch.self, from: JSONEncoder().encode(Launch(speed: 3, from: 1, aim: 0.2)))
        #expect(round == Launch(speed: 3, from: 1, aim: 0.2))
    }

    @Test func aShotStartsWhereItWasLetGo() {
        let r = simulateShot(Launch(speed: 3, from: 0.8, aim: 0), on: .standard)
        #expect(abs(r.path.first!.along - 0.8) < 1e-9)
    }

    @Test func letGoFurtherUpAtTheSameSpeedFliesFurther() {
        let near = simulateShot(Launch(speed: 3.2, from: 0, aim: 0), on: .standard)
        let far = simulateShot(Launch(speed: 3.2, from: 1.0, aim: 0), on: .standard)
        #expect(far.hingeSpeed! > near.hingeSpeed!)
    }
}
