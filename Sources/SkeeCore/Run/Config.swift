/// The three rounds of every ante, like Balatro's small blind, big blind and
/// boss blind.
public enum RoundKind: String, Hashable, Sendable, Codable, CaseIterable {
    case warmup, feature, boss

    public var title: String {
        switch self {
        case .warmup: "Warm-up"
        case .feature: "Feature Game"
        case .boss: "Boss Machine"
        }
    }

    var next: RoundKind? {
        switch self {
        case .warmup: .feature
        case .feature: .boss
        case .boss: nil
        }
    }
}

/// Every balance number for a run lives here, so the balance tool can sweep
/// them without touching rules code.
public struct RunConfig: Hashable, Sendable, Codable {
    public var antes = 8
    public var framesPerRound = 3
    public var ballsPerFrame = 3
    public var startTickets = 4
    public var charmSlots = 5
    public var powerUpSlots = 2
    /// Rattles and gutters fill the jackpot meter; at this much heat the
    /// next frame plays at double mult.
    public var feverHeat = 10
    /// Target for the warm-up of each ante; feature and boss scale it.
    /// Tuned to the novice bot, the closest thing to the player this is for:
    /// someone who likes shiny things and should win often. Experts find
    /// their difficulty in the chaos balls, not here.
    public var anteBase = [400, 820, 1320, 1870, 2530, 3300, 4070, 4950]
    /// Every target times this: how much a room asks of the same run.
    public var targetScale = 1.0
    public var kindScale: [RoundKind: Double] = [.warmup: 1, .feature: 1.3, .boss: 1.6]
    public var roundTickets: [RoundKind: Int] = [.warmup: 3, .feature: 4, .boss: 5]
    /// One bonus ticket per this fraction of overkill above the target.
    public var overkillStep = 0.5
    public var overkillCap = 5
    /// One interest ticket per this many held, capped.
    public var interestPer = 5
    public var interestCap = 5
    public var offerCount = 4

    public static let standard = RunConfig()

    public func target(ante: Int, kind: RoundKind) -> Int {
        let base = anteBase[clamp(ante, 1, anteBase.count) - 1]
        return Int((Double(base) * (kindScale[kind] ?? 1) * targetScale).rounded())
    }
}
