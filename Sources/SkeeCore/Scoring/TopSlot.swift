/// The slot machine on top of the cabinet. It spins after every throw, foul
/// included, and lands on three symbols: the next throw's targets. A ball
/// whose symbol matches k of them adds mult, scaled by the combo, the run of
/// consecutive throws that matched. A throw that misses breaks the combo.
///
/// The spin happens before you aim, not while the ball is in the air: if the
/// slot landed after the ball, matching it would be luck. Shown first, it is
/// a target, and the combo is a streak you earn.
public struct TopSlot: Hashable, Sendable, Codable {
    /// Each reel's stop on `strip`.
    public var stops: [Int]

    /// Common symbols often, rich ones rarely; never blank.
    public static let strip: [Symbol] = [
        .cherry, .lemon, .bell, .cherry, .bar, .lemon, .bell, .seven,
        .cherry, .lemon, .bell, .bar, .diamond, .lemon, .cherry, .clover,
    ]
    public static let maxLevel = 5
    public static let jackpotTickets = 3

    public init(stops: [Int]) { self.stops = stops }

    public static func spin(_ rng: inout SplitMix64) -> TopSlot {
        TopSlot(stops: (0..<3).map { _ in rng.nextInt(below: strip.count) })
    }

    public var symbols: [Symbol] { stops.map { Self.strip[$0 % Self.strip.count] } }

    /// How many reels a ball showing `s` matches. A clover reel matches any
    /// real symbol; a clover ball matches whichever symbol shows most.
    public func hits(_ s: Symbol) -> Int {
        guard s != .blank else { return 0 }
        let shown = symbols
        let wild = shown.filter(\.isWild).count
        if s.isWild {
            let best = Set(shown.filter { !$0.isWild }).map { x in shown.filter { $0 == x }.count }.max() ?? 0
            return best + wild
        }
        return shown.filter { $0 == s }.count + wild
    }

    /// Mult a matching ball adds: half a mult per reel matched, times the
    /// combo level (capped).
    public static func comboMult(hits: Int, level: Int) -> Double {
        0.5 * Double(hits) * Double(min(max(level, 1), maxLevel)) * (hits > 0 ? 1 : 0)
    }
}
