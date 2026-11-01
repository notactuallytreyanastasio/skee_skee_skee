/// The frame's targets: the centre row of the last pull, shown on top of
/// the cabinet. A ball whose symbol matches k of them adds mult, scaled by
/// the combo, the run of consecutive throws that matched. A throw that
/// misses breaks the combo.
///
/// The pull happens before you aim, not while the ball is in the air: if
/// the targets landed after the ball, matching them would be luck. Shown
/// first, they are a target, and the combo is a streak you earn.
public struct TopSlot: Hashable, Sendable, Codable {
    public var symbols: [Symbol]

    public static let maxLevel = 5
    public static let jackpotTickets = 3
    /// Before the first pull of a run: nothing to match.
    public static let empty = TopSlot(symbols: [.blank, .blank, .blank])

    public init(symbols: [Symbol]) { self.symbols = symbols }

    /// How many targets a ball showing `s` matches. A wild target matches
    /// any real symbol; a wild ball matches whichever symbol shows most.
    public func hits(_ s: Symbol) -> Int {
        guard s != .blank else { return 0 }
        let shown = symbols
        let wild = shown.filter(\.isWild).count
        if s.isWild {
            let best = Set(shown.filter { !$0.isWild && $0 != .blank }).map { x in shown.filter { $0 == x }.count }.max() ?? 0
            return best + wild
        }
        return shown.filter { $0 == s }.count + wild
    }

    /// Mult a matching ball adds: half a mult per target matched, times the
    /// combo level (capped).
    public static func comboMult(hits: Int, level: Int) -> Double {
        0.5 * Double(hits) * Double(min(max(level, 1), maxLevel)) * (hits > 0 ? 1 : 0)
    }
}
