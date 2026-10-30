import Testing
@testable import SkeeCore

@Suite("Vectors")
struct VectorTests {
    @Test func addAndScale() {
        let v = Vec2(1, 2) + Vec2(3, -1)
        #expect(v == Vec2(4, 1))
        #expect(v * 2 == Vec2(8, 2))
    }

    @Test func lengthAndDot() {
        #expect(Vec2(3, 4).length == 5)
        #expect(Vec2(1, 0).dot(Vec2(0, 1)) == 0)
        #expect(Vec2(3, 4).normalized == Vec2(0.6, 0.8))
    }

    @Test func normalizedZeroIsZero() {
        #expect(Vec2.zero.normalized == .zero)
    }
}

@Suite("SplitMix64")
struct RandomTests {
    @Test func sameSeedSameSequence() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        for _ in 0..<100 { #expect(a.next() == b.next()) }
    }

    @Test func knownFirstValue() {
        // Reference value for SplitMix64 seeded with 0 (Vigna's reference impl).
        var r = SplitMix64(seed: 0)
        #expect(r.next() == 0xE220A8397B1DCDAF)
    }

    @Test func unitIntervalStaysInRange() {
        var r = SplitMix64(seed: 7)
        for _ in 0..<1000 {
            let u = r.nextUnit()
            #expect(u >= 0 && u < 1)
        }
    }

    @Test func intBelowStaysInRange() {
        var r = SplitMix64(seed: 9)
        var seen = Set<Int>()
        for _ in 0..<500 { seen.insert(r.nextInt(below: 5)) }
        #expect(seen == Set(0..<5))
    }

    @Test func shuffleIsAPermutationAndDeterministic() {
        var a = SplitMix64(seed: 3)
        var b = SplitMix64(seed: 3)
        let xs = Array(0..<20)
        let sa = a.shuffled(xs)
        #expect(sa.sorted() == xs)
        #expect(sa == b.shuffled(xs))
    }
}
