import AVFoundation
import os
import SkeeRender

/// The game's `Synth` on the audio thread. Cues come from the presentation,
/// timed to the frame the ball hits the hump, rattles a lip or drops.
final class SoundEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var lock = os_unfair_lock()
    private var synth = Synth()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(Synth.rate), channels: 1)!
        let node = AVAudioSourceNode(format: format) { [unowned self] _, _, frames, abl in
            let buf = UnsafeMutableAudioBufferListPointer(abl)[0]
            let out = buf.mData!.assumingMemoryBound(to: Float.self)
            self.locked { $0.render(out, Int(frames)) }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.8
        try? engine.start()
    }

    private func locked(_ f: (inout Synth) -> Void) {
        os_unfair_lock_lock(&lock)
        f(&synth)
        os_unfair_lock_unlock(&lock)
    }

    func setRumble(_ v: Float) { locked { $0.rumbleTarget = v } }
    func setDrumRoll(_ on: Bool) { locked { $0.drum = on } }
    func play(_ cue: Cue) { locked { $0.play(cue) } }
}
