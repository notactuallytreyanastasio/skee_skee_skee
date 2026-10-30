import Testing
@testable import SkeeCore

/// Sweep power at a fixed aim and return the outcomes in order.
func sweep(aim: Double = 0, start: Double = 0, fold: Double = 0,
           table: Table = .standard, steps: Int = 400) -> [(power: Double, result: ShotResult)] {
    (0...steps).map { i in
        let p = Double(i) / Double(steps)
        return (p, simulateShot(Launch(power: p, aim: aim, start: start, fold: fold), on: table))
    }
}

@Suite("Shot physics")
struct PhysicsTests {
    @Test func identicalLaunchesGiveIdenticalShots() {
        let l = Launch(power: 0.55, aim: 0.1, start: -0.2, fold: 0.3)
        #expect(simulateShot(l, on: .standard) == simulateShot(l, on: .standard))
    }

    @Test func weakShotIsADudThatNeverLeavesTheLane() {
        let r = simulateShot(Launch(power: 0.05, aim: 0), on: .standard)
        #expect(r.hole == .gutter)
        #expect(r.events.contains(.dud))
        #expect(r.hingeSpeed == nil)
        #expect(r.path.allSatisfy { $0.phase == .lane })
    }

    @Test func clearingTheHingeReportsLaunchSpeed() {
        let r = simulateShot(Launch(power: 0.6, aim: 0), on: .standard)
        #expect(r.hingeSpeed != nil)
        #expect(r.path.contains { $0.phase == .air })
    }

    @Test func cleanLandingsMoveUpTheBoardWithPower() {
        // Lips and the backwall deflect a ball before it lands; only clean
        // flights have to be monotonic in power.
        let clean = sweep().filter { s in
            !s.result.events.contains(.backwall) && s.result.rattles == 0
        }
        let landings = clean.compactMap { $0.result.firstLanding?.y }
        #expect(landings.count > 10)
        // A ring wall face can stop a descending ball up to one radius early.
        let slack = Table.standard.board.ballRadius
        #expect(zip(landings, landings.dropFirst()).allSatisfy { $0 <= $1 + slack })
        #expect(landings.last! - landings.first! > 0.5)
    }

    @Test func overpoweredShotHitsTheBackwall() {
        let r = simulateShot(Launch(power: 1.0, aim: 0), on: .standard)
        #expect(r.events.contains(.backwall))
    }

    @Test func aStraightShotCanScoreFifty() {
        #expect(sweep().contains { $0.result.hole == .ring50 })
    }

    @Test func everyHoleIsReachable() {
        var seen = Set<Hole>()
        for aim in stride(from: -1.0, through: 1.0, by: 0.1) {
            for start in [-1.0, 0, 1.0] {
                for (_, r) in sweep(aim: aim, start: start, steps: 120) { seen.insert(r.hole) }
            }
        }
        #expect(seen == Set(Hole.allCases))
    }

    @Test func mirroredLaunchGivesMirroredHole() {
        for p in stride(from: 0.3, through: 0.9, by: 0.05) {
            let a = simulateShot(Launch(power: p, aim: 0.4, start: 0.2), on: .standard).hole
            let b = simulateShot(Launch(power: p, aim: -0.4, start: -0.2), on: .standard).hole
            #expect(a.mirrored == b, "power \(p): \(a) vs \(b)")
        }
    }

    @Test func foldingTheHingeLoftsTheBallShorter() {
        let flat = simulateShot(Launch(power: 0.6, aim: 0, fold: 0), on: .standard)
        let folded = simulateShot(Launch(power: 0.6, aim: 0, fold: 1), on: .standard)
        #expect(folded.firstLanding!.y < flat.firstLanding!.y)
        #expect(folded.peakHeight > flat.peakHeight)
    }

    @Test func someShotsRattleOnALip() {
        #expect(sweep().contains { $0.result.events.contains { if case .lip = $0 { true } else { false } } })
    }

    @Test func shotsAlwaysTerminate() {
        for (_, r) in sweep(aim: 0.3, steps: 60) {
            #expect(r.duration < Table.standard.maxDuration + 0.01)
        }
    }

    @Test func launchClampsItsInputs() {
        let l = Launch(power: 3, aim: -9, start: 4, fold: -1)
        #expect(l == Launch(power: 1, aim: -1, start: 1, fold: 0))
    }
}
