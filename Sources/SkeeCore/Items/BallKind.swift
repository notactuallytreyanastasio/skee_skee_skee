/// The ball you choose to throw, free to change before any throw. Easy
/// balls forgive and pay less; chaotic ones pay more for what they put you
/// through. This is where a player who wants difficulty goes to find it:
/// the base game stays gentle.
public enum BallKind: String, Hashable, Sendable, Codable, CaseIterable {
    case marshmallow, classic, bean, wobbler, comet

    public var name: String {
        switch self {
        case .marshmallow: "Marshmallow"
        case .classic: "Classic"
        case .bean: "Jumping Bean"
        case .wobbler: "Wobbler"
        case .comet: "Comet"
        }
    }

    /// A word that fits on a small button.
    public var short: String {
        switch self {
        case .marshmallow: "SOFT"
        case .classic: "CLASSIC"
        case .bean: "BEAN"
        case .wobbler: "WOBBLE"
        case .comet: "COMET"
        }
    }

    public var blurb: String {
        switch self {
        case .marshmallow: "Big and soft. Drifts toward the middle."
        case .classic: "The good old ball."
        case .bean: "Hops around when it feels like it."
        case .wobbler: "Snakes from side to side."
        case .comet: "Blazing fast. Bounces off everything!"
        }
    }

    /// What a ball's chips are multiplied by.
    public var pay: Double {
        switch self {
        case .marshmallow: 1.1
        case .classic: 1.2
        case .bean: 2
        case .wobbler: 2
        case .comet: 3
        }
    }

    public var payLabel: String {
        switch self {
        case .marshmallow: "x1.1"
        case .classic: "x1.2"
        case .bean: "x2"
        case .wobbler: "x2"
        case .comet: "x3"
        }
    }

    /// Its flight depends on a seed drawn from the run.
    public var isRandom: Bool { self == .bean || self == .wobbler }

    /// Released this much faster than the thumb asked.
    var speedScale: Double { self == .comet ? 1.3 : 1 }

    /// Drawn size against a classic ball. The physics radius does not
    /// change: only the holes' welcome does.
    public var drawnSize: Float { self == .marshmallow ? 1.3 : 1 }

    func modify(_ table: Table) -> Table {
        var t = table
        switch self {
        case .marshmallow:
            t.board.centerHoleRadius *= 1.5
            t.board.captureSpeed *= 1.6
            // Lips and bounce stay as they are, softer as it looks. Rattles
            // fill the fever meter: a gentler lip cut fever frames by two
            // thirds and made the easy ball the hard one.
            t.board.pockets = t.board.pockets.map { p in var q = p; q.radius *= 1.5; return q }
        case .comet:
            t.lane.railRestitution = 1
            t.board.bounce *= 1.5
            t.board.landingGrip = 0.95
            t.board.lipBounce *= 1.3
            t.board.wallRestitution = 1.05
            t.board.backwallRestitution = 1.05
        case .classic, .bean, .wobbler:
            break
        }
        return t
    }
}
