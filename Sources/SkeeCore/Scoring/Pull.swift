/// The base game: a three-reel, three-row slot you pull before every frame.
///
/// Everything a regular slot player looks for, mapped onto the skee-ball
/// frame that follows:
/// - a bet: 1, 3 or 5 lines for 0, 1 or 2 tickets. Max bet is the only way
///   to a progressive jackpot, as on a real floor;
/// - line wins: three alike on an active line bank chips into the frame, so
///   they are multiplied by whatever mult the three balls build;
/// - wilds, and x2 / x3 wilds that multiply the line they complete
///   (Double Diamond's trick: the symbol players chase on a classic);
/// - the centre row is the frame's targets: a ball into a hole showing one
///   of them builds the combo. A wild there matches anything;
/// - BONUS scatters, anywhere in the window, any bet: three or more start
///   free games, frames that cost no pull, add no frame to the round's
///   count, and score double;
/// - jackpots by line: three bars MINI, three sevens MINOR, three diamonds
///   MAJOR, three wilds on the centre line GRAND. The amounts are the
///   progressive meters, which live outside the run (see `Progressive`).
public enum ReelSymbol: String, Hashable, Sendable, Codable, CaseIterable {
    case cherry, lemon, bell, bar, seven, diamond, wild, x2, x3, bonus

    /// Substitutes for any paying symbol on a line.
    public var isWild: Bool { self == .wild || self == .x2 || self == .x3 }

    /// What a wild multiplies the line it completes by.
    public var lineMultiplier: Int {
        switch self {
        case .x2: 2
        case .x3: 3
        default: 1
        }
    }

    /// Chips banked for three alike on an active line.
    public var linePay: Int {
        switch self {
        case .cherry: 20
        case .lemon: 25
        case .bell: 40
        case .bar: 60
        case .seven: 100
        case .diamond: 150
        case .wild, .x2, .x3: 250
        case .bonus: 0
        }
    }

    /// The board symbol a ball must show to match this target. Wilds match
    /// anything (clover is the board's wild); a BONUS is no target at all.
    public var target: Symbol {
        switch self {
        case .cherry: .cherry
        case .lemon: .lemon
        case .bell: .bell
        case .bar: .bar
        case .seven: .seven
        case .diamond: .diamond
        case .wild, .x2, .x3: .clover
        case .bonus: .blank
        }
    }
}

public enum Bet: Int, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case one = 1, three = 3, five = 5

    public var lines: Int { rawValue }
    public var cost: Int {
        switch self {
        case .one: 0
        case .three: 1
        case .five: 2
        }
    }
    public var isMax: Bool { self == .five }
    public static func < (a: Bet, b: Bet) -> Bool { a.rawValue < b.rawValue }
}

public enum JackpotTier: String, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case mini, minor, major, grand

    public var title: String { rawValue.uppercased() }
    var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (a: JackpotTier, b: JackpotTier) -> Bool { a.rank < b.rank }
}

public struct LineWin: Hashable, Sendable, Codable {
    /// Index into `Pull.lines`.
    public var line: Int
    public var symbol: ReelSymbol
    public var chips: Int
    public var multiplier: Int
}

public struct Pull: Hashable, Sendable, Codable {
    /// Each reel's top visible stop on its strip.
    public var stops: [Int]
    public var bet: Bet
    /// A free game: spun by the machine, cost nothing, scores double.
    public var free: Bool
    /// Whose machine: each room's strips differ.
    public var room: Room

    public init(stops: [Int], bet: Bet, free: Bool = false, room: Room = .boardwalk) {
        self.stops = stops; self.bet = bet; self.free = free; self.room = room
    }

    /// Common symbols often, rich ones rarely. Reels 1 and 3 carry two
    /// BONUS each, the middle reel one, so three scatters land about once
    /// in 75 pulls: roughly once a run.
    public static let strips: [[ReelSymbol]] = [
        [.cherry, .lemon, .bell, .bonus, .cherry, .bar, .lemon, .seven, .cherry, .bell,
         .lemon, .wild, .bar, .cherry, .diamond, .lemon, .bell, .bonus, .x2, .cherry],
        [.lemon, .cherry, .bar, .bell, .lemon, .seven, .cherry, .wild, .bell, .lemon,
         .cherry, .bonus, .bar, .lemon, .x3, .cherry, .bell, .diamond, .lemon, .cherry],
        [.bell, .cherry, .lemon, .bonus, .bar, .cherry, .bell, .lemon, .seven, .cherry,
         .x2, .lemon, .bell, .cherry, .bonus, .diamond, .lemon, .bar, .wild, .cherry],
    ]

    /// Rows of the window, top to bottom, as (column, row) per reel.
    /// Line 0 is the centre row: one-line bets play it alone.
    public static let lines: [[Int]] = [
        [1, 1, 1],
        [0, 0, 0],
        [2, 2, 2],
        [0, 1, 2],
        [2, 1, 0],
    ]

    public static func spin(bet: Bet, free: Bool = false, room: Room = .boardwalk, _ rng: inout SplitMix64) -> Pull {
        Pull(stops: room.strips.map { rng.nextInt(below: $0.count) }, bet: bet, free: free, room: room)
    }

    /// `grid[row][reel]`, rows top to bottom.
    public var grid: [[ReelSymbol]] {
        let strips = room.strips
        return (0..<3).map { row in
            (0..<3).map { reel in
                let strip = strips[reel]
                return strip[(stops[reel] + row) % strip.count]
            }
        }
    }

    public var centre: [ReelSymbol] { grid[1] }

    /// The frame's three targets.
    public var targets: [Symbol] { centre.map(\.target) }

    public var activeLines: Range<Int> { 0..<bet.lines }

    public func symbols(onLine i: Int) -> [ReelSymbol] {
        let g = grid
        return Self.lines[i].enumerated().map { reel, row in g[row][reel] }
    }

    /// Three alike on a line, wilds standing in. All wilds pay as wilds.
    /// Multiplier wilds on the line multiply its pay together.
    public static func lineWin(_ s: [ReelSymbol], line: Int) -> LineWin? {
        guard !s.contains(.bonus) else { return nil }
        let real = Set(s.filter { !$0.isWild })
        guard real.count <= 1 else { return nil }
        let symbol = real.first ?? .wild
        let mult = s.reduce(1) { $0 * $1.lineMultiplier }
        return LineWin(line: line, symbol: symbol, chips: symbol.linePay * mult, multiplier: mult)
    }

    public var lineWins: [LineWin] {
        activeLines.compactMap { Self.lineWin(symbols(onLine: $0), line: $0) }
    }

    public var lineChips: Int { lineWins.reduce(0) { $0 + $1.chips } }

    /// BONUS symbols anywhere in the window, whatever the bet.
    public var scatters: Int { grid.joined().filter { $0 == .bonus }.count }

    public static let freeGamesAwarded = 3
    public var triggersFreeGames: Bool { scatters >= 3 }

    /// The best jackpot this pull wins. Max bet only, never on a free game.
    public var jackpot: JackpotTier? {
        guard bet.isMax, !free else { return nil }
        var best: JackpotTier?
        for w in lineWins {
            let tier: JackpotTier? = switch w.symbol {
            case .bar: .mini
            case .seven: .minor
            case .diamond: .major
            case .wild where w.line == 0 && centre.allSatisfy { $0 == .wild }: .grand
            default: nil
            }
            if let tier, best.map({ tier > $0 }) ?? true { best = tier }
        }
        return best
    }
}

/// The progressive meters over the machine, kept between runs. Every pull
/// feeds them by its bet; a jackpot pays its meter into winnings and the
/// meter falls back to its seed.
public struct Progressive: Hashable, Sendable, Codable {
    public var meters: [JackpotTier: Int]

    public static let seeds: [JackpotTier: Int] = [.mini: 50, .minor: 150, .major: 600, .grand: 2500]
    /// Per ticket bet, how much each meter grows.
    public static let growth: [JackpotTier: Int] = [.mini: 2, .minor: 4, .major: 8, .grand: 15]

    public init(meters: [JackpotTier: Int] = Progressive.seeds) { self.meters = meters }

    public func amount(_ t: JackpotTier) -> Int { meters[t] ?? Self.seeds[t]! }

    /// Every pull feeds the meters, a free bet still a little.
    public mutating func feed(_ bet: Bet) {
        let units = max(1, bet.cost)
        for t in JackpotTier.allCases { meters[t] = amount(t) + Self.growth[t]! * units }
    }

    /// Pay a tier: its amount, and the meter resets.
    public mutating func hit(_ t: JackpotTier) -> Int {
        let won = amount(t)
        meters[t] = Self.seeds[t]
        return won
    }
}
