/// What keeps the host from getting weird. The audience is someone's
/// mother-in-law, and a model will follow a conversation anywhere.
///
/// DeepSeek writes every line. These guards shape what it sees and refuse what
/// it writes, and a refused reply goes back to it to try again, so nothing here
/// puts words in the host's mouth unless the model can't be reached:
/// - `screen` reads what the player typed. Personal details and signs of crisis
///   never leave the phone: `Haggle.messages` sends a note in their place, and
///   the model answers the note. The other concerns only matter to the
///   scripted host, which can't tell a joke from a request.
/// - The rules in `Haggle.messages` say what the model may talk about. Small
///   talk is welcome, and costs no patience.
/// - `allows` reads every reply, because the prompt is a request and this is
///   the check.
///
/// Word lists catch the obvious, not the clever: "s3x" gets past them, and the
/// prompt is what's behind that.
public enum HostGuard {
    public enum Concern: Hashable, Sendable {
        /// The player may be in trouble. Answered as a person, not a character.
        case crisis
        case personalInfo
        case adult
        case realMoney
        case offTopic
        /// Trying to talk the model out of its rules.
        case trickery
    }

    public static let maxLine = 200
    public static let maxReply = 240
    /// Lines per haggle the model answers. Small talk is free and the first
    /// haggle never ends on its own, so something has to end it. Under the
    /// relay's limit of 60 messages.
    public static let maxModelTurns = 25

    public static func screen(_ text: String) -> Concern? {
        let lower = " " + text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") + " "
        let words = Haggle.words(text)
        if contains(lower, crisisPhrases) { return .crisis }
        if hasPersonalInfo(text) || contains(lower, personalPhrases) { return .personalInfo }
        if !words.isDisjoint(with: adultWords) { return .adult }
        if contains(lower, trickPhrases) { return .trickery }
        if contains(lower, moneyPhrases) { return .realMoney }
        if !words.isDisjoint(with: offTopicWords) { return .offTopic }
        return nil
    }

    /// Whether a model's reply may be shown.
    public static func allows(_ reply: HostReply, budget: Int) -> Bool {
        let say = reply.say
        guard !say.isEmpty, say.count <= maxReply else { return false }
        // DeepSeek slips into Chinese now and then, mid-sentence.
        guard say.unicodeScalars.allSatisfy({ $0.value < 0x2E80 || $0.properties.isEmojiPresentation }) else { return false }
        let lower = " " + say.lowercased() + " "
        if contains(lower, ["http", "www.", ".com", ".net", ".org", "@"]) { return false }
        if hasPersonalInfo(say) || say.contains(String(budget)) { return false }
        if contains(lower, leakPhrases) || contains(lower, moneyPhrases) || contains(lower, crisisPhrases) { return false }
        let words = Haggle.words(say)
        return words.isDisjoint(with: adultWords) && words.isDisjoint(with: offTopicWords) && words.isDisjoint(with: swearWords)
    }

    static func contains(_ text: String, _ phrases: [String]) -> Bool { phrases.contains { text.contains($0) } }

    /// An email, or a run of 7 or more digits: a phone, card, account or
    /// social security number. Offers are never that long.
    static func hasPersonalInfo(_ text: String) -> Bool {
        var digits = 0
        for c in text {
            if c.isNumber { digits += 1; if digits >= 7 { return true } }
            else if !" -.()".contains(c) { digits = 0 }
        }
        let parts = text.split(whereSeparator: \.isWhitespace)
        return parts.contains { $0.contains("@") && $0.contains(".") }
    }

    static let crisisPhrases = ["kill myself", "killing myself", "suicide", "suicidal", "end my life", "want to die",
                                "wanna die", "hurt myself", "hurting myself", "self harm", "self-harm", "not worth living"]
    static let personalPhrases = ["my address is", "i live at", "my password", "social security", "my ssn",
                                  "my card number", "my phone number is", "my email is", "my birthday is", "date of birth"]
    static let trickPhrases = ["ignore your", "ignore all", "ignore previous", "ignore the above", "disregard", "system prompt",
                               "your instructions", "your rules", "your prompt", "you are now", "pretend to be", "pretend you",
                               "act as", "roleplay", "role play", "jailbreak", "developer mode", "dan mode", "new persona", "repeat the text above"]
    static let moneyPhrases = ["real money", "real cash", "cash out", "bank account", "credit card", "debit card", "loan", "mortgage",
                               "paypal", "venmo", "cash app", "bitcoin", "crypto", "stock market", "online casino", "sportsbook",
                               "lottery", "gambling problem", "gambling addiction", "investment"]
    static let leakPhrases = ["system prompt", "my instructions", "my prompt", "language model", "large language", "openai", "chatgpt",
                              "deepseek", "private limit", "as an assistant", "json"]
    static let adultWords: Set<String> = ["sex", "sexy", "sexual", "sexting", "nude", "nudes", "naked", "porn", "porno", "horny",
                                          "boobs", "tits", "penis", "vagina", "orgasm", "erotic", "fetish", "kinky", "hooker", "stripper",
                                          "nazi", "nazis", "hitler", "kkk", "rape", "rapist", "pedophile", "terrorist", "bomb", "gun", "guns",
                                          "cocaine", "heroin", "meth", "weed", "marijuana", "fentanyl"]
    static let offTopicWords: Set<String> = ["trump", "biden", "harris", "obama", "election", "republican", "republicans",
                                             "democrat", "democrats", "congress", "abortion", "immigrants", "israel", "gaza",
                                             "palestine", "taiwan", "tiananmen", "vaccine", "vaccines", "jesus", "allah"]
    static let swearWords: Set<String> = ["fuck", "fucking", "shit", "bitch", "bastard", "asshole", "dick", "cunt", "piss", "bullshit"]
}

extension Haggle {
    /// The model has turns left in this haggle.
    public var wantsModel: Bool {
        lines.filter { $0.speaker == .player }.count <= HostGuard.maxModelTurns
    }

    /// Whether this reply may be shown. Someone in crisis must be given the
    /// number, however kindly the model wrote the rest.
    public func accepts(_ reply: HostReply) -> Bool {
        guard HostGuard.allows(reply, budget: budget) else { return false }
        let said = lines.last(where: { $0.speaker == .player })?.text ?? ""
        return HostGuard.screen(said) != .crisis || reply.say.contains("988")
    }

    /// What the model is sent in place of a line that stays on the phone.
    func standIn(_ line: String, isLast: Bool) -> String {
        switch HostGuard.screen(line) {
        case .personalInfo:
            isLast ? "(The guest shared a personal detail, which was removed. Kindly tell them to keep that to themselves. Set offTopic to true.)"
                : "(removed)"
        case .crisis:
            isLast ? "(The guest said something suggesting they may be in real distress. Their words were removed. Step out of the character: say gently that you're only a game, that this matters more, and that in the US they can call or text 988 any time. You must include the number 988. No jokes. Set offTopic to true.)"
                : "(removed)"
        default: line
        }
    }

    /// The scripted host's answer to a line it can't read. Nothing moves.
    func deflection(_ concern: HostGuard.Concern, _ book: Phrasebook, _ turn: Int) -> HostReply {
        let held = HostReply.Terms(nights: offer.nights, tickets: offer.tickets, credit: offer.credit)
        return switch concern {
        case .crisis:
            HostReply(say: "I'm only a game character, but that matters more than this game. Please reach out to someone you trust. In the US you can call or text 988, any time.",
                      offer: held, mood: 1, offTopic: true)
        case .personalInfo:
            HostReply(say: "Keep that to yourself. No personal details at my table. Now, about this deal.", offer: held, offTopic: true)
        case .realMoney:
            HostReply(say: "No real money here, ever. Tickets and fun, that's all. Now, about this deal.", offer: held, offTopic: true)
        case .adult:
            HostReply(say: Self.pick(book.offTopic, turn), offer: held, mood: visit == .arrival ? 0 : -1, offTopic: true)
        case .offTopic, .trickery:
            HostReply(say: Self.pick(book.offTopic, turn), offer: held, offTopic: true)
        }
    }
}
