import Testing
@testable import SkeeCore

@Suite("Walkthrough")
struct WalkthroughTests {
    func shot(_ hole: Hole = .ring30, slotHits: Int = 0) -> GameEvent {
        let r = simulateShot(Launch(power: 0.5, aim: 0), on: .standard)
        return .shot(r, BallRecord(hole: hole, symbol: .bell, chips: 30, slotHits: slotHits, combo: slotHits > 0 ? 1 : 0))
    }

    @Test func startsAtTheFlick() {
        let w = Walkthrough()
        #expect(w.step == .flick)
        #expect(!w.finished)
        #expect(!w.card.title.isEmpty)
    }

    @Test func aFoulStaysOnTheFlickAndSaysWhy() {
        var w = Walkthrough()
        w.observe([.fouled])
        #expect(w.step == .flick)
        #expect(w.card.body.lowercased().contains("foul"))
        w.observe([shot()])
        #expect(w.step == .symbols)
    }

    @Test func walksThroughEveryStepOnTheEventsThatTeachIt() throws {
        var w = Walkthrough()
        w.observe([shot()]); #expect(w.step == .symbols)
        w.observe([shot()]); #expect(w.step == .line)
        let frame = scoreFrame([], context: ScoringContext())
        w.observe([shot(), .frameScored(frame)]); #expect(w.step == .topSlot)
        w.observe([shot(slotHits: 1)]); #expect(w.step == .target)
        w.observe([.roundCleared(score: 90, target: 60, payout: Payout(base: 3, overkill: 0, interest: 0)), .counterOpened])
        #expect(w.step == .counter)
        w.observe([.roundStarted(.feature, target: 300)]); #expect(w.step == .prizes)
        w.gotIt()
        #expect(w.finished)
    }

    @Test func topSlotMovesOnAfterTwoMissesSoNobodyGetsStuck() {
        var w = Walkthrough(step: .topSlot)
        w.observe([shot()]); #expect(w.step == .topSlot)
        w.observe([shot()]); #expect(w.step == .target)
    }

    @Test func failingThePracticeStillEndsIt() {
        var w = Walkthrough(step: .target)
        w.observe([.roundFailed(score: 10, target: 60)])
        #expect(w.step == .prizes)
    }

    @Test func skipEndsItAnywhere() {
        var w = Walkthrough(step: .line)
        w.skip()
        #expect(w.finished)
    }

    @Test func gotItOnlyWorksOnCardsWithoutATask() {
        var w = Walkthrough()
        w.gotIt()
        #expect(w.step == .flick)
        #expect(Walkthrough(step: .prizes).card.needsTap)
        #expect(!Walkthrough(step: .flick).card.needsTap)
    }

    @Test func practiceRunIsAnEasyWarmup() {
        let s = practiceRun()
        #expect(s.round.kind == .warmup)
        #expect(s.round.target == Walkthrough.practiceTarget)
        #expect(s.round.target < newRun(seed: 1).round.target)
    }
}
