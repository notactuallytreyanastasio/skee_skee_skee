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

    @Test func rollStartsWhereTheThumbLetGo() {
        let s = newRun(seed: 3)
        var p = Presentation(state: s)
        p.enqueue(throwOnce(s), releaseAlong: 0.8)
        p.advance(1 / 120)
        #expect(p.ball!.along >= 0.8)
        #expect(p.ball!.along < 0.9)
    }

    @Test func shotEventsBecomeTimedCues() {
        let s = newRun(seed: 3)
        var p = Presentation(state: s)
        p.enqueue(throwOnce(s))
        var cues: [Cue] = []
        while p.isBusy { p.advance(1 / 60); cues += p.cues }
        #expect(cues.contains(.hump))
        #expect(cues.contains { if case .drop = $0 { true } else { false } } || cues.contains(.gutter))
        #expect(cues.contains(.reelStop))
        let hump = cues.firstIndex(of: .hump)!
        let land = cues.firstIndex { if case .drop = $0 { true } else { $0 == .gutter } }!
        #expect(hump < land)
    }

    @Test func aPairWithTheThirdBallInTheAirSlowsTime() {
        var s = newRun(seed: 3)
        s.round.currentBalls = [BallRecord(hole: .ring30, symbol: .bell, chips: 30),
                                BallRecord(hole: .ring30, symbol: .bell, chips: 30)]
        var p = Presentation(state: s)
        p.enqueue(throwOnce(s))
        var sawSlow = false, sawAnticipation = false
        while p.isBusy {
            p.advance(1 / 60)
            if p.timeScale < 1 { sawSlow = true }
            if p.anticipation > 0 { sawAnticipation = true }
        }
        #expect(sawSlow && sawAnticipation)
    }

    @Test func noPairNoSlowMotion() {
        let s = newRun(seed: 3)
        var p = Presentation(state: s)
        p.enqueue(throwOnce(s))
        while p.isBusy { p.advance(1 / 60); #expect(p.timeScale == 1) }
    }

    @Test func samplingInterpolates() {
        let path = [PathSample(t: 0, phase: .lane, x: 0, along: 0, height: 0),
                    PathSample(t: 1, phase: .lane, x: 0, along: 2, height: 0)]
        #expect(Presentation.sample(path, at: 0.25)!.along == 0.5)
        #expect(Presentation.sample(path, at: 9)!.along == 2)
    }
}

@Suite("Presentation: top slot")
struct TopSlotPresentationTests {
    @Test func theTopSlotSpinsToItsNewStopsAfterAThrow() throws {
        let s = newRun(seed: 2)
        var p = Presentation(state: s)
        let step = try apply(.foul, to: s).get()
        p.enqueue(step)
        #expect(p.slotPositions == s.topSlot.stops.map(Double.init))
        var moved = false
        while p.isBusy {
            p.advance(1.0 / 60)
            if p.slotPositions != s.topSlot.stops.map(Double.init) { moved = true }
        }
        #expect(moved)
        #expect(p.slotPositions == step.state.topSlot.stops.map(Double.init))
        #expect(p.shownSlot == step.state.topSlot.symbols)
    }

    @Test func aMatchingBallCallsOutTheCombo() {
        let s = newRun(seed: 2)
        var p = Presentation(state: s)
        var after = s
        let ball = BallRecord(hole: .ring30, symbol: .bell, chips: 30, slotHits: 2, combo: 3)
        after.round.currentBalls = [ball]
        let shot = simulateShot(Launch(power: 0.5, aim: 0), on: .standard)
        p.enqueue(Step(state: after, events: [.shot(shot, ball)]))
        var cues: [Cue] = []
        while p.isBusy { p.advance(1.0 / 60); cues += p.cues }
        #expect(cues.contains(.combo(3)))
    }
}
