import Testing
import SkeeCore
@testable import SkeeRender

/// A fresh run with the first frame's lever already pulled.
func pulledRun(_ seed: UInt64) -> RunState {
    try! apply(.pull(.one), to: newRun(seed: seed)).get().state
}

@Suite("Presentation")
struct PresentationTests {
    func throwOnce(_ s: RunState, power: Double = 0.6) -> Step {
        try! apply(.throwBall(Launch(power: power, aim: 0)), to: s).get()
    }

    @Test func showsOldStateUntilTheBallLands() {
        let s = pulledRun(3)
        var p = Presentation(state: s)
        let step = throwOnce(s)
        p.enqueue(step)
        #expect(p.isBusy)
        p.advance(0.3)
        #expect(p.shown == s)
        #expect(p.ball != nil)
    }

    @Test func endsOnTheRealState() {
        let s = pulledRun(3)
        var p = Presentation(state: s)
        let step = throwOnce(s)
        p.enqueue(step)
        p.skip()
        #expect(!p.isBusy)
        #expect(p.shown == step.state)
        #expect(p.reelPositions == step.state.stops.mapValues(Double.init))
    }

    @Test func ballMovesForwardWhileRolling() {
        let s = pulledRun(3)
        var p = Presentation(state: s)
        p.enqueue(throwOnce(s))
        p.advance(0.1)
        let a = p.ball!.along
        p.advance(0.2)
        #expect(p.ball!.along > a)
    }

    @Test func aFrameIsTalliedAfterItsThirdBall() {
        var s = pulledRun(3)
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
        var s = pulledRun(3)
        var p = Presentation(state: s)
        var last: Step!
        for _ in 0..<3 { last = throwOnce(s); p.enqueue(last); s = last.state }
        while p.tallyProgress == nil { p.advance(1 / 60) }
        while p.tallyProgress != nil { p.advance(1 / 60) }
        #expect(p.shown.round.score + p.talliedBonus == last.state.round.score)
    }

    @Test func rollStartsWhereTheThumbLetGo() {
        let s = pulledRun(3)
        var p = Presentation(state: s)
        p.enqueue(throwOnce(s), releaseAlong: 0.8)
        p.advance(1 / 120)
        #expect(p.ball!.along >= 0.8)
        #expect(p.ball!.along < 0.9)
    }

    @Test func shotEventsBecomeTimedCues() {
        let s = pulledRun(3)
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
        var s = pulledRun(3)
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
        let s = pulledRun(3)
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
    @Test func thePullSpinsTheMachineToItsStopsAndHoldsTheWin() throws {
        let s = newRun(seed: 2)
        var p = Presentation(state: s)
        let step = try apply(.pull(.one), to: s).get()
        p.enqueue(step)
        let pull = step.state.round.pull!
        var moved = false, cues: [Cue] = []
        while p.isBusy {
            p.advance(1.0 / 60)
            cues += p.cues
            if p.pullPositions != pull.stops.map(Double.init) { moved = true }
        }
        #expect(moved)
        #expect(p.pullPositions == pull.stops.map(Double.init))
        #expect(p.lastPull == pull)
        #expect(cues.first == .lever)
        #expect(cues.filter { $0 == .reelStop }.count == 3)
    }

    @Test func twoBonusOnTheFirstReelsMakeTheLastOneHangOn() {
        let plain = Pull(stops: [0, 0, 0], bet: .one)
        var tease = plain
        // Find stops that show a BONUS on reels 1 and 2.
        tease.stops[0] = Pull.strips[0].firstIndex(of: .bonus)!
        tease.stops[1] = Pull.strips[1].firstIndex(of: .bonus)!
        #expect(Presentation.pullStop(2, tease) > Presentation.pullStop(2, plain) + 0.5)
    }

    @Test func aMatchingBallCallsOutTheCombo() {
        let s = pulledRun(2)
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
