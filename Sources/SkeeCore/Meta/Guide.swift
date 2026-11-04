/// The Guide: how each part of the game works, in plain words, for when a
/// card has gone by and you'd like to read it again. It only lists what
/// you've met, so it starts small and grows with you. Numbers and lists come
/// from the rules themselves, so a change to a charm or a price can't leave
/// a page telling a different story.
public struct GuideTopic: Hashable, Sendable {
    public var title: String
    /// One screen each, so the words can be large and nothing scrolls.
    public var pages: [String]
    /// Any of these unlocks it. Empty: there from the start.
    public var unlocks: Set<Tip> = []
}

public enum Guide {
    /// What this player has met so far.
    public static func topics(seen: Set<Tip>) -> [GuideTopic] {
        all.filter { $0.unlocks.isEmpty || !$0.unlocks.isDisjoint(with: seen) }
    }

    public static var all: [GuideTopic] {
        let c = RunConfig.standard
        return [
            GuideTopic(title: "The Big Idea", pages: [
                "You roll balls into holes to reach a target score. Beat the target and you move on to the next round.",
                "A game has \(c.antes) antes, which are like levels. Each ante has 3 rounds: a warm-up, a feature game and a boss machine.",
                "Each round gives you \(c.framesPerRound) frames, and a frame is one turn of \(c.ballsPerFrame) balls. Miss a target and that game is over, but your winnings are saved.",
            ]),
            GuideTopic(title: "Rolling the Ball", pages: [
                "Put your thumb on the dotted line, flick up and let go. Where you put your thumb is where the ball goes, and a faster flick rolls farther.",
                "If your thumb crosses the line on the lane, that's a foul: the ball is used up and scores nothing. Flick and let go early.",
                "The ball rolls up the lane, over the hump and onto the board. On a folding phone, folding it lofts the ball higher off the hump.",
            ]),
            GuideTopic(title: "The Lever", pages: [
                "Every frame starts with a pull. The middle row becomes the frame's targets, the pictures you want to hit.",
            ]),
            GuideTopic(title: "Scoring", pages: [
                "The rings pay \(Hole.ring10.faceValue), \(Hole.ring20.faceValue), \(Hole.ring30.faceValue), \(Hole.ring40.faceValue) and \(Hole.ring50.faceValue) chips, and the two corner pockets pay \(Hole.pocketLeft.faceValue). The gutter pays nothing.",
                "Every hole also shows a picture, and your ball takes that picture. The pictures change after every ball, so look before you throw.",
                "A frame's three balls read as a slot line. A pair or three alike raises your multiplier. Cherries also add \(Symbol.cherry.flatChips) chips each, matched or not.",
                (["What matches add to your multiplier:"] + [Symbol.cherry, .lemon, .bell, .bar, .clover, .seven, .diamond].map {
                    "\(label($0)): pair +\(num($0.pairMult)), three +\(num($0.tripleMult))"
                }).joined(separator: "\n"),
                "The clover is wild and matches anything except a blank.",
                "A frame scores chips times multiplier. Chips come from holes, cherries and line wins. The multiplier starts at 1 and everything else raises it.",
                "That's why a small hole with a good match can beat a big hole with none. Three frames add up to your round score.",
            ]),
            GuideTopic(title: "Tickets and the Counter", pages: [
                "Tickets are for this game only. You start with \(c.startTickets). Clearing a round pays \(c.roundTickets[.warmup]!), \(c.roundTickets[.feature]!) or \(c.roundTickets[.boss]!), and a boss pays the most.",
                "Beat the target by half again and you get a bonus ticket, up to \(c.overkillCap). You also get 1 for every \(c.interestPer) you're holding, up to \(c.interestCap), so saving pays.",
                "After each round you can spend tickets. You can hold \(c.charmSlots) charms and \(c.powerUpSlots) specialty balls. Charms sell back for half. Rerolling shows new offers, and costs more each time.",
                "Stamp puts a picture on a hole you pick. Gild adds \(Offer.gildAmount) chips to a hole for good. Purge removes the picture a hole is showing. Tap the item, then tap the hole.",
            ]),
            GuideTopic(title: "Targets and Combos", pages: [
                "A ball showing one of the frame's targets adds to your multiplier and starts a combo. The next match in a row adds more, up to level \(TopSlot.maxLevel).",
                "A throw that misses the targets ends the combo. A ball that matches all three targets also pays \(TopSlot.jackpotTickets) tickets.",
            ], unlocks: [.combo]),
            GuideTopic(title: "Hot Spot and Fever", pages: [
                "After each pull one hole sparkles with a gold ring. A ball in it pays double chips until the next pull. It's never the 10.",
                "Every rattle on a rim and every gutter ball adds heat to the meter. At \(c.feverHeat) heat, the next frame's multiplier is doubled.",
            ], unlocks: [.hotSpot, .fever]),
            GuideTopic(title: "Bets and Free Games", pages: [
                "Bet 1, 3 or 5 lines for \(Bet.one.cost), \(Bet.three.cost) or \(Bet.five.cost) tickets. Three alike on a line you bet on adds chips to the frame, from \(ReelSymbol.cherry.linePay) for cherries up to \(ReelSymbol.wild.linePay) for wilds.",
                "Wilds stand in for any picture, and 2X and 3X wilds multiply the line. Three or more BONUS pictures anywhere win \(Pull.freeGamesAwarded) free games: extra frames that score double.",
            ], unlocks: [.bets, .freeGames]),
            list("Charms", Charm.allCases.map { "\($0.name): \($0.blurb)." }, per: 4, unlocks: [.charm]),
            list("Specialty Balls", ["Buy these at the counter for \(PowerUp.goldenBall.cost) tickets, then tap one to use it on your next throw."]
                + PowerUp.allCases.map { "\($0.name): \($0.blurb)." }, per: 3, unlocks: [.specialty]),
            list("Choosing a Ball", ["Swap for free before any throw. The number is what the ball's chips are multiplied by."]
                + BallKind.allCases.map { "\($0.name) (\($0.payLabel)): \($0.blurb)" }, per: 3, unlocks: [.balls]),
            list("Boss Machines", ["The third round of each ante bends one rule, and it's written on screen."]
                + Boss.allCases.map { "\($0.name): \($0.blurb)" }, per: 4, unlocks: [.boss]),
            GuideTopic(title: "Winnings and Hosts", pages: [
                "Winnings are kept between games. Each finished game pays 1 for every 20 points you scored, 20 for each round cleared, and 500 for beating the arcade.",
                "Spend winnings in the prize shop. Prizes are just for show and never change the game. They're there to be collected.",
                "Jackpots only pay at the 5-line bet. Three bars pay the MINI, three sevens the MINOR, three diamonds the MAJOR, and three wilds on the middle row the GRAND.",
                "The meters over the machine grow with every pull and carry over between games. A jackpot goes straight to your winnings.",
                "Every 3 or 4 games a host sits down to offer you free nights. A night is one game that starts with bonus tickets. Talk to them: charm pays, and rudeness costs patience.",
                "Win enough and the host offers a new room, yours for good, with its own board and machine: \(Room.allCases.dropFirst().map(\.name).joined(separator: ", ")). Pick your room on the title screen.",
            ], unlocks: [.gameOver, .jackpot]),
        ]
    }

    static func list(_ title: String, _ items: [String], per: Int, unlocks: Set<Tip>) -> GuideTopic {
        GuideTopic(title: title, pages: stride(from: 0, to: items.count, by: per).map {
            items[$0..<min($0 + per, items.count)].joined(separator: "\n\n")
        }, unlocks: unlocks)
    }

    static func label(_ s: Symbol) -> String { s.rawValue.prefix(1).uppercased() + s.rawValue.dropFirst() }
    static func num(_ x: Double) -> String { x == x.rounded() ? "\(Int(x))" : "\(x)" }
}
