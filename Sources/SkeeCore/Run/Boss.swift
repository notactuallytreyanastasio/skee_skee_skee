/// Boss machines: the third round of each ante bends one rule. The run picks
/// one per ante from the seed and shows it in advance.
public enum Boss: String, Hashable, Sendable, Codable, CaseIterable {
    case tallLips, slickLane, crosswind, miser, shortHand, tightPockets, theHouse

    public var name: String {
        switch self {
        case .tallLips: "Tall Lips"
        case .slickLane: "Slick Lane"
        case .crosswind: "Crosswind"
        case .miser: "The Miser"
        case .shortHand: "Short Hand"
        case .tightPockets: "Tight Pockets"
        case .theHouse: "The House"
        }
    }

    public var blurb: String {
        switch self {
        case .tallLips: "Ring lips are taller and wider. Expect rattles."
        case .slickLane: "The lane is waxed. Your usual power overshoots."
        case .crosswind: "A steady wind pushes balls across the board."
        case .miser: "The 50 hole pays no chips."
        case .shortHand: "One frame fewer this round."
        case .tightPockets: "The 50 hole and the 100 pockets shrink."
        case .theHouse: "Pairs pay nothing. Only three of a kind counts."
        }
    }

    /// Physical changes. Scoring and round-shape changes are read elsewhere.
    public func modify(_ table: Table) -> Table {
        var t = table
        switch self {
        case .tallLips:
            t.board.lipHeight *= 1.6
            t.board.lipBand += 0.2
        case .slickLane:
            t.lane.rollingFriction *= 0.3
        case .crosswind:
            t.board.wind = Vec2(0.4, 0)
        case .tightPockets:
            t.board.centerHoleRadius *= 0.85
            t.board.pockets = t.board.pockets.map { p in var q = p; q.radius *= 0.75; return q }
        case .miser, .shortHand, .theHouse:
            break
        }
        return t
    }

    var frameDelta: Int { self == .shortHand ? -1 : 0 }
    var pairsPay: Bool { self != .theHouse }
    public func chips(for hole: Hole, base: Int) -> Int { self == .miser && hole == .ring50 ? 0 : base }
}
