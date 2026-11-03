import SkeeCore
import SkeeRender
import Testing

@Suite struct SynthTests {
    func render(_ cues: [Cue], samples: Int = 22050) -> [Float] {
        var s = Synth()
        for c in cues { s.play(c) }
        var out = [Float](repeating: 0, count: samples)
        out.withUnsafeMutableBufferPointer { s.render($0.baseAddress!, samples) }
        return out
    }

    @Test func silentUntilCued() {
        #expect(render([]).allSatisfy { $0 == 0 })
    }

    @Test func aCueSoundsAndStaysInRange() {
        let out = render([.drop(.ring50), .jackpot, .lever])
        #expect(out.contains { abs($0) > 0.05 })
        #expect(out.allSatisfy { abs($0) <= 1 })
    }

    /// `skee film` depends on this: the same cues are the same sound.
    @Test func deterministic() {
        #expect(render([.drop(.ring30), .reelStop]) == render([.drop(.ring30), .reelStop]))
    }
}
