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
        case .cherry, .lemon: 3
        case .bell: 4
        case .bar, .clover: 5
        case .seven: 10
        case .diamond: 12
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

/// The player's machine. Every hole has its own reel strip; after each ball
/// the reels spin (seeded) and each hole shows one symbol from its strip.
/// The player sees what's showing and aims for what completes the line.
/// Stamps add symbols to a strip, purges remove them — Luck be a Landlord's
/// reel building, except you choose which reel you hit.
public struct BoardSetup: Hashable, Sendable, Codable {
    public var reels: [Hole: [Symbol]]
    public var gild: [Hole: Int]

    /// The first symbol on each strip is the hole's "home" symbol, the one
    /// a classic cabinet would print: 10 cherry up to 50 seven.
    public static let standard = BoardSetup(
        reels: [
            .ring10: [.cherry, .cherry, .lemon, .cherry, .bell],
            .ring20: [.lemon, .lemon, .cherry, .bell, .lemon],
            .ring30: [.bell, .bell, .lemon, .bar, .bell],
            .ring40: [.bar, .bar, .bell, .seven, .bar],
            .ring50: [.seven, .bar, .seven, .bell, .cherry],
            .pocketLeft: [.diamond, .seven, .diamond, .clover, .bar],
            .pocketRight: [.diamond, .bar, .diamond, .clover, .seven],
        ],
        gild: [:])

    public func reel(_ hole: Hole) -> [Symbol] {
        hole == .gutter ? [.blank] : (reels[hole] ?? [.blank])
    }
    public func homeSymbol(for hole: Hole) -> Symbol { reel(hole).first ?? .blank }
    public func chips(for hole: Hole) -> Int { hole.faceValue + (gild[hole] ?? 0) }

    /// Holes that have reels (everything but the gutter).
    public static let reelHoles: [Hole] = Hole.allCases.filter { $0 != .gutter }
}
