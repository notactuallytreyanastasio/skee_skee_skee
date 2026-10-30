import Testing
@testable import SkeeCore

@Suite("Ring holes")
struct RingHoleTests {
    /// Real skee-ball: every ring has its own hole at the bottom, and a ball
    /// that lands in a ring rolls down into it. Nothing just "settles".
    @Test func everyScoringBallDropsThroughAHole() {
        for aim in [-0.4, 0, 0.3] {
            for (_, r) in sweep(aim: aim, steps: 200) where r.hole != .gutter {
                #expect(r.events.last == .dropped(r.hole), "\(r.hole): \(r.events.suffix(3))")
            }
        }
    }

    @Test func holesSitInAColumnBelowTheCentre() {
        let b = BoardSpec.standard
        let ys = [Hole.ring50, .ring40, .ring30, .ring20, .ring10].map { b.holeCenter($0).y }
        #expect(zip(ys, ys.dropFirst()).allSatisfy { $0 > $1 })
        for h in [Hole.ring40, .ring30, .ring20, .ring10] {
            #expect(b.holeCenter(h).x == 0)
            #expect(b.zone(at: b.holeCenter(h)) == h)
        }
    }
}

@Suite("Spin and skid")
struct SpinSkidTests {
    @Test func spinHooksTheBall() {
        let plain = simulateShot(Launch(power: 0.6, aim: 0), on: .standard)
        let hook = simulateShot(Launch(power: 0.6, aim: 0, spin: 1), on: .standard)
        let back = simulateShot(Launch(power: 0.6, aim: 0, spin: -1), on: .standard)
        #expect(hook.firstLanding!.x > plain.firstLanding!.x + 0.02)
        #expect(back.firstLanding!.x < plain.firstLanding!.x - 0.02)
    }

    @Test func aJerkyStrokeSkidsAndLosesSpeed() {
        let clean = simulateShot(Launch(power: 0.6, aim: 0), on: .standard)
        let skid = simulateShot(Launch(power: 0.6, aim: 0, skid: 1), on: .standard)
        #expect(skid.hingeSpeed! < clean.hingeSpeed! * 0.95)
    }

    @Test func spinAndSkidAreClamped() {
        let l = Launch(power: 0.5, aim: 0, spin: 7, skid: -2)
        #expect(l.spin == 1 && l.skid == 0)
    }
}

@Suite("Fouls")
struct FoulTests {
    @Test func aFoulSpendsABallForNothing() throws {
        let s = newRun(seed: 4)
        let step = try apply(.foul, to: s).get()
        let ball = step.state.round.currentBalls[0]
        #expect(ball.foul)
        #expect(ball.chips == 0 && ball.symbol == .blank)
        #expect(step.events.contains(.fouled))
        #expect(step.state.round.ballsLeft == s.round.ballsLeft - 1)
        #expect(step.state.heat == s.heat)
    }

    @Test func gutterRatDoesNotPayForFouls() {
        let foul = BallRecord(hole: .gutter, symbol: .blank, chips: 0, foul: true)
        let f = scoreFrame([foul, foul, foul], context: .init(charms: [.gutterRat]))
        #expect(f.total == 0)
    }

    @Test func foulOnlyWhileThrowing() {
        var s = newRun(seed: 4)
        s.phase = .lost
        #expect(throws: ActionError.wrongPhase) { try apply(.foul, to: s).get() }
    }
}
