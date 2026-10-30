import Testing
import SkeeCore
@testable import SkeeRender

@Suite("Presentation")
struct PresentationTests {
    func throwOnce(_ s: RunState, power: Double = 0.6) -> Step {
        try! apply(.throwBall(Launch(power: power, aim: 0)), to: s).get()
    }

    @Test func showsOldStateUntilTheBallLands() {
        let s = newRun(seed: 3)
        var p = Presentation(state: s)
        let step = throwOnce(s)
        p.enqueue(step)
        #expect(p.isBusy)
        p.advance(0.3)
        #expect(p.shown == s)
        #expect(p.ball != nil)
    }

    @Test func endsOnTheRealState() {
        let s = newRun(seed: 3)
        var p = Presentation(state: s)
        let step = throwOnce(s)
        p.enqueue(step)
        p.skip()
        #expect(!p.isBusy)
        #expect(p.shown == step.state)
        #expect(p.reelPositions == step.state.stops.mapValues(Double.init))
    }

    @Test func ballMovesForwardWhileRolling() {
        let s = newRun(seed: 3)
        var p = Presentation(state: s)
        p.enqueue(throwOnce(s))
        p.advance(0.1)
        let a = p.ball!.along
        p.advance(0.2)
        #expect(p.ball!.along > a)
    }

    @Test func aFrameIsTalliedAfterItsThirdBall() {
        var s = newRun(seed: 3)
        var p = Presentation(state: s)
        for _ in 0..<3 {
            let step = throwOnce(s)
            p.enqueue(step); s = step.state
        }
        var sawTally = false
        while p.isBusy {
            if p.tallyProgress != nil { sawTally = true }
            p.advance(1 / 30)
        }
        #expect(sawTally)
    }

    @Test func tallyScoreStaysOnScreenUntilCommit() {
        var s = newRun(seed: 3)
        var p = Presentation(state: s)
        var last: Step!
        for _ in 0..<3 { last = throwOnce(s); p.enqueue(last); s = last.state }
        while p.tallyProgress == nil { p.advance(1 / 60) }
        while p.tallyProgress != nil { p.advance(1 / 60) }
        #expect(p.shown.round.score + p.talliedBonus == last.state.round.score)
    }

    @Test func samplingInterpolates() {
        let path = [PathSample(t: 0, phase: .lane, x: 0, along: 0, height: 0),
                    PathSample(t: 1, phase: .lane, x: 0, along: 2, height: 0)]
        #expect(Presentation.sample(path, at: 0.25)!.along == 0.5)
        #expect(Presentation.sample(path, at: 9)!.along == 2)
    }
}
