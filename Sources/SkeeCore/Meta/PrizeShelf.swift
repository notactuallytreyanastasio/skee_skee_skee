/// The prize shelf: what a run's winnings buy after it ends. Prizes are
/// trophies and nothing else. They never touch a run, so a long shelf says
/// you've played a lot without making the next run easier. Tickets, the
/// in-run currency, stay inside the run and buy charms; winnings live here.
public enum Prize: String, Hashable, Sendable, Codable, CaseIterable {
    // The Boardwalk Arcade
    case sticker, rubberDuck, kazoo, yoyo, slinky, plushFrog, lavaLamp, robot, giantBear, trophy
    // The Neon Lounge
    case glowSticks, rollerSkates, discoBall, neonSign, jukebox, arcadeCabinet
    // The High Roller Suite
    case cufflinks, champagne, pearlNecklace, goldWatch, chandelier, sportsCar
    // The Penthouse
    case goldenFlamingo, hotTub, grandPiano, yacht, privateJet, diamondCrown

    /// The shelf each room's counter stocks.
    public var room: Room { Room.allCases.first { $0.prizes.contains(self) }! }

    public var name: String {
        switch self {
        case .sticker: "Gold Star Sticker"
        case .rubberDuck: "Rubber Duck"
        case .kazoo: "Kazoo"
        case .yoyo: "Yo-yo"
        case .slinky: "Slinky"
        case .plushFrog: "Plush Frog"
        case .lavaLamp: "Lava Lamp"
        case .robot: "Wind-up Robot"
        case .giantBear: "Giant Bear"
        case .trophy: "Golden Skee Trophy"
        case .glowSticks: "Glow Sticks"
        case .rollerSkates: "Roller Skates"
        case .discoBall: "Disco Ball"
        case .neonSign: "Neon Sign"
        case .jukebox: "Jukebox"
        case .arcadeCabinet: "Tiny Arcade Cabinet"
        case .cufflinks: "Cufflinks"
        case .champagne: "Champagne"
        case .pearlNecklace: "Pearl Necklace"
        case .goldWatch: "Gold Watch"
        case .chandelier: "Chandelier"
        case .sportsCar: "Toy Sports Car"
        case .goldenFlamingo: "Golden Flamingo"
        case .hotTub: "Hot Tub"
        case .grandPiano: "Grand Piano"
        case .yacht: "Yacht"
        case .privateJet: "Private Jet"
        case .diamondCrown: "Diamond Crown"
        }
    }

    public var price: Int {
        switch self {
        case .sticker: 50
        case .rubberDuck: 150
        case .kazoo: 250
        case .yoyo: 400
        case .slinky: 600
        case .plushFrog: 1000
        case .lavaLamp: 1600
        case .robot: 2500
        case .giantBear: 5000
        case .trophy: 10000
        case .glowSticks: 300
        case .rollerSkates: 900
        case .discoBall: 1800
        case .neonSign: 3000
        case .jukebox: 6000
        case .arcadeCabinet: 12000
        case .cufflinks: 1500
        case .champagne: 3000
        case .pearlNecklace: 6000
        case .goldWatch: 10000
        case .chandelier: 16000
        case .sportsCar: 25000
        case .goldenFlamingo: 5000
        case .hotTub: 12000
        case .grandPiano: 20000
        case .yacht: 35000
        case .privateJet: 50000
        case .diamondCrown: 100000
        }
    }
}

public enum ShopError: Error, Hashable, Sendable {
    case cantAfford, alreadyOwned
}

/// Winnings carried between runs, and the shelf they bought.
public struct Wallet: Hashable, Sendable, Codable {
    public var balance: Int
    /// Everything ever credited, spent or not.
    public var lifetime: Int
    /// In the order bought.
    public var owned: [Prize]
    /// The jackpot meters over the pull machine. They carry between runs,
    /// so a GRAND nobody has hit in a while is worth more.
    public var progressive = Progressive()
    /// Rooms comped so far; yours for good.
    public var rooms: Set<Room> = [.boardwalk]
    /// The room the next run is played in.
    public var room: Room = .boardwalk
    /// Comped nights still to use, by room.
    public var comps: [Room: Comp] = [:]
    /// Games played since the host last sat down, and how many times they
    /// have. Saved so the visit survives closing the app.
    public var gamesSinceHost = 0
    public var hostVisits = 0

    public init(balance: Int = 0, lifetime: Int = 0, owned: [Prize] = []) {
        self.balance = balance; self.lifetime = lifetime; self.owned = owned
    }

    enum CodingKeys: String, CodingKey { case balance, lifetime, owned, progressive, rooms, room, comps, gamesSinceHost, hostVisits }

    /// Wallets saved before a field existed still load, with its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        balance = try c.decode(Int.self, forKey: .balance)
        lifetime = try c.decode(Int.self, forKey: .lifetime)
        owned = try c.decode([Prize].self, forKey: .owned)
        progressive = try c.decodeIfPresent(Progressive.self, forKey: .progressive) ?? Progressive()
        rooms = try c.decodeIfPresent(Set<Room>.self, forKey: .rooms) ?? [.boardwalk]
        room = try c.decodeIfPresent(Room.self, forKey: .room) ?? .boardwalk
        comps = try c.decodeIfPresent([Room: Comp].self, forKey: .comps) ?? [:]
        gamesSinceHost = try c.decodeIfPresent(Int.self, forKey: .gamesSinceHost) ?? 0
        hostVisits = try c.decodeIfPresent(Int.self, forKey: .hostVisits) ?? 0
    }

    /// The next room the host is ready to comp, if your winnings have
    /// earned it: the first one you don't have yet, once you're past its
    /// threshold.
    public var compDue: Room? {
        guard let next = Room.allCases.first(where: { !rooms.contains($0) }) else { return nil }
        return lifetime >= next.compThreshold ? next : nil
    }

    /// Games between the host's visits: three, then four, then three.
    public var hostInterval: Int { hostVisits.isMultiple(of: 2) ? 3 : 4 }

    /// A game ended, won, lost or walked away from.
    public mutating func gamePlayed() { gamesSinceHost += 1 }

    /// The room the host wants to talk about, once enough games have gone
    /// by: the next room if winnings have earned it, otherwise a comped
    /// stay where you are. A count, not a winnings threshold, because a
    /// player who keeps losing is the one who most needs a free night.
    public var hostDue: Room? {
        gamesSinceHost >= hostInterval ? (compDue ?? room) : nil
    }

    /// Close a haggle: the room is yours either way. A signed deal banks
    /// its nights and pays its credit; a host who walked leaves you the
    /// opening offer and nothing you talked them into. The new room is
    /// where the next run happens. Nights left from an earlier deal stay,
    /// and the better ticket perk applies to all of them.
    public mutating func close(_ h: Haggle) {
        guard h.status != .open else { return }
        let deal = h.final
        rooms.insert(deal.room)
        room = deal.room
        var stay = deal
        if let old = comps[deal.room] {
            stay.nights += old.nights
            stay.tickets = max(stay.tickets, old.tickets)
        }
        comps[deal.room] = stay
        credit(deal.credit)
        gamesSinceHost = 0
        hostVisits += 1
    }

    /// Start a run in the current room: use a comped night if one is left.
    /// Returns the extra starting tickets.
    public mutating func checkIn() -> Int {
        guard var c = comps[room], c.nights > 0 else { return 0 }
        c.nights -= 1
        comps[room] = c.nights > 0 ? c : nil
        return c.tickets
    }

    /// Feed the meters for a pull, and pay out a jackpot if it hit one.
    /// Returns what the jackpot paid.
    @discardableResult
    public mutating func pulled(_ p: Pull) -> Int {
        if !p.free { progressive.feed(p.bet) }
        guard let tier = p.jackpot else { return 0 }
        let won = progressive.hit(tier)
        credit(won)
        return won
    }

    public func buy(_ p: Prize) -> Result<Wallet, ShopError> {
        guard !owned.contains(p) else { return .failure(.alreadyOwned) }
        guard balance >= p.price else { return .failure(.cantAfford) }
        var w = self
        w.balance -= p.price
        w.owned.append(p)
        return .success(w)
    }

    public mutating func credit(_ amount: Int) {
        balance += amount; lifetime += amount
    }
}

/// What a finished run pays to the shelf: a twentieth of every point
/// scored, 20 per round cleared, 500 for beating the arcade.
public func winnings(stats: RunStats, won: Bool) -> Int {
    stats.points / 20 + stats.roundsCleared * 20 + (won ? 500 : 0)
}
