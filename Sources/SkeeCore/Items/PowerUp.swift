/// Specialty balls: one-shot consumables. Arm one and it applies to the next
/// throw only.
public enum PowerUp: String, Hashable, Sendable, Codable, CaseIterable {
    case goldenBall, feather, magnet, wildBall, hold

    public var name: String {
        switch self {
        case .goldenBall: "Golden Ball"
        case .feather: "Feather Ball"
        case .magnet: "Magnet Ball"
        case .wildBall: "Wild Ball"
        case .hold: "Hold"
        }
    }

    public var blurb: String {
        switch self {
        case .goldenBall: "This ball's chips x3"
        case .feather: "This ball passes over ring lips"
        case .magnet: "Holes and pockets grab this ball from further away"
        case .wildBall: "This ball's symbol is a wild clover"
        case .hold: "The reels don't spin after this ball"
        }
    }

    public var cost: Int { 2 }

    func modify(_ table: Table) -> Table {
        var t = table
        switch self {
        case .feather:
            t.board.lipBand = 0
        case .magnet:
            t.board.centerHoleRadius *= 1.6
            t.board.captureSpeed *= 1.5
            t.board.pockets = t.board.pockets.map { p in var q = p; q.radius *= 1.6; return q }
        case .goldenBall, .wildBall, .hold:
            break
        }
        return t
    }
}

/// What the prize counter can sell.
public enum Offer: Hashable, Sendable, Codable {
    case charm(Charm)
    /// Put this symbol on a hole of your choice.
    case stamp(Symbol)
    /// +10 chips on a hole of your choice, permanently.
    case gild
    /// Remove the symbol a hole is showing from its reel.
    case purge
    case powerUp(PowerUp)

    public var cost: Int {
        switch self {
        case .charm(let c): c.cost
        case .stamp(let s): s == .seven || s == .diamond || s == .clover ? 4 : 3
        case .gild, .purge: 3
        case .powerUp(let p): p.cost
        }
    }

    public var needsTarget: Bool {
        switch self {
        case .stamp, .gild, .purge: true
        case .charm, .powerUp: false
        }
    }

    public static let gildAmount = 10
}

public struct PrizeCounter: Hashable, Sendable, Codable {
    /// nil marks a slot already bought this visit.
    public var offers: [Offer?]
    public var rerollCost: Int
}
