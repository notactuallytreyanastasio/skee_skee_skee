/// Seedable, platform-independent PRNG (SplitMix64, Vigna 2015).
///
/// The core never touches system randomness. Every random choice in a run
/// (shop offers, boss order) flows from one seed, so a run is fully
/// described by `(seed, [Action])` and can be replayed exactly.
public struct SplitMix64: Hashable, Sendable, Codable {
    public private(set) var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1) using the top 53 bits.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform in 0..<n. Modulo bias is negligible for the tiny n we use.
    public mutating func nextInt(below n: Int) -> Int {
        precondition(n > 0, "nextInt(below:) needs a positive bound, got \(n)")
        return Int(next() % UInt64(n))
    }

    /// Gaussian sample (Box–Muller). Used only by bots, never by the game.
    public mutating func nextGaussian() -> Double {
        let u1 = max(nextUnit(), 1e-12)
        let u2 = nextUnit()
        return (-2 * _log(u1)).squareRoot() * _cos(2 * .pi * u2)
    }

    public mutating func shuffled<T>(_ xs: [T]) -> [T] {
        var a = xs
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            a.swapAt(i, nextInt(below: i + 1))
        }
        return a
    }

    public mutating func pick<T>(_ xs: [T]) -> T {
        xs[nextInt(below: xs.count)]
    }
}
