import Testing
@testable import SkeeCore

@Suite("First loadout")
struct WalkthroughTests {
    func shot() -> GameEvent {
        .shot(simulateShot(Launch(power: 0.5, aim: 0), on: .standard), BallRecord(hole: .ring30, symbol: .bell, chips: 30))
    }
    var pulled: GameEvent { .pulled(Pull(stops: [0, 0, 0], bet: .one)) }
    var frame: GameEvent { .frameScored(scoreFrame([], context: ScoringContext())) }

    /// Play the lesson through the real reducer, doing what each card asks.
    func play(_ walk: inout Walkthrough) -> [WalkthroughStep] {
        var s = practiceRun()
        var seen = [walk.step]
        var moves = 0
        while !walk.finished, moves < 200 {
            moves += 1
            if walk.card.needsTap { walk.gotIt() } else {
                let action: Action = switch walk.step {
                case .pull, .pullAgain, .lastPull: .pull(.one)
                case .counter: .leaveCounter
                default: .throwBall(Launch(power: 0.62, aim: 0))
                }
                guard case .success(let step) = apply(action, to: s) else {
                    Issue.record("\(walk.step) asked for \(action), which the rules refused")
                    return seen
                }
                s = step.state
                walk.observe(step.events)
            }
            if seen.last != walk.step { seen.append(walk.step) }
        }
        return seen
    }

    @Test func aPracticeGameTouchesEveryStepInOrder() {
        var w = Walkthrough()
        let seen = play(&w)
        #expect(w.finished)
        #expect(seen == WalkthroughStep.allCases)
    }

    @Test func oneIdeaPerCardShortEnoughToReadAtEighteenPoints() {
        for step in WalkthroughStep.allCases {
            #expect(Walkthrough(step: step).card.body.count <= 170, "\(step)")
        }
        for tip in Tip.allCases { #expect(tip.card.body.count <= 170, "\(tip)") }
    }

    @Test func nothingHappensUntilTheWelcomeIsRead() {
        var w = Walkthrough()
        #expect(w.step == .welcome && w.card.needsTap)
        w.gotIt()
        #expect(w.step == .pull)
        w.gotIt()
        #expect(w.step == .pull)
    }

    @Test func aFoulStaysOnTheFlickAndSaysWhy() {
        var w = Walkthrough(step: .flick)
        w.observe([.fouled])
        #expect(w.step == .flick)
        #expect(w.card.body.lowercased().contains("line"))
        w.observe([shot()])
        #expect(w.step == .symbols)
    }

    @Test func threeFoulsStillReachScoring() {
        var w = Walkthrough(step: .flick)
        w.observe([.fouled]); w.observe([.fouled]); w.observe([.fouled, frame])
        #expect(w.step == .score)
    }

    @Test func aFreeGameThatPullsTheLeverIsNotWaitedFor() {
        var w = Walkthrough(step: .line)
        w.observe([frame, pulled])
        #expect(w.step == .score)
        w.gotIt()
        #expect(w.step == .topSlot)
    }

    @Test func aRoundThatEndsEarlyStillEndsTheLesson() {
        var w = Walkthrough(step: .topSlot)
        w.observe([.roundFailed(score: 0, target: 60)])
        #expect(w.step == .prizes)
        w.gotIt()
        #expect(w.finished)
    }

    @Test func gotItOnlyWorksOnCardsWithoutATask() {
        var w = Walkthrough(step: .flick)
        w.gotIt()
        #expect(w.step == .flick && !w.finished)
    }

    @Test func skipEndsItAnywhere() {
        var w = Walkthrough(step: .symbols)
        w.skip()
        #expect(w.finished)
    }

    @Test func practiceRunIsAnEasyWarmup() {
        let s = practiceRun()
        #expect(s.round.target == Walkthrough.practiceTarget)
    }

    @Test func theLessonIsOnlyTheBasics() {
        #expect(WalkthroughStep.allCases.count <= 12)
        let words = WalkthroughStep.allCases.map { Walkthrough(step: $0).card.body }.joined(separator: " ").lowercased()
        for later in ["hot spot", "fever", "jackpot", "boss", "combo", "marshmallow"] { #expect(!words.contains(later), "\(later)") }
    }

    var game: RunState { practiceRun() }
    func hit(hot: Bool = false, slot: Int = 0) -> GameEvent {
        .shot(simulateShot(Launch(power: 0.5, aim: 0), on: .standard),
              BallRecord(hole: .ring30, symbol: .bell, chips: 30, slotHits: slot, hot: hot))
    }

    @Test func tipsComeOnceEach() {
        let events: [GameEvent] = [.feverLit, .roundFailed(score: 0, target: 1)]
        #expect(Tip.next(after: events, in: game, seen: []) == .fever)
        #expect(Tip.next(after: events, in: game, seen: [.fever]) == .gameOver)
        #expect(Tip.next(after: events, in: game, seen: [.fever, .gameOver]) == nil)
    }

    @Test func theFirstMatchTeachesTheCombo() {
        #expect(Tip.next(after: [hit()], in: game, seen: []) == nil)
        #expect(Tip.next(after: [hit(slot: 1)], in: game, seen: []) == .combo)
    }

    @Test func theHotSpotWaitsForTheSecondRoundUnlessItIsHit() {
        var later = game
        later.round.kind = .feature
        #expect(Tip.next(after: [pulled], in: game, seen: []) == nil)
        #expect(Tip.next(after: [pulled], in: later, seen: []) == .hotSpot)
        #expect(Tip.next(after: [hit(hot: true)], in: game, seen: []) == .hotSpot)
    }

    @Test func betsComeOnTheSecondAnteOrTheSecondGameAndBallsARoundLater() {
        var ante2 = game
        ante2.ante = 2
        #expect(Tip.next(after: [frame], in: game, seen: []) == nil)
        #expect(Tip.next(after: [frame], in: ante2, seen: []) == .bets)
        #expect(Tip.next(after: [frame], in: game, seen: [.gameOver]) == .bets)
        let round: GameEvent = .roundStarted(.feature, target: 9)
        #expect(Tip.next(after: [round], in: ante2, seen: []) == nil)
        #expect(Tip.next(after: [round], in: ante2, seen: [.bets]) == .balls)
    }

    @Test func cardsThatCanWaitDoNotCrowdEachOther() {
        #expect(Tip.next(after: [hit(slot: 1)], in: game, seen: [], sinceLast: 2) == nil)
        #expect(Tip.next(after: [hit(slot: 1)], in: game, seen: [], sinceLast: Tip.gap) == .combo)
        // A jackpot happens when it happens.
        #expect(Tip.next(after: [.jackpot(.mini)], in: game, seen: [], sinceLast: 0) == .jackpot)
    }

    @Test func buyingThingsExplainsThem() {
        #expect(Tip.next(after: [.bought(.charm(.multBall))], in: game, seen: []) == .charm)
        #expect(Tip.next(after: [.bought(.powerUp(.hold))], in: game, seen: []) == .specialty)
        #expect(Tip.next(after: [.bought(.gild)], in: game, seen: []) == .boardEdit)
    }
}

@Suite("The door and the Guide")
struct ArrivalTests {
    @Test func theFirstHaggleCannotGoBadly() {
        var h = Haggle(room: .boardwalk, seed: 3, visit: .arrival)
        #expect(h.patience == Haggle.maxPatience)
        for _ in 0..<8 {
            h.say("give me everything")
            h.hear(HostReply(say: "No.", offer: .init(nights: 1, tickets: 0, credit: 0), mood: -1, walk: true))
        }
        #expect(h.status == .open)
        #expect(h.patience == 1)
    }

    @Test func aFriendlyAskAlwaysMovesTheFirstOffer() {
        var h = Haggle(room: .boardwalk, seed: 3, visit: .arrival)
        var last = h.offer.value
        for _ in 0..<3 {
            h.say("one more night, please?")
            h.hear(HostReply(say: "Welcome!", offer: .init(nights: h.offer.nights, tickets: h.offer.tickets, credit: h.offer.credit), mood: 1))
            #expect(h.offer.value > last)
            #expect(h.offer.value <= h.budget)
            last = h.offer.value
        }
    }

    @Test func rudenessDoesNotMoveIt() {
        var h = Haggle(room: .boardwalk, seed: 3, visit: .arrival)
        let before = h.offer
        h.say("give me everything now")
        h.hear(HostReply(say: "Easy there.", offer: .init(nights: 1, tickets: 0, credit: 0), mood: -1))
        #expect(h.offer == before)
    }

    @Test func otherVisitsStayHardToMove() {
        var h = Haggle(room: .boardwalk, seed: 3, visit: .returning)
        let before = h.offer
        h.say("hello")
        h.hear(HostReply(say: "Hi.", offer: .init(nights: 1, tickets: 0, credit: 0), mood: 0))
        #expect(h.offer == before)
    }

    @Test func theFirstDealIsGenerousAndDoesNotCountAsAVisit() {
        var w = Wallet()
        w.gamePlayed()
        var h = Haggle(room: .boardwalk, seed: 3, visit: .arrival)
        #expect(h.budget > Comp.opening(.boardwalk).value + (Comp.ceiling(.boardwalk).value - Comp.opening(.boardwalk).value) / 2)
        h.say("please")
        h.hear(HostReply(say: "Sure.", offer: .init(nights: 2, tickets: 1, credit: 0), mood: 1))
        h.accept()
        w.close(h)
        #expect(w.comps[.boardwalk]?.nights == 2)
        #expect(w.hostVisits == 0 && w.gamesSinceHost == 1)
    }

    @Test func theFirstDealLeavesAPlayerInTheirRoom() {
        var w = Wallet()
        w.rooms.insert(.neonLounge)
        w.room = .neonLounge
        var h = Haggle(room: .boardwalk, seed: 3, visit: .arrival)
        h.accept()
        w.close(h)
        #expect(w.room == .neonLounge)
    }

    @Test func theModelIsToldThisIsABeginner() {
        let prompt = Haggle(room: .boardwalk, seed: 3, visit: .arrival).messages[0].content
        #expect(prompt.contains("brand-new guest"))
        #expect(prompt.contains("Never walk"))
    }

    @Test func theGuideStartsSmallAndGrows() {
        #expect(Guide.topics(seen: []).count == 5)
        #expect(Guide.all.count <= 13)
        let more = Guide.topics(seen: [.combo])
        #expect(more.count == 6 && more.last?.title == "Targets and Combos")
        #expect(Guide.topics(seen: Set(Tip.allCases)).count == Guide.all.count)
    }

    @Test func everyGuidePageFitsOnOneScreen() {
        for topic in Guide.all {
            #expect(!topic.pages.isEmpty)
            for page in topic.pages { #expect(page.count <= 330, "\(topic.title): \(page.count)") }
        }
    }

    @Test func theGuideListsEveryItemByName() {
        let all = Guide.all.flatMap(\.pages).joined(separator: " ")
        for c in Charm.allCases { #expect(all.contains(c.name)) }
        for p in PowerUp.allCases { #expect(all.contains(p.name)) }
        for b in BallKind.allCases { #expect(all.contains(b.name)) }
        for b in Boss.allCases { #expect(all.contains(b.name)) }
        for r in Room.allCases.dropFirst() { #expect(all.contains(r.name)) }
    }
}
