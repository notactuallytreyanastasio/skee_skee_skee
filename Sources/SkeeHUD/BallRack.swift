import SkeeCore
import SwiftUI

/// Big plain buttons along the bottom: pick your ball before any throw.
struct BallRack: View {
    let selected: BallKind
    let pick: (BallKind) -> Void

    static func color(_ k: BallKind) -> Color {
        switch k {
        case .marshmallow: Ink.cream
        case .classic: Color(hex: 0xFF6F6F)
        case .bean: Ink.mint
        case .wobbler: Ink.lilac
        case .comet: Color(hex: 0xFF9A2E)
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            CelText(text: selected.blurb, size: 15, fill: Ink.butter)
            HStack(spacing: 5) {
                ForEach(BallKind.allCases, id: \.self) { k in
                    Button { pick(k) } label: {
                        VStack(spacing: 1) {
                            Circle().fill(Self.color(k)).overlay(Circle().strokeBorder(Ink.ink, lineWidth: 2.5)).frame(width: 22, height: 22)
                            CelText(text: k.short, size: 11)
                            CelText(text: k.payLabel, size: 16, fill: Ink.butter)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: 12).fill(k == selected ? Ink.pink : Ink.violet)
                            RoundedRectangle(cornerRadius: 12).strokeBorder(k == selected ? Ink.butter : Ink.ink, lineWidth: k == selected ? 3.5 : 2.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
    }
}

/// The frame's Hot Spot: a pulsing gold ring with its promise on it.
struct HotSpotMark: View {
    let clock: Double
    var body: some View {
        let beat = 0.5 + 0.5 * sin(clock * 6)
        ZStack {
            Circle().strokeBorder(Ink.butter, lineWidth: 5).frame(width: 46 + 12 * beat, height: 46 + 12 * beat).opacity(0.9 - 0.4 * beat)
            CelText(text: "x2", size: 20, fill: Ink.butter)
        }
        .allowsHitTesting(false)
    }
}

/// Gold coins raining down the whole screen. `progress` runs 1 to 0.
struct CoinRain: View {
    let progress: Double
    var body: some View {
        Canvas { ctx, size in
            let t = 1 - progress
            for i in 0..<70 {
                // Fixed per coin: the rain is a pure function of progress.
                let a = Double((i * 73) % 101) / 101, b = Double((i * 37) % 97) / 97, c = Double((i * 19) % 89) / 89
                let y = (t * (1.1 + b) - c * 0.55) * size.height * 1.15
                guard y > -30, y < size.height + 30 else { continue }
                let x = a * size.width + sin(t * 9 + c * 6) * 18
                let r = 8 + 9 * b
                let turn = abs(cos(t * (10 + 12 * a) + c * 6))
                let rect = CGRect(x: x - r * turn, y: y - r, width: 2 * r * max(turn, 0.12), height: 2 * r)
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(Ink.ink))
                ctx.fill(Path(ellipseIn: rect), with: .color(Ink.butter))
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: rect.width * 0.28, dy: r * 0.5)), with: .color(Ink.cream))
            }
        }
        .opacity(min(1, progress * 3))
        .allowsHitTesting(false)
    }
}

/// One clear question before a run is thrown away: a stray tap on a phone
/// should not cost anyone an evening's progress.
struct NewGamePrompt: View {
    let yes: () -> Void
    let no: () -> Void
    var body: some View {
        ZStack {
            Ink.ink.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                CelText(text: "START A NEW GAME?", size: 30, fill: Ink.butter)
                CelText(text: "This run ends. Your prizes stay.", size: 18)
                HStack(spacing: 12) {
                    Button(action: no) { Pill(fill: Ink.mint, radius: 18) { CelText(text: "KEEP PLAYING", size: 20) } }.buttonStyle(.plain)
                    Button(action: yes) { Pill(fill: Ink.pink, radius: 18) { CelText(text: "NEW GAME", size: 20) } }.buttonStyle(.plain)
                }
            }
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: 22).fill(Ink.violet)
                RoundedRectangle(cornerRadius: 22).strokeBorder(Ink.butter, lineWidth: 4)
            }
        }
    }
}
