/// The walkthrough: a practice warm-up with a coach. Each step teaches one
/// thing and waits until the player has done it, read off the same events
/// the shell already gets. Skip ends it from any step.
///
/// It teaches by doing because the rules only click once a ball has
/// dropped: "the ball takes the hole's symbol" is abstract on a slide and
/// obvious the moment the cherry appears in the reel.
public enum WalkthroughStep: Int, Hashable, Sendable, Codable, CaseIterable {
    case flick, symbols, line, topSlot, target, counter, prizes
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
    /// Throws seen on this step; the top slot step gives up after two.
    var throwsHere = 0
    var lastWasFoul = false

    public init(step: WalkthroughStep = .flick) { self.step = step }

    public mutating func observe(_ events: [GameEvent]) {
        guard !finished else { return }
        for e in events {
            switch (step, e) {
            case (.flick, .fouled):
                lastWasFoul = true
            case (.flick, .shot), (.symbols, .shot):
                go(WalkthroughStep(rawValue: step.rawValue + 1)!)
            case (.line, .frameScored):
                go(.topSlot)
            case (.topSlot, .shot(_, let b)):
                throwsHere += 1
                if b.slotHits > 0 || throwsHere >= 2 { go(.target) }
            case (.topSlot, .fouled):
                throwsHere += 1
                if throwsHere >= 2 { go(.target) }
            case (_, .roundFailed):
                go(.prizes)
            case (.target, .counterOpened), (.topSlot, .counterOpened), (.line, .counterOpened):
                go(.counter)
            case (.counter, .roundStarted):
                go(.prizes)
            default:
                break
            }
        }
    }

    /// Dismiss a card that has no task.
    public mutating func gotIt() {
        guard card.needsTap else { return }
        finished = true
    }

    public mutating func skip() { finished = true }

    mutating func go(_ s: WalkthroughStep) {
        step = s; throwsHere = 0; lastWasFoul = false
    }

    public var card: CoachCard {
        switch step {
        case .flick:
            lastWasFoul
                ? CoachCard(title: "FOUL", body: "That was a foul: your thumb went past the line. Flick and let go before it; the ball does the rest.", needsTap: false, high: false)
                : CoachCard(title: "FLICK IT", body: "Swipe up the lane and let go. A faster flick rolls farther. Aim for the middle.", needsTap: false, high: false)
        case .symbols:
            CoachCard(title: "HOLES ARE REELS", body: "Every hole shows a symbol. Your ball takes the symbol of the hole it drops in. Throw again.", needsTap: false, high: false)
        case .line:
            CoachCard(title: "3 BALLS = 1 LINE", body: "Three balls make a slot line. Two alike pay MULT, three alike pay big. Glowing rings would match.", needsTap: false, high: false)
        case .topSlot:
            CoachCard(title: "THE TOP SLOT", body: "It spins every throw. Hit a hole showing one of its symbols for a COMBO; keep hitting to grow it. Cyan rings match.", needsTap: false, high: false)
        case .target:
            CoachCard(title: "BEAT THE TARGET", body: "Score = chips x mult. Reach the target at the top before your balls run out.", needsTap: false, high: false)
        case .counter:
            CoachCard(title: "PRIZE COUNTER", body: "Clearing a round pays tickets. Charms change how you score for the rest of the run. Leave when you're ready.", needsTap: false, high: true)
        case .prizes:
            CoachCard(title: "THAT'S THE GAME", body: "Each run has 8 antes and a boss each. Finished runs pay winnings for the prize shop. Prizes are just for show.", needsTap: true, high: false)
        }
    }
}

/// The walkthrough's warm-up: a fixed seed and a low target, so a first
/// try clears it and sees the prize counter.
public func practiceRun() -> RunState {
    var s = newRun(seed: 2024)
    s.round.target = Walkthrough.practiceTarget
    return s
}
