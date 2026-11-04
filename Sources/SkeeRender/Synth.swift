import Foundation
import SkeeCore

/// Every sound in the game, synthesised: no audio files. A tiny polyphonic
/// synth as a pure value: cues in, samples out. The app runs it in an
/// AVAudioSourceNode; `skee film` runs it offline against the same cues, so
/// the trailer's sound is the game's sound, on the frame it happens.
public struct Synth: Sendable {
    public enum Wave: Sendable { case sine, square, tri, noise }
    public struct Voice: Sendable {
        var wave: Wave
        var freq: Float
        var freqEnd: Float
        var glide: Float
        var amp: Float
        var decay: Float
        var delay: Float = 0
        var t: Float = 0
        var phase: Float = 0
    }

    public static let rate: Float = 44100
    /// Enough for the game's cues. The film's music raises it: a bar of
    /// sequenced notes queues far more voices than any cue does.
    public static let maxVoices = 48

    private var voices: [Voice] = []
    private var lowpass: Float = 0, rumble: Float = 0
    private var drumClock: Float = 0
    private var seed: UInt32 = 22222
    private let rate = Synth.rate
    public var rumbleTarget: Float = 0
    public var drum = false

    public init() {}

    private mutating func noise() -> Float {
        seed = seed &* 1664525 &+ 1013904223
        return Float(seed >> 9) / Float(1 << 23) * 2 - 1
    }

    public mutating func render(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        let dt = 1 / rate
        for i in 0..<n {
            var s: Float = 0
            // Rolling rumble: low-passed noise that follows the ball's speed.
            rumble += (rumbleTarget - rumble) * 0.0008
            lowpass += (noise() - lowpass) * 0.035
            s += lowpass * rumble * 0.9
            // Drum roll while a jackpot-chance ball is in the air.
            if drum {
                drumClock += dt
                if drumClock > 0.055 { drumClock = 0; voices.append(Voice(wave: .noise, freq: 0, freqEnd: 0, glide: 1, amp: 0.13, decay: 0.03)) }
            }
            var k = 0
            while k < voices.count {
                var v = voices[k]
                if v.delay > 0 { v.delay -= dt; voices[k] = v; k += 1; continue }
                let f = v.freq + (v.freqEnd - v.freq) * min(1, v.t / max(v.glide, 0.0001))
                v.phase += f * dt
                if v.phase > 1 { v.phase -= 1 }
                let osc: Float = switch v.wave {
                case .sine: sin(v.phase * 2 * .pi)
                case .square: v.phase < 0.5 ? 0.6 : -0.6
                case .tri: 4 * abs(v.phase - 0.5) - 1
                case .noise: noise()
                }
                let attack = min(1, v.t / 0.003)
                s += osc * v.amp * attack * exp(-v.t / v.decay)
                v.t += dt
                if v.t > v.decay * 6 { voices.remove(at: k); continue }
                voices[k] = v
                k += 1
            }
            out[i] = max(-1, min(1, s))
        }
    }

    public mutating func add(_ vs: [Voice]) {
        voices += vs
        if voices.count > Self.maxVoices { voices.removeFirst(voices.count - Self.maxVoices) }
    }

    public func v(_ w: Wave, _ f: Float, to: Float? = nil, glide: Float = 0.1, amp: Float, decay: Float, delay: Float = 0) -> Voice {
        Voice(wave: w, freq: f, freqEnd: to ?? f, glide: glide, amp: amp, decay: decay, delay: delay)
    }

    public func arpeggio(_ notes: [Float], step: Float, amp: Float, decay: Float, wave: Wave = .sine) -> [Voice] {
        notes.enumerated().map { i, f in v(wave, f, amp: amp, decay: decay, delay: Float(i) * step) }
    }

    /// Bell partials, like a struck chime.
    public func bell(_ f: Float, amp: Float, delay: Float = 0) -> [Voice] {
        [v(.sine, f, amp: amp, decay: 0.5, delay: delay),
         v(.sine, f * 2.76, amp: amp * 0.35, decay: 0.25, delay: delay),
         v(.sine, f * 5.4, amp: amp * 0.15, decay: 0.12, delay: delay)]
    }

    public mutating func play(_ cue: Cue) {
        switch cue {
        case .launch:
            add([v(.noise, 0, amp: 0.12, decay: 0.08), v(.sine, 180, to: 320, glide: 0.12, amp: 0.15, decay: 0.08)])
        case .whoosh:
            add([v(.noise, 0, amp: 0.16, decay: 0.3), v(.sine, 900, to: 180, glide: 0.5, amp: 0.2, decay: 0.3)])
        case .hotSpot:
            add(arpeggio([1046, 1318, 1568, 2093], step: 0.05, amp: 0.2, decay: 0.3, wave: .tri) + bell(2093, amp: 0.22, delay: 0.2)
                + (0..<14).map { i in v(.tri, 2600 + Float((i * 7) % 5) * 300, amp: 0.06, decay: 0.025, delay: 0.25 + Float(i) * 0.04) })
        case .hop:
            // Boing: a pitch that jumps up and falls back.
            add([v(.sine, 220, to: 780, glide: 0.09, amp: 0.3, decay: 0.12), v(.tri, 440, to: 1100, glide: 0.09, amp: 0.1, decay: 0.08)])
        case .rail:
            add([v(.tri, 900, amp: 0.15, decay: 0.03)])
        case .hump:
            // Wood knock over the ramp.
            add([v(.sine, 170, to: 120, glide: 0.08, amp: 0.55, decay: 0.07), v(.tri, 950, amp: 0.18, decay: 0.015),
                 v(.noise, 0, amp: 0.08, decay: 0.02)])
        case .lip:
            add([v(.tri, 1900, amp: 0.2, decay: 0.02), v(.tri, 2300, amp: 0.16, decay: 0.02, delay: 0.035)])
        case .backwall:
            add([v(.sine, 110, to: 80, amp: 0.4, decay: 0.12), v(.noise, 0, amp: 0.06, decay: 0.04)])
        case .landed:
            add([v(.sine, 140, to: 100, amp: 0.3, decay: 0.06)])
        case .drop(let h):
            let pitch: Float = switch h {
            case .ring10: 523
            case .ring20: 587
            case .ring30: 659
            case .ring40: 784
            case .ring50: 1046
            case .pocketLeft, .pocketRight: 1318
            case .gutter: 220
            }
            var vs = [v(.sine, 120, to: 50, glide: 0.25, amp: 0.6, decay: 0.2)] + bell(pitch, amp: 0.3, delay: 0.04)
            if h.faceValue >= 50 { vs += bell(pitch * 1.5, amp: 0.2, delay: 0.12) }
            add(vs)
        case .gutter:
            add([v(.sine, 220, to: 70, glide: 0.45, amp: 0.35, decay: 0.35), v(.noise, 0, amp: 0.05, decay: 0.1)])
        case .reelTick:
            add([v(.tri, 2600, amp: 0.07, decay: 0.012)])
        case .reelStop:
            add([v(.tri, 1500, amp: 0.18, decay: 0.05), v(.sine, 750, amp: 0.12, decay: 0.08)])
        case .combo(let n):
            // A rising two-note chime, higher each link of the chain.
            let k = pow(1.0595, Float(2 * min(n, 6)))
            add([v(.square, 659 * k, amp: 0.1, decay: 0.08), v(.square, 988 * k, amp: 0.1, decay: 0.14, delay: 0.07)]
                + bell(1318 * k, amp: 0.15, delay: 0.14))
        case .tallyChips(let i):
            add([v(.sine, 440 * pow(1.06, Float(i)), amp: 0.22, decay: 0.07)])
        case .tallyMult(let i):
            add([v(.square, 587 * pow(1.06, Float(i)), amp: 0.1, decay: 0.09), v(.sine, 1174 * pow(1.06, Float(i)), amp: 0.08, decay: 0.06)])
        case .frameDone:
            add([v(.sine, 392, amp: 0.2, decay: 0.15)])
        case .lineWon:
            add(arpeggio([523, 659, 784, 1046], step: 0.06, amp: 0.22, decay: 0.18))
        case .jackpot:
            add(arpeggio([523, 659, 784, 1046, 1318, 1568, 2093], step: 0.055, amp: 0.25, decay: 0.3, wave: .tri)
                + bell(1046, amp: 0.35, delay: 0.4) + bell(1568, amp: 0.25, delay: 0.45)
                + (0..<20).map { i in v(.tri, 3000 + Float(i % 5) * 400, amp: 0.05, decay: 0.03, delay: 0.4 + Float(i) * 0.04) })
        case .banner(let t):
            switch t {
            case "CLEARED":
                add(arpeggio([392, 523, 659, 784, 1046], step: 0.08, amp: 0.22, decay: 0.25)
                    + (0..<16).map { i in v(.tri, 1800, amp: 0.08, decay: 0.012, delay: 0.5 + Float(i) * 0.045) })
            case "FREE GAMES":
                add(arpeggio([523, 659, 784, 1046, 784, 1046, 1318, 1568], step: 0.07, amp: 0.22, decay: 0.2, wave: .square))
            case _ where t.hasSuffix("JACKPOT"):
                add(arpeggio([523, 659, 784, 1046, 1318, 1568, 2093, 2637], step: 0.06, amp: 0.25, decay: 0.35, wave: .tri)
                    + (0..<40).map { i in v(.tri, 2600 + Float(i % 6) * 350, amp: 0.05, decay: 0.03, delay: 0.5 + Float(i) * 0.04) })
            case "GAME OVER":
                add(arpeggio([392, 370, 349, 294], step: 0.3, amp: 0.15, decay: 0.4, wave: .square))
            case "FEVER":
                add([v(.square, 300, to: 1200, glide: 0.5, amp: 0.1, decay: 0.4)] + bell(1568, amp: 0.2, delay: 0.5))
            default:
                add(bell(784, amp: 0.18))
            }
        case .lever:
            // Ratchet down, then the clunk of the reels letting go.
            add((0..<6).map { i in v(.tri, 1200 - Float(i) * 60, amp: 0.1, decay: 0.012, delay: Float(i) * 0.025) }
                + [v(.sine, 90, to: 60, glide: 0.1, amp: 0.45, decay: 0.12, delay: 0.16), v(.noise, 0, amp: 0.08, decay: 0.05, delay: 0.16)])
        case .pullWin(let chips):
            // A coin rattle that runs longer the more it paid.
            let n = min(30, 6 + chips / 15)
            add(arpeggio([784, 988, 1175], step: 0.07, amp: 0.2, decay: 0.12)
                + (0..<n).map { i in v(.tri, 2400 + Float((i * 7) % 5) * 300, amp: 0.06, decay: 0.02, delay: 0.2 + Float(i) * 0.035) })
        case .foul:
            add([v(.square, 110, amp: 0.25, decay: 0.3), v(.square, 104, amp: 0.2, decay: 0.3)])
        }
    }
}
