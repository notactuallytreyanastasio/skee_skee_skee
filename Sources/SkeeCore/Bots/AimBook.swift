/// For one table, the most forgiving launch for each hole: the centre of the
/// widest contiguous power window at any of a set of aims. Bots aim with it;
/// the map tool prints the raw grid it is built from.
public struct AimBook: Sendable {
    public struct Window: Hashable, Sendable {
        public var launch: Launch
        /// Width of the window as a fraction of the full power range.
        public var width: Double
    }

    public let grid: [[Hole]]          // [aimIndex][powerIndex]
    public let aims: [Double]
    public let powers: [Double]
    public let best: [Hole: Window]

    public static let defaultAims = stride(from: -1.0, through: 1.0, by: 0.125).map { $0 }

    public init(table: Table, powerSteps: Int = 240, aims: [Double] = AimBook.defaultAims, fold: Double = 0, ball: BallKind = .classic) {
        let powers = (0...powerSteps).map { Double($0) / Double(powerSteps) }
        let grid = aims.map { aim in
            powers.map { simulateShot(Launch(power: $0, aim: aim, fold: fold), on: table, ball: ball, seed: 1).hole }
        }
        var best: [Hole: Window] = [:]
        for (ai, row) in grid.enumerated() {
            var i = 0
            while i < row.count {
                var j = i
                while j + 1 < row.count && row[j + 1] == row[i] { j += 1 }
                let width = Double(j - i + 1) / Double(powerSteps)
                let hole = row[i]
                if width > (best[hole]?.width ?? 0) {
                    let mid = (powers[i] + powers[j]) / 2
                    best[hole] = Window(launch: Launch(power: mid, aim: aims[ai], fold: fold), width: width)
                }
                i = j + 1
            }
        }
        self.grid = grid; self.aims = aims; self.powers = powers; self.best = best
    }
}

/// How shaky a bot's hand is: Gaussian noise on power and aim.
public struct Skill: Hashable, Sendable, Codable {
    public var name: String
    public var powerSigma: Double
    public var aimSigma: Double

    public static let perfect = Skill(name: "perfect", powerSigma: 0, aimSigma: 0)
    public static let expert = Skill(name: "expert", powerSigma: 0.012, aimSigma: 0.04)
    public static let regular = Skill(name: "regular", powerSigma: 0.025, aimSigma: 0.08)
    public static let novice = Skill(name: "novice", powerSigma: 0.05, aimSigma: 0.15)
    public static let all = [perfect, expert, regular, novice]

    public func perturb(_ l: Launch, rng: inout SplitMix64) -> Launch {
        Launch(power: l.power + rng.nextGaussian() * powerSigma,
               aim: l.aim + rng.nextGaussian() * aimSigma,
               start: l.start, fold: l.fold)
    }
}
