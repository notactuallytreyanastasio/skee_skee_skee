/// Where you play. Every room has its own alley (board geometry), its own
/// cabinet reels and pull machine, and its own prize counter. You start in
/// the Boardwalk Arcade; the others are comped by the casino's host once
/// your winnings are big enough, and stay yours for good.
///
/// The physics is the same everywhere. What changes is where the rings and
/// pockets sit, how tight they are, what the reels carry and what the
/// machine likes to land on, so each room asks for a different throw.
public enum Room: String, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case boardwalk, neonLounge, highRoller, penthouse

    public var name: String {
        switch self {
        case .boardwalk: "The Boardwalk Arcade"
        case .neonLounge: "The Neon Lounge"
        case .highRoller: "The High Roller Suite"
        case .penthouse: "The Penthouse"
        }
    }

    public var blurb: String {
        switch self {
        case .boardwalk: "Where everyone starts. Sticky floors, honest machines."
        case .neonLounge: "Rings set high and tight, pockets pulled in. The machine runs hot on wilds."
        case .highRoller: "Small rings, pockets that pay 150, a machine heavy with sevens and diamonds."
        case .penthouse: "A steep board and wide rings. The machine is full of 3X wilds."
        }
    }

    var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (a: Room, b: Room) -> Bool { a.rank < b.rank }

    public var next: Room? {
        let all = Self.allCases
        return rank + 1 < all.count ? all[rank + 1] : nil
    }

    /// Lifetime winnings at which the host first offers to comp this room.
    public var compThreshold: Int {
        switch self {
        case .boardwalk: 0
        case .neonLounge: 1500
        case .highRoller: 5000
        case .penthouse: 12000
        }
    }

    /// The alley. Only the board moves; the lane and hinge are the same
    /// everywhere, so your flick carries from room to room.
    public var table: Table {
        var t = Table.standard
        switch self {
        case .boardwalk:
            break
        case .neonLounge:
            t.board.ringCenter = Vec2(0, 0.6)
            t.board.ringWalls = [0.095, 0.15, 0.21, 0.28]
            t.board.pockets = [
                Pocket(hole: .pocketLeft, center: Vec2(-0.17, 0.88), radius: 0.036),
                Pocket(hole: .pocketRight, center: Vec2(0.17, 0.88), radius: 0.036),
            ]
        case .highRoller:
            t.board.ringWalls = [0.085, 0.14, 0.2, 0.27]
            t.board.centerHoleOffset = Vec2(0, 0.035)
            t.board.pockets = [
                Pocket(hole: .pocketLeft, center: Vec2(-0.22, 0.87), radius: 0.033),
                Pocket(hole: .pocketRight, center: Vec2(0.22, 0.87), radius: 0.033),
            ]
        case .penthouse:
            t.board.tilt = 24 * .pi / 180
            t.board.ringCenter = Vec2(0, 0.6)
            t.board.ringWalls = [0.11, 0.17, 0.23, 0.3]
            t.board.pockets = [
                Pocket(hole: .pocketLeft, center: Vec2(-0.19, 0.88), radius: 0.038),
                Pocket(hole: .pocketRight, center: Vec2(0.19, 0.88), radius: 0.038),
            ]
        }
        return t
    }

    /// The cabinet's reels: what each hole can show.
    public var setup: BoardSetup {
        var s = BoardSetup.standard
        switch self {
        case .boardwalk:
            break
        case .neonLounge:
            s.reels[.ring10] = [.lemon, .lemon, .cherry, .clover, .lemon]
            s.reels[.ring20] = [.bell, .lemon, .bell, .cherry, .bell]
            s.reels[.ring50] = [.seven, .clover, .seven, .bar, .seven]
        case .highRoller:
            s.reels[.ring30] = [.bar, .bell, .bar, .seven, .bar]
            s.reels[.ring40] = [.seven, .bar, .seven, .diamond, .seven]
            s.reels[.ring50] = [.diamond, .seven, .diamond, .bar, .diamond]
            s.gild[.pocketLeft] = 50
            s.gild[.pocketRight] = 50
        case .penthouse:
            s.reels[.ring10] = [.bell, .bell, .bar, .bell, .cherry]
            s.reels[.ring20] = [.bar, .bar, .bell, .seven, .bar]
            s.reels[.ring50] = [.diamond, .clover, .diamond, .seven, .diamond]
            s.reels[.pocketLeft] = [.clover, .diamond, .clover, .seven, .clover]
            s.reels[.pocketRight] = [.clover, .seven, .clover, .diamond, .clover]
        }
        return s
    }

    /// The pull machine's strips. Each room swaps a few stops on the
    /// Boardwalk's: the same machine, with a different temper.
    public var strips: [[ReelSymbol]] {
        var s = Pull.strips
        func swap(_ from: ReelSymbol, _ to: ReelSymbol, count: Int) {
            var left = count
            for r in 0..<3 {
                for i in s[r].indices where left > 0 && s[r][i] == from { s[r][i] = to; left -= 1; break }
            }
        }
        switch self {
        case .boardwalk:
            break
        case .neonLounge:
            swap(.cherry, .wild, count: 3)
            swap(.lemon, .x2, count: 3)
        case .highRoller:
            swap(.cherry, .seven, count: 3)
            swap(.lemon, .diamond, count: 3)
        case .penthouse:
            swap(.cherry, .x3, count: 3)
            swap(.lemon, .bar, count: 3)
        }
        return s
    }

    /// This room's prize counter, cheapest first.
    public var prizes: [Prize] {
        switch self {
        case .boardwalk: [.sticker, .rubberDuck, .kazoo, .yoyo, .slinky, .plushFrog, .lavaLamp, .robot, .giantBear, .trophy]
        case .neonLounge: [.glowSticks, .rollerSkates, .discoBall, .neonSign, .jukebox, .arcadeCabinet]
        case .highRoller: [.cufflinks, .champagne, .pearlNecklace, .goldWatch, .chandelier, .sportsCar]
        case .penthouse: [.goldenFlamingo, .hotTub, .grandPiano, .yacht, .privateJet, .diamondCrown]
        }
    }
}

/// What the host comps you with a room: nights (runs) that start with
/// extra tickets, and resort credit paid into winnings at once. The room
/// itself is yours for good either way.
public struct Comp: Hashable, Sendable, Codable {
    public var room: Room
    /// Runs in this room that start with the perk.
    public var nights: Int
    /// Extra starting tickets on each of those nights.
    public var tickets: Int
    /// Winnings credited when the deal is signed.
    public var credit: Int

    public init(room: Room, nights: Int, tickets: Int, credit: Int) {
        self.room = room; self.nights = nights; self.tickets = tickets; self.credit = credit
    }

    /// The host's first offer: the room, one night, nothing else.
    public static func opening(_ room: Room) -> Comp { Comp(room: room, nights: 1, tickets: 0, credit: 0) }

    /// What the deal is worth in winnings, by the casino's arithmetic: a
    /// ticket on a night is worth 40, each night itself 60.
    public var value: Int { nights * 60 + nights * tickets * 40 + credit }

    /// The most any host will put on the table for a room.
    public static func ceiling(_ room: Room) -> Comp {
        let k = room.rank
        return Comp(room: room, nights: 3 + k, tickets: 2 + k, credit: 300 * (k + 1))
    }

    /// Every field held inside 0...ceiling (nights at least 1).
    public func clamped() -> Comp {
        let c = Self.ceiling(room)
        return Comp(room: room, nights: clamp(nights, 1, c.nights), tickets: clamp(tickets, 0, c.tickets),
                    credit: clamp(credit, 0, c.credit))
    }
}
