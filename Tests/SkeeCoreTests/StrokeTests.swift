import Foundation
import Testing
@testable import SkeeCore

/// Inner display: crease at y = 445, lane centred at x = 313, ~260 pt either side.
let duoLane = FlickGeometry(creaseY: 445, laneCenterX: 313, laneHalfWidth: 260)

/// A natural flick: minimum-jerk motion (the standard model of a human
/// reach) over `distance` points in `duration` seconds, lifted at `lift`
/// of the way through the movement, sampled at 120 Hz.
func flick(distance: Double = 220, duration: Double = 0.16, lift: Double = 0.8,
           from y0: Double = 820, x0: Double = 313, lateral: (Double) -> Double = { _ in 0 },
           wobble: Double = 0) -> [FlickSample] {
    var out: [FlickSample] = []
    let dt = 1.0 / 120
    var t = 0.0
    while t <= duration * lift + 1e-9 {
        let u = t / duration
        let d = distance * (10 * pow(u, 3) - 15 * pow(u, 4) + 6 * pow(u, 5))
        let w = wobble * sin(t * 90)
        out.append(FlickSample(t: t, x: x0 + lateral(u), y: y0 - d - w))
        t += dt
    }
    return out
}

func launch(_ s: [FlickSample]) -> Launch? {
    if case .release(let l) = analyzeFlick(s, in: duoLane) { return l }
    return nil
}

@Suite("Flick")
struct FlickTests {
    @Test func aNaturalFlickIsClean() {
        let l = launch(flick())!
        #expect(l.skid < 0.15)
        #expect(abs(l.aim) < 0.05)
        #expect(abs(l.spin) < 0.1)
        #expect(l.from == 0)
    }

    @Test func aQuickerFlickThrowsHarder() {
        let slow = launch(flick(duration: 0.24))!
        let fast = launch(flick(duration: 0.12))!
        #expect(fast.power > slow.power + 0.15)
    }

    @Test func aLongerFlickThrowsHarder() {
        #expect(launch(flick(distance: 300))!.power > launch(flick(distance: 150))!.power + 0.1)
    }

    @Test func easingOffBeforeLettingGoCostsSpeed() {
        // Same motion; one lets go mid-stroke at speed, one rides it out to
        // nearly a stop before lifting.
        let snap = launch(flick(lift: 0.6))!
        let lazy = launch(flick(lift: 0.97))!
        #expect(snap.power > lazy.power)
    }

    @Test func aShakyFlickSkids() {
        #expect(launch(flick(wobble: 9))!.skid > 0.4)
    }

    @Test func hookingTheThumbAtTheEndSpins() {
        let l = launch(flick(lateral: { u in u > 0.55 ? 90 * pow(u - 0.55, 2) * 10 : 0 }))!
        #expect(l.spin > 0.3)
    }

    @Test func flickingRightAimsRight() {
        #expect(launch(flick(lateral: { u in 40 * u }))!.aim > 0.2)
    }

    @Test func whereYouFlickSetsTheLine() {
        #expect(launch(flick(x0: 120))!.start < -0.4)
    }

    @Test func liftingOffJustPastTheCreaseIsFine() {
        // Natural flicks overshoot. 820 - 400 = 420: 25 pt past the crease.
        #expect(launch(flick(distance: 520, duration: 0.2)) != nil)
    }

    @Test func draggingFarPastTheCreaseIsAFoul() {
        let s = flick(distance: 700, duration: 0.5, lift: 1.0)
        #expect(s.last!.y < duoLane.foulY)
        #expect(analyzeFlick(s, in: duoLane) == .foul)
    }

    @Test func startingAboveTheCreaseIsNotAThrow() {
        #expect(analyzeFlick(flick(from: 400), in: duoLane) == .none)
    }

    @Test func aTapIsNotAThrow() {
        #expect(analyzeFlick(flick(distance: 8, duration: 0.1), in: duoLane) == .none)
    }

    @Test func pullingDownIsNotAThrow() {
        #expect(analyzeFlick(flick(distance: -200, from: 500), in: duoLane) == .none)
    }

    @Test func deterministic() {
        let s = flick(wobble: 4)
        #expect(analyzeFlick(s, in: duoLane) == analyzeFlick(s, in: duoLane))
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
    }

    @Test func aShotStartsWhereItWasLetGo() {
        let r = simulateShot(Launch(speed: 3, from: 0.8, aim: 0), on: .standard)
        #expect(abs(r.path.first!.along - 0.8) < 1e-9)
    }
}
