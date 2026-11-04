/// The first loadout: a short practice game with a coach, for the basics
/// only: pull, roll, match, score, beat the target, spend tickets. Each step
/// teaches one thing. Some wait for the player to do it, read off the same
/// events the shell already gets; some are a card to read and tap. Skip
/// ends it anywhere. Everything else waits for real play: see `Tip`.
///
/// It teaches by doing because the rules only click once a ball has
/// dropped: "the ball takes the hole's symbol" is abstract on a slide and
/// obvious the moment the cherry appears in the reel.
public enum WalkthroughStep: Int, Hashable, Sendable, Codable, CaseIterable {
    case welcome, pull, flick, symbols, line, score
    case pullAgain, topSlot, lastPull, finish, counter, prizes

    /// Waiting for the lever. A free game pulls it for you, so these can
    /// be passed over.
    var wantsPull: Bool { self == .pull || self == .pullAgain || self == .lastPull }
}

public struct CoachCard: Hashable, Sendable {
    public var title: String
    public var body: String
    /// No task to do: the card waits for a tap on GOT IT.
    public var needsTap: Bool
    /// Where the card should sit so it doesn't cover what it's about.
    public var high: Bool
}

public struct Walkthrough: Hashable, Sendable, Codable {
    public static let practiceTarget = 60

    public private(set) var step: WalkthroughStep
    public private(set) var finished = false
    var lastWasFoul = false
    /// A free game has already pulled the next frame's lever.
    var pulledAhead = false

    public init(step: WalkthroughStep = .welcome) { self.step = step }

    public mutating func observe(_ events: [GameEvent]) {
        guard !finished else { return }
        for e in events {
            switch (step, e) {
            case (.pull, .pulled): go(.flick)
            case (.pullAgain, .pulled): go(.topSlot)
            case (.lastPull, .pulled): go(.finish)
            case (_, .pulled): pulledAhead = true
            case (.flick, .fouled): lastWasFoul = true
            case (.flick, .shot): go(.symbols)
            case (.symbols, .shot), (.symbols, .fouled): go(.line)
            case (.flick, .frameScored), (.symbols, .frameScored), (.line, .frameScored): go(.score)
            case (.topSlot, .frameScored): go(.lastPull)
            case (.counter, .roundStarted): go(.prizes)
            case (_, .counterOpened): go(.counter)
            case (_, .roundFailed): go(.prizes)
            default: break
            }
        }
    }

    /// Dismiss a card that has no task: on to the next step, or done.
    public mutating func gotIt() {
        guard card.needsTap else { return }
        guard var next = WalkthroughStep(rawValue: step.rawValue + 1) else { finished = true; return }
        if next.wantsPull, pulledAhead, let after = WalkthroughStep(rawValue: next.rawValue + 1) {
            pulledAhead = false
            next = after
        }
        go(next)
    }

    public mutating func skip() { finished = true }

    mutating func go(_ s: WalkthroughStep) {
        step = s; lastWasFoul = false
    }

    public var card: CoachCard {
        switch step {
        case .welcome:
            CoachCard(title: "YOUR FIRST LOADOUT", body: "This is a practice game. It doesn't count, you can't get it wrong, and nobody's in a hurry. We'll just cover the basics.", needsTap: true, high: false)
        case .pull:
            CoachCard(title: "PULL THE LEVER", body: "Every turn starts at the slot machine. Drag the lever down, or tap SPIN.", needsTap: false, high: true)
        case .flick:
            lastWasFoul
                ? CoachCard(title: "THAT WAS A FOUL", body: "Your thumb went past the line, so that ball didn't count. No harm done. Start lower, flick, and let go before the line.", needsTap: false, high: false)
                : CoachCard(title: "ROLL THE BALL", body: "Put your thumb on the dotted line, flick straight up and let go. A faster flick rolls farther. Don't worry about aiming yet.", needsTap: false, high: false)
        case .symbols:
            CoachCard(title: "EVERY HOLE HAS A PICTURE", body: "Your ball took the picture of the hole it landed in. Look for it in the row of three. Roll another.", needsTap: false, high: false)
        case .line:
            CoachCard(title: "THREE BALLS, ONE LINE", body: "Your three balls make a slot line, just like three reels. Two matching pictures pay well. Three pay big. Roll your last ball.", needsTap: false, high: false)
        case .score:
            CoachCard(title: "HOW SCORING WORKS", body: "Holes pay chips, and the far ones pay most. Matches raise your multiplier. Your score for the turn is chips times multiplier.", needsTap: true, high: false)
        case .pullAgain:
            CoachCard(title: "NEXT TURN", body: "Pull again. This time, watch the middle row of the machine.", needsTap: false, high: true)
        case .topSlot:
            CoachCard(title: "AIM FOR YOUR PICTURES", body: "The middle row is now at the top of the screen: your targets. Holes showing those pictures glow. Try to hit one.", needsTap: false, high: false)
        case .lastPull:
            CoachCard(title: "LAST TURN", body: "One more turn in this round. Pull the lever.", needsTap: false, high: true)
        case .finish:
            CoachCard(title: "BEAT THE TARGET", body: "The goal of every round is the target score at the top of the screen. Reach it before your balls run out. Roll your last three.", needsTap: false, high: false)
        case .counter:
            CoachCard(title: "THE PRIZE COUNTER", body: "Clearing a round pays tickets. Spend them here on things that help, or save them. Tap NEXT ROUND when you're ready.", needsTap: false, high: true)
        case .prizes:
            CoachCard(title: "THAT'S ALL YOU NEED", body: "Now for a real game. There's more to discover, and I'll show you each new thing as it comes up. Have fun!", needsTap: true, high: false)
        }
    }
}

/// One card, the first time something comes up in a real game. This is how
/// the game teaches past the basics: the lesson stays short, and a new idea
/// arrives when there's a reason to care about it. Bets, the ball rack and
/// the Hot Spot ring stay hidden until their card has been seen, and the
/// Guide lists a topic only once it has been met.
public enum Tip: String, Hashable, Sendable, Codable, CaseIterable {
    case combo, hotSpot, charm, specialty, boardEdit, boss, bets, balls
    case fever, freeGames, jackpot, gameOver

    /// Balls that must go by after one card before a card that can wait.
    public static let gap = 6

    /// These come up again if they're held back. The rest happen once, so
    /// they're shown when they happen.
    var canWait: Bool {
        switch self {
        case .combo, .hotSpot, .bets, .balls: true
        default: false
        }
    }

    /// The first unseen tip these events raise.
    /// - Parameter sinceLast: balls thrown since the last card.
    public static func next(after events: [GameEvent], in s: RunState, seen: Set<Tip>, sinceLast: Int = .max) -> Tip? {
        events.lazy.compactMap { raised(by: $0, in: s, seen: seen) }
            .first { !seen.contains($0) && (!$0.canWait || sinceLast >= gap) }
    }

    static func raised(by e: GameEvent, in s: RunState, seen: Set<Tip>) -> Tip? {
        switch e {
        case .shot(_, let b) where b.hot: return .hotSpot
        case .shot(_, let b) where b.slotHits > 0: return .combo
        case .pulled where s.round.kind != .warmup || s.ante > 1: return .hotSpot
        case .bought(.charm): return .charm
        case .bought(.powerUp): return .specialty
        case .bought: return .boardEdit
        case .roundStarted(.boss, _): return .boss
        // Bets once there's a second ante, or a second game; balls a round later.
        case .frameScored where s.ante > 1 || seen.contains(.gameOver): return .bets
        case .roundStarted where seen.contains(.bets): return .balls
        case .feverLit: return .fever
        case .freeGamesWon: return .freeGames
        case .jackpot: return .jackpot
        case .roundFailed: return .gameOver
        default: return nil
        }
    }

    public var card: CoachCard {
        switch self {
        case .combo:
            CoachCard(title: "A COMBO!", body: "That ball matched one of your targets. Keep matching, ball after ball, and each one adds more to your score. A miss ends it.", needsTap: true, high: false)
        case .hotSpot:
            CoachCard(title: "THE HOT SPOT", body: "See the sparkling gold ring on the board? That hole pays double this turn. Every pull moves it.", needsTap: true, high: false)
        case .charm:
            CoachCard(title: "YOUR FIRST CHARM", body: "Charms work by themselves for the rest of the game. There's nothing to do. Yours sit down the left side of the screen.", needsTap: true, high: true)
        case .specialty:
            CoachCard(title: "A SPECIALTY BALL", body: "Tap it at the side of the screen when you want it, then throw. It only works on that one ball, so save it for a good moment.", needsTap: true, high: true)
        case .boardEdit:
            CoachCard(title: "YOUR OWN BOARD", body: "That change stays on the board until this game ends. Shaping the holes to suit you is how big scores get built.", needsTap: true, high: true)
        case .boss:
            CoachCard(title: "A BOSS MACHINE", body: "The third round of every ante bends one rule. This machine's rule is written at the top of the screen. Beat it to reach the next ante.", needsTap: true, high: false)
        case .bets:
            CoachCard(title: "BIGGER BETS", body: "The machine has new buttons. Betting 3 or 5 lines costs tickets but wins more, and only 5 lines can hit a jackpot. 1 line is always free.", needsTap: true, high: true)
        case .balls:
            CoachCard(title: "PICK YOUR BALL", body: "You can now swap balls for free before any throw. Marshmallow is the easiest. Wilder balls are harder and pay more.", needsTap: true, high: true)
        case .fever:
            CoachCard(title: "FEVER!", body: "Rattles and gutter balls filled the meter, so your next turn scores double. Even a bad roll helps.", needsTap: true, high: false)
        case .freeGames:
            CoachCard(title: "FREE GAMES!", body: "Three BONUS pictures won you extra turns. The machine pulls for you, and they score double.", needsTap: true, high: false)
        case .jackpot:
            CoachCard(title: "JACKPOT!", body: "You hit a jackpot meter. It goes straight into your winnings for the prize shop, and you keep it whatever happens next.", needsTap: true, high: false)
        case .gameOver:
            CoachCard(title: "NOT TO WORRY", body: "Every game ends sooner or later. Your winnings are saved for the prize shop, and the next game starts fresh. Sal looks after people who come back.", needsTap: true, high: false)
        }
    }
}

/// What Sal says at the door, one line per tap, before the first haggle.
public enum Arrival {
    public static let beats = [
        "Well, look who walked in! I'm Sal. I run the Boardwalk Arcade.",
        "Welcome to Skee Skee Skee. It's half arcade ball-rolling and half slot machine. And it's all for fun: there's no real money here, ever.",
        "You roll balls up a ramp into glowing rings. Every ring shows a picture, and matching pictures make your score climb.",
        "Nobody rushes you here. Take as long as you like on every throw.",
        "One more thing. Around here, everything's negotiable! So let's talk about what you walk in with: your first loadout.",
    ]
}

/// The walkthrough's warm-up: a fixed seed and a low target, so a first
/// try clears it and sees the prize counter.
/// The practice round is played in whatever room the cabinet is: the
/// physics has to match the board on screen.
public func practiceRun(room: Room = .boardwalk) -> RunState {
    var s = newRun(seed: 2024, room: room)
    s.round.target = Walkthrough.practiceTarget
    return s
}
