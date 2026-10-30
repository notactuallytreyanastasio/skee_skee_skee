import Testing
@testable import SkeeCore

@Suite("Top slot")
struct TopSlotTests {
    func slot(_ a: Symbol, _ b: Symbol, _ c: Symbol) -> TopSlot {
        TopSlot(stops: [a, b, c].map { s in TopSlot.strip.firstIndex(of: s)! })
    }

    @Test func countsReelsMatchingTheBall() {
        let t = slot(.bell, .bell, .lemon)
        #expect(t.symbols == [.bell, .bell, .lemon])
        #expect(t.hits(.bell) == 2)
        #expect(t.hits(.lemon) == 1)
        #expect(t.hits(.seven) == 0)
        #expect(t.hits(.blank) == 0)
    }

    @Test func cloverOnAReelMatchesAnyBallButBlank() {
        let t = slot(.clover, .bell, .cherry)
        #expect(t.hits(.bell) == 2)
        #expect(t.hits(.blank) == 0)
    }

    @Test func cloverBallTakesTheBestSymbolShowing() {
        #expect(slot(.bar, .bar, .cherry).hits(.clover) == 2)
        #expect(slot(.clover, .clover, .clover).hits(.clover) == 3)
    }

    @Test func comboMultGrowsWithHitsAndLevelAndCaps() {
        #expect(TopSlot.comboMult(hits: 0, level: 3) == 0)
        #expect(TopSlot.comboMult(hits: 1, level: 1) == 0.5)
        #expect(TopSlot.comboMult(hits: 2, level: 3) == 3)
        #expect(TopSlot.comboMult(hits: 1, level: 99) == TopSlot.comboMult(hits: 1, level: TopSlot.maxLevel))
    }

    @Test func aBallThatHitTheSlotAddsMultInTheFrame() {
        let hit = BallRecord(hole: .ring30, symbol: .bell, chips: 30, slotHits: 2, combo: 3)
        let plain = BallRecord(hole: .ring10, symbol: .cherry, chips: 10)
        let f = scoreFrame([hit, plain, plain], context: ScoringContext())
        #expect(f.steps.contains(ScoreStep(source: .slot(0), effect: .mult(3))))
        #expect(f.mult == 1 + 1 + 3)   // pair of cherries + slot combo
    }

    @Test func threeOfAKindOnTheSlotHitPaysTickets() {
        let hit = BallRecord(hole: .ring30, symbol: .bell, chips: 30, slotHits: 3, combo: 1)
        let f = scoreFrame([hit], context: ScoringContext())
        #expect(f.tickets == TopSlot.jackpotTickets)
    }

    @Test func theSlotSpinsEveryThrowAndFouls() throws {
        var s = newRun(seed: 3)
        var seen: Set<[Int]> = [s.topSlot.stops]
        for _ in 0..<4 {
            s = try apply(.foul, to: s).get().state
            seen.insert(s.topSlot.stops)
        }
        #expect(seen.count > 2)
    }

    @Test func comboChainsOnHitsAndBreaksOnAMiss() throws {
        var s = newRun(seed: 1)
        // Force the slot to show what ring30 shows, so the throw hits it.
        let want = s.showing(.ring30)
        s.topSlot = slot(want, .blankFree, .blankFree)
        var step = try apply(.throwBall(launch(for: .ring30, on: table(for: s))), to: s).get()
        #expect(step.state.round.combo == 1)
        #expect(step.state.round.currentBalls.last?.slotHits ?? 0 >= 1)

        s = step.state
        s.topSlot = slot(s.showing(.ring30), .blankFree, .blankFree)
        step = try apply(.throwBall(launch(for: .ring30, on: table(for: s))), to: s).get()
        #expect(step.state.round.combo == 2)
        #expect(step.state.round.currentBalls.last?.combo == 2)

        step = try apply(.foul, to: step.state).get()
        #expect(step.state.round.combo == 0)
    }

    @Test func sameSeedSameSlot() {
        #expect(newRun(seed: 9).topSlot == newRun(seed: 9).topSlot)
    }
}

extension Symbol {
    /// A symbol no ring shows in the standard setup, for slot tests.
    static let blankFree: Symbol = .diamond
}
