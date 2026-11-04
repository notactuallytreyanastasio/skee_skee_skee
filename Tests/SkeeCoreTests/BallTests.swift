import Testing
@testable import SkeeCore

@Suite("Balls and the Hot Spot")
struct BallTests {
    let throwOne = Launch(power: 0.6, aim: 0)

    @Test func randomBallsReplayFromTheirSeed() {
        for ball in [BallKind.bean, .wobbler] {
            let a = simulateShot(throwOne, on: .standard, ball: ball, seed: 5)
            #expect(a == simulateShot(throwOne, on: .standard, ball: ball, seed: 5))
            let paths = (0..<8).map { simulateShot(throwOne, on: .standard, ball: ball, seed: $0).path }
            #expect(Set(paths.map(\.count)).count > 1 || paths.contains { $0 != paths[0] }, "\(ball) ignores its seed")
        }
    }

    @Test func aClassicBallIgnoresTheSeed() {
        #expect(simulateShot(throwOne, on: .standard, seed: 1) == simulateShot(throwOne, on: .standard, seed: 2))
    }

    @Test func aBeanHops() {
        let hops = (0..<20).map { simulateShot(throwOne, on: .standard, ball: .bean, seed: $0).events.filter { $0 == .hop }.count }
        #expect(hops.reduce(0, +) > 20)
    }

    @Test func aCometLeavesFaster() {
        let classic = simulateShot(throwOne, on: .standard)
        let comet = simulateShot(throwOne, on: BallKind.comet.modify(.standard), ball: .comet)
        #expect((comet.hingeSpeed ?? 0) > (classic.hingeSpeed ?? 0))
    }

    /// The easy ball must really be easy: an earlier version looked gentle
    /// and hit the bullseye no more often.
    @Test func aMarshmallowFindsTheBullseye() {
        func fifties(_ ball: BallKind) -> Int {
            var n = 0
            let t = ball.modify(.standard)
            for p in stride(from: 0.3, through: 0.9, by: 0.02) {
                for a in stride(from: -0.3, through: 0.3, by: 0.1) where simulateShot(Launch(power: p, aim: a), on: t, ball: ball).hole == .ring50 { n += 1 }
            }
            return n
        }
        #expect(fifties(.marshmallow) > fifties(.classic))
    }

    @Test func choosingABallIsFreeAndStays() throws {
        var s = newRun(seed: 1)
        let tickets = s.tickets
        s = try apply(.chooseBall(.comet), to: s).get().state
        #expect(s.ball == .comet && s.tickets == tickets)
        s = try apply(.pull(.one), to: s).get().state
        s = try apply(.throwBall(throwOne), to: s).get().state
        #expect(s.ball == .comet)
        #expect(s.round.currentBalls[0].ball == .comet)
    }

    @Test func everyPullPicksAHotSpotThatIsWorthHaving() throws {
        for seed in UInt64(1)...30 {
            let s = try apply(.pull(.one), to: newRun(seed: seed)).get().state
            let hot = try #require(s.round.hot)
            #expect(Hole.hotSpots.contains(hot))
            #expect(hot != .ring10 && hot != .gutter)
        }
    }

    @Test func chipsAreBallPayTimesHotSpot() throws {
        for ball in BallKind.allCases {
            var s = try apply(.chooseBall(ball), to: newRun(seed: 3)).get().state
            s = try apply(.pull(.one), to: s).get().state
            s = try apply(.throwBall(throwOne), to: s).get().state
            let b = s.round.currentBalls[0]
            let base = Double(s.setup.chips(for: b.hole))
            #expect(b.chips == Int((base * ball.pay * (b.hot ? 2 : 1)).rounded()))
            #expect(b.hot == (b.hole == s.round.hot))
        }
    }
}
