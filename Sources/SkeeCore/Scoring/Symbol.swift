/// Reel symbols. Every hole on the board carries one; a frame's three balls
/// read as a three-reel payline. The player picks their reel stops by aiming.
public enum Symbol: String, Hashable, Sendable, Codable, CaseIterable {
    case blank, cherry, lemon, bell, bar, seven, diamond, clover

    /// Paid per symbol whether or not it matches (cherries, like a real slot).
    public var flatChips: Int { self == .cherry ? 10 : 0 }

    public var pairMult: Double {
        switch self {
        case .blank: 0
        case .cherry, .lemon: 1
        case .bell, .bar, .clover: 2
        case .seven: 3
        case .diamond: 4
        }
    }

    public var tripleMult: Double {
        switch self {
        case .blank: 0
        case .cherry: 3
        case .lemon: 4
        case .bell: 5
        case .bar: 6
        case .clover: 7
        case .seven: 10
        case .diamond: 15
        }
    }

    /// Clover stands in for any symbol except blank.
    public var isWild: Bool { self == .clover }
}

/// The result of reading three symbols as one line.
public enum Payline: Hashable, Sendable, Codable {
    case none
    case pair(Symbol)
    case triple(Symbol)

    public var addedMult: Double {
        switch self {
        case .none: 0
        case .pair(let s): s.pairMult
        case .triple(let s): s.tripleMult
        }
    }

    /// Best line the symbols make. Wilds join whichever real symbol pays
    /// most; blanks never match anything.
    public static func evaluate(_ symbols: [Symbol]) -> Payline {
        let wilds = symbols.filter(\.isWild).count
        let real = symbols.filter { $0 != .blank && !$0.isWild }
        if real.isEmpty {
            return wilds >= 3 ? .triple(.clover) : wilds == 2 ? .pair(.clover) : .none
        }
        let best = Set(real)
            .map { s in (s, real.filter { $0 == s }.count + wilds) }
            .max { a, b in (a.1, a.0.tripleMult) < (b.1, b.0.tripleMult) }!
        switch best.1 {
        case 3...: return .triple(best.0)
        case 2: return .pair(best.0)
        default: return .none
        }
    }
}

/// The player's machine: which symbol sits on each hole and any permanent
/// chip upgrades ("gilding"). This is what stamps from the prize counter
/// change — the Luck-be-a-Landlord layer, except you choose your reel stops.
public struct BoardSetup: Hashable, Sendable, Codable {
    public var symbols: [Hole: Symbol]
    public var gild: [Hole: Int]

    public static let standard = BoardSetup(
        symbols: [
            .gutter: .blank, .ring10: .cherry, .ring20: .lemon, .ring30: .bell,
            .ring40: .bar, .ring50: .seven, .pocketLeft: .diamond, .pocketRight: .diamond,
        ],
        gild: [:])

    public func symbol(for hole: Hole) -> Symbol { symbols[hole] ?? .blank }
    public func chips(for hole: Hole) -> Int { hole.faceValue + (gild[hole] ?? 0) }
}
