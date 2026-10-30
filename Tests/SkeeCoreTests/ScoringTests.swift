import Testing
@testable import SkeeCore

func ball(_ hole: Hole, _ symbol: Symbol? = nil, rattles: Int = 0, fold: Double = 0,
          setup: BoardSetup = .standard) -> BallRecord {
    BallRecord(hole: hole, symbol: symbol ?? setup.symbol(for: hole),
               chips: setup.chips(for: hole), rattles: rattles, fold: fold)
}

@Suite("Payline")
struct PaylineTests {
    @Test func threeOfAKind() {
        #expect(Payline.evaluate([.seven, .seven, .seven]) == .triple(.seven))
    }

    @Test func pairAnywhere() {
        #expect(Payline.evaluate([.bell, .cherry, .bell]) == .pair(.bell))
    }

    @Test func cloverIsWild() {
        #expect(Payline.evaluate([.clover, .bar, .bar]) == .triple(.bar))
        #expect(Payline.evaluate([.clover, .bar, .lemon]) == .pair(.bar))
    }

    @Test func wildPrefersTheBestSymbol() {
        #expect(Payline.evaluate([.clover, .lemon, .seven]) == .pair(.seven))
    }

    @Test func blanksNeverMatch() {
        #expect(Payline.evaluate([.blank, .blank, .blank]) == .none)
        #expect(Payline.evaluate([.blank, .clover, .blank]) == .none)
    }

    @Test func threeCloversAreTripleClover() {
        #expect(Payline.evaluate([.clover, .clover, .clover]) == .triple(.clover))
    }
}

@Suite("Frame scoring")
struct FrameScoringTests {
    @Test func plainFrameIsChipsTimesOne() {
        let f = scoreFrame([ball(.ring10), ball(.ring20), ball(.ring30)], context: .init())
        // cherry on 10 pays its flat chip bonus even without a match
        #expect(f.chips == 10 + 20 + 30 + Symbol.cherry.flatChips)
        #expect(f.mult == 1)
        #expect(f.total == f.chips)
    }

    @Test func pairAddsMult() {
        let f = scoreFrame([ball(.ring30), ball(.ring30), ball(.ring20)], context: .init())
        #expect(f.payline == .pair(.bell))
        #expect(f.mult == 1 + Symbol.bell.pairMult)
    }

    @Test func jackpotTripleSevens() {
        let f = scoreFrame([ball(.ring50), ball(.ring50), ball(.ring50)], context: .init())
        #expect(f.payline == .triple(.seven))
        #expect(f.total == 150 * Int(1 + Symbol.seven.tripleMult))
        #expect(f.isJackpot)
    }

    @Test func gutterIsBlankAndZero() {
        let f = scoreFrame([ball(.gutter), ball(.gutter), ball(.gutter)], context: .init())
        #expect(f.total == 0)
    }

    @Test func feverDoublesTheFrame() {
        let plain = scoreFrame([ball(.ring40), ball(.ring30), ball(.ring20)], context: .init())
        let hot = scoreFrame([ball(.ring40), ball(.ring30), ball(.ring20)], context: .init(fever: true))
        #expect(hot.total == plain.total * 2)
    }

    @Test func stepsExplainTheTotal() {
        let f = scoreFrame([ball(.ring50), ball(.ring10), ball(.ring50)],
                           context: .init(charms: [.multBall, .heavyHand]))
        var chips = 0, mult = 0.0
        for s in f.steps {
            switch s.effect {
            case .chips(let c): chips += c
            case .mult(let m): mult += m
            case .timesMult(let x): mult *= x
            case .tickets, .note: break
            case .base(let c, let m): chips = c; mult = m
            }
        }
        #expect(chips == f.chips)
        #expect(mult == f.mult)
    }
}

@Suite("Charms")
struct CharmTests {
    func score(_ balls: [BallRecord], _ charms: [Charm], streak: Int = 0) -> FrameScore {
        scoreFrame(balls, context: .init(charms: charms, streakBefore: streak))
    }

    @Test func luckyPennyAddsMultPerCherry() {
        let base = score([ball(.ring10), ball(.ring10), ball(.ring30)], [])
        let lucky = score([ball(.ring10), ball(.ring10), ball(.ring30)], [.luckyPenny])
        #expect(lucky.mult == base.mult + 4)
    }

    @Test func heavyHandAddsChipsPerFifty() {
        let f = score([ball(.ring50), ball(.ring50), ball(.ring10)], [.heavyHand])
        let g = score([ball(.ring50), ball(.ring50), ball(.ring10)], [])
        #expect(f.chips == g.chips + 80)
    }

    @Test func gutterRatPaysForGutters() {
        let f = score([ball(.gutter), ball(.ring10), ball(.ring10)], [.gutterRat])
        let g = score([ball(.gutter), ball(.ring10), ball(.ring10)], [])
        #expect(f.chips == g.chips + 25)
    }

    @Test func ladderTriplesConsecutiveRings() {
        let f = score([ball(.ring40), ball(.ring30), ball(.ring50)], [.ladder])
        let g = score([ball(.ring40), ball(.ring30), ball(.ring50)], [])
        #expect(f.mult == g.mult * 3)
        let h = score([ball(.ring40), ball(.ring10), ball(.ring50)], [.ladder])
        #expect(h.mult == score([ball(.ring40), ball(.ring10), ball(.ring50)], []).mult)
    }

    @Test func nearMissPaysForRattles() {
        let f = score([ball(.ring30, rattles: 2), ball(.ring10), ball(.ring10, rattles: 1)], [.nearMiss])
        let g = score([ball(.ring30, rattles: 2), ball(.ring10), ball(.ring10, rattles: 1)], [])
        #expect(f.chips == g.chips + 45)
    }

    @Test func glassCannonShattersOnAGutter() {
        let clean = score([ball(.ring30), ball(.ring30), ball(.ring30)], [.glassCannon])
        #expect(clean.mult == score([ball(.ring30), ball(.ring30), ball(.ring30)], []).mult * 3)
        let broken = score([ball(.ring30), ball(.gutter), ball(.ring30)], [.glassCannon])
        #expect(broken.total == 0)
    }

    @Test func hotStreakCountsScoringBallsInARow() {
        let f = score([ball(.ring10), ball(.ring10), ball(.ring10)], [.hotStreak], streak: 4)
        let g = score([ball(.ring10), ball(.ring10), ball(.ring10)], [], streak: 4)
        #expect(f.mult == g.mult + 7) // 4 before + 3 this frame
        #expect(f.streakAfter == 7)
        let broken = score([ball(.ring10), ball(.gutter), ball(.ring10)], [.hotStreak], streak: 4)
        #expect(broken.streakAfter == 1)
    }

    @Test func hingeWhispererRewardsFolding() {
        let f = score([ball(.ring10, fold: 0.6), ball(.ring10, fold: 0.2), ball(.ring10, fold: 0.9)], [.hingeWhisperer])
        let g = score([ball(.ring10), ball(.ring10), ball(.ring10)], [])
        #expect(f.mult == g.mult + 6)
    }

    @Test func ticketMuncherPaysTickets() {
        let f = score([ball(.ring50), ball(.pocketLeft), ball(.ring10)], [.ticketMuncher])
        #expect(f.tickets == 2)
    }

    @Test func charmsApplyLeftToRight() {
        // +4 mult then x3 is not the same as x3 then +4.
        let balls = [ball(.ring40), ball(.ring30), ball(.ring50)]
        let a = score(balls, [.multBall, .ladder])
        let b = score(balls, [.ladder, .multBall])
        #expect(a.mult == (1 + 4) * 3)
        #expect(b.mult == 1 * 3 + 4)
    }
}
