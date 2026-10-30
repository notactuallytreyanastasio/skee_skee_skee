/// The prize shelf: what a run's winnings buy after it ends. Prizes are
/// trophies and nothing else. They never touch a run, so a long shelf says
/// you've played a lot without making the next run easier. Tickets, the
/// in-run currency, stay inside the run and buy charms; winnings live here.
public enum Prize: String, Hashable, Sendable, Codable, CaseIterable {
    case sticker, rubberDuck, kazoo, yoyo, slinky, plushFrog, lavaLamp, robot, giantBear, trophy

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

    public init(balance: Int = 0, lifetime: Int = 0, owned: [Prize] = []) {
        self.balance = balance; self.lifetime = lifetime; self.owned = owned
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
