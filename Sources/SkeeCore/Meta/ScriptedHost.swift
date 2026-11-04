/// The host without a model: the fallback when the phone is offline, the
/// relay's limit is hit, or the player said no to AI chat.
///
/// It reads the player's last line for three things (which perk they named,
/// whether they were nice, whether they were rude) and writes a line from
/// the host's own phrasebook. It doesn't understand a sentence, so it never
/// pretends to answer one: every reply is about the offer.
///
/// The obvious version picks a line and lets `hear` clamp the offer, which
/// has the host announce a second night the budget then takes away. So the
/// line is chosen after `within` has settled what's really on the table.
extension Haggle {
    enum Perk: CaseIterable { case nights, tickets, credit }

    /// What the host says next, from the transcript alone. Deterministic.
    public var scriptedReply: HostReply {
        let said = lines.last(where: { $0.speaker == .player })?.text ?? ""
        let words = Self.words(said)
        let turn = lines.filter { $0.speaker == .player }.count
        let book = Phrasebook.of(room)

        let rude = !words.isDisjoint(with: Self.rudeWords)
        let nice = !rude && !words.isDisjoint(with: Self.niceWords)
        let repeated = lines.filter { $0.speaker == .player }.dropLast().last.map { Self.words($0.text) == words } ?? false
        let mood = rude ? -1 : nice ? 1 : 0
        let terms = { (c: Comp) in HostReply.Terms(nights: c.nights, tickets: c.tickets, credit: c.credit) }
        let welcome = visit == .arrival

        if let concern = HostGuard.screen(said) { return deflection(concern, book, turn) }

        // Saying yes is not a push: nothing moves, and it costs no patience.
        if !rude, !words.isDisjoint(with: Self.yesWords) {
            return HostReply(say: "Then tap DEAL and it's done.", offer: terms(offer), mood: 1)
        }

        let leaving = !welcome && patience - 1 + mood <= 0
        if leaving {
            return HostReply(say: book.goodbye, offer: terms(offer), mood: mood, walk: true)
        }
        if rude {
            return HostReply(say: Self.pick(book.rude, turn), offer: terms(offer), mood: welcome ? 0 : -1)
        }
        if repeated, !welcome {
            return HostReply(say: Self.pick(book.repeated, turn), offer: terms(offer), mood: 0)
        }

        // What would really be on the table if this perk went up.
        let asked = Perk.allCases.filter { !words.isDisjoint(with: Self.perkWords($0)) }
        let order = asked + Self.rotation(turn).filter { !asked.contains($0) }
        for perk in order {
            let next = within(raised(perk))
            guard next.value > offer.value else { continue }
            let warning = !welcome && patience - 1 + mood == 1 ? " " + book.lastWord : ""
            return HostReply(say: Self.line(perk, next, book, turn) + warning, offer: terms(next), mood: mood)
        }
        return HostReply(say: welcome ? "That's the best I've got, and it's a good one. Tap DEAL." : Self.pick(book.limit, turn),
                         offer: terms(offer), mood: mood)
    }

    func raised(_ perk: Perk) -> Comp {
        var c = offer
        switch perk {
        case .nights: c.nights += 1
        case .tickets: c.tickets += 1
        case .credit: c.credit += 100
        }
        return c
    }

    static func rotation(_ turn: Int) -> [Perk] {
        let all = [Perk.tickets, .nights, .credit]
        return (0..<3).map { all[(turn + $0) % 3] }
    }

    static func line(_ perk: Perk, _ c: Comp, _ book: Phrasebook, _ turn: Int) -> String {
        let opener = pick(book.yes, turn)
        return switch perk {
        case .nights: "\(opener) \(c.nights) nights."
        case .tickets: "\(opener) \(c.tickets) bonus \(c.tickets == 1 ? "ticket" : "tickets") a night."
        case .credit: "\(opener) \(c.credit) in prize credit."
        }
    }

    static func pick(_ from: [String], _ turn: Int) -> String { from[turn % from.count] }

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init))
    }

    static func perkWords(_ perk: Perk) -> Set<String> {
        switch perk {
        case .nights: ["night", "nights", "stay", "longer", "days"]
        case .tickets: ["ticket", "tickets"]
        case .credit: ["credit", "credits", "money", "cash", "prize", "prizes", "winnings"]
        }
    }

    static let niceWords: Set<String> = ["please", "thanks", "thank", "love", "lovely", "nice", "great", "wonderful",
                                         "beautiful", "handsome", "friend", "kind", "sweet", "best", "amazing", "pretty", "haha", "lol"]
    static let rudeWords: Set<String> = ["stupid", "idiot", "dumb", "cheap", "cheapskate", "hate", "sucks", "suck", "shut",
                                         "crook", "liar", "loser", "ugly", "damn", "hell", "crap", "jerk"]
    static let yesWords: Set<String> = ["deal", "ok", "okay", "yes", "yep", "sure", "agreed", "done", "sold"]
}

/// How each host talks, one voice apiece.
struct Phrasebook {
    var yes: [String]
    var limit: [String]
    var repeated: [String]
    var rude: [String]
    var lastWord: String
    var goodbye: String
    var offTopic: [String]

    static func of(_ room: Room) -> Phrasebook {
        switch room {
        case .boardwalk:
            Phrasebook(yes: ["You drive a hard bargain! Okay:", "Ah, why not. For you:", "My wife'll kill me, but sure:"],
                       limit: ["That's all I've got, friend.", "Any more and they take the boardwalk from me."],
                       repeated: ["You said that already, friend. Try me with something new."],
                       rude: ["Hey, easy now. We're all friends here.", "That's no way to talk at my arcade."],
                       lastWord: "That's my last word. Tap DEAL.",
                       goodbye: "All right, that's enough for me. Enjoy your night, friend.",
                       offTopic: ["Not my department, friend. Let's talk nights, tickets and credit.", "I just run the arcade. So, what'll it take to make this deal?"])
        case .neonLounge:
            Phrasebook(yes: ["Mm. I've heard worse. Fine:", "You're lucky I like you:", "Cute. All right:"],
                       limit: ["That's the ceiling, darling.", "I've run out of favours tonight."],
                       repeated: ["Once was enough, darling."],
                       rude: ["Careful. I've thrown out better than you.", "Charming. Try again."],
                       lastWord: "That's nearly all you'll get from me. Tap DEAL.",
                       goodbye: "I've a lounge to run. Good night.",
                       offTopic: ["Not a subject for my lounge, darling. Back to the deal.", "Let's keep to business. Nights, tickets or credit?"])
        case .highRoller:
            Phrasebook(yes: ["Very good. I can arrange it:", "A reasonable request:", "If you insist:"],
                       limit: ["I regret that's the limit of my discretion.", "I'm afraid the house can go no further."],
                       repeated: ["I did hear you the first time."],
                       rude: ["We don't speak that way in this room.", "I'll pretend I didn't hear that."],
                       lastWord: "I would accept now, if I were you.",
                       goodbye: "I believe we're finished here. Good evening.",
                       offTopic: ["That's not a matter for this room. Shall we return to your stay?", "I couldn't say. May we discuss your comp?"])
        case .penthouse:
            Phrasebook(yes: ["For you, a star among stars:", "Oh, you wonderful creature:", "How could I refuse?"],
                       limit: ["Even a penthouse has a ceiling, my dear.", "Not one thing more, my treasure."],
                       repeated: ["My dear, you're repeating yourself."],
                       rude: ["Such words, in my penthouse!", "My dear, that was beneath you."],
                       lastWord: "Sign, my dear, before the moment passes.",
                       goodbye: "The curtain falls, my dear. Farewell.",
                       offTopic: ["Such a curious thing to say, my dear. Now, your stay!", "Let us speak only of your comp, my treasure."])
        }
    }
}
