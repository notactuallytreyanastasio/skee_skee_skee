import SkeeCore
import SkeeRender
import SwiftUI

/// The pull machine over the lane: jackpot meters, a three-by-three window,
/// the bet, and a lever. Drag the lever down and let go, or tap SPIN.
struct MachineView: View {
    let m: HUDState.Machine
    let pull: () -> Void
    let setBet: (Bet) -> Void

    var body: some View {
        VStack(spacing: 8) {
            meters
            HStack(alignment: .center, spacing: 10) {
                window.frame(width: 210, height: 210)
                Lever(enabled: m.canPull, pull: pull).frame(width: 44, height: 200)
            }
            if m.free {
                CelText(text: "FREE GAME · x2 · \(m.freeLeft) MORE", size: 18, fill: Ink.butter)
            } else {
                bets
                Button(action: pull) {
                    Pill(fill: m.canPull ? Ink.mint : Ink.cream.opacity(0.5), radius: 18) {
                        CelText(text: m.canPull ? "SPIN" : "...", size: 24)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!m.canPull)
            }
        }
        .padding(12)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Ink.ink).offset(y: 5)
                RoundedRectangle(cornerRadius: 22).fill(Ink.violet)
                RoundedRectangle(cornerRadius: 22).strokeBorder(Ink.butter, lineWidth: 4)
            }
        }
    }

    /// Four progressive meters. Lit only at max bet: below it they show,
    /// dimmed, what you are not playing for.
    var meters: some View {
        HStack(spacing: 4) {
            ForEach(JackpotTier.allCases.reversed(), id: \.self) { t in
                VStack(spacing: 0) {
                    CelText(text: t.title, size: 10, fill: Self.tierColor(t))
                    CelText(text: "\(m.progressive.amount(t))", size: 14)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 8).fill(Ink.ink.opacity(0.55)))
                .opacity(m.bet.isMax ? 1 : 0.45)
            }
        }
        .overlay(alignment: .bottom) {
            if !m.bet.isMax && !m.free {
                CelText(text: "MAX BET FOR JACKPOTS", size: 9, fill: Ink.butter).offset(y: 9)
            }
        }
        .frame(width: 264)
    }

    static func tierColor(_ t: JackpotTier) -> Color {
        switch t {
        case .mini: Ink.sky
        case .minor: Ink.mint
        case .major: Ink.pink
        case .grand: Ink.butter
        }
    }

    var window: some View {
        GeometryReader { g in
            let cw = g.size.width / 3, ch = g.size.height / 3
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Ink.cream)
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { reel in
                        PullReel(reel: reel, position: m.positions.indices.contains(reel) ? m.positions[reel] : 0,
                                 teasing: m.teasing && reel == 2)
                            .frame(width: cw, height: g.size.height)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                // Reel dividers.
                ForEach(1..<3, id: \.self) { i in
                    Rectangle().fill(Ink.ink.opacity(0.35)).frame(width: 2).position(x: cw * Double(i), y: g.size.height / 2)
                }
                // Active lines as ticks at the edge; wins drawn through.
                ForEach(0..<m.bet.lines, id: \.self) { i in
                    let rows = Pull.lines[i]
                    Circle().fill(Self.lineColor(i)).overlay(Circle().stroke(Ink.ink, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                        .position(x: -7, y: ch * (Double(rows[0]) + 0.5))
                }
                ForEach(m.wins, id: \.line) { w in
                    Path { p in
                        for (reel, row) in Pull.lines[w.line].enumerated() {
                            let pt = CGPoint(x: cw * (Double(reel) + 0.5), y: ch * (Double(row) + 0.5))
                            if reel == 0 { p.move(to: CGPoint(x: 0, y: pt.y)); p.addLine(to: pt) } else { p.addLine(to: pt) }
                        }
                        p.addLine(to: CGPoint(x: g.size.width, y: ch * (Double(Pull.lines[w.line][2]) + 0.5)))
                    }
                    .stroke(Self.lineColor(w.line), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .shadow(color: Ink.ink, radius: 0, x: 0, y: 2)
                }
                RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.ink, lineWidth: 4)
                if m.teasing {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.butter, lineWidth: 4)
                        .frame(width: cw).position(x: cw * 2.5, y: g.size.height / 2)
                }
            }
        }
    }

    static func lineColor(_ i: Int) -> Color { [Ink.mult, Ink.sky, Ink.mint, Ink.butter, Ink.pink][i % 5] }

    var bets: some View {
        HStack(spacing: 6) {
            ForEach(Bet.allCases, id: \.self) { b in
                let can = m.affordable.contains(b)
                Button { if can { setBet(b) } } label: {
                    VStack(spacing: 0) {
                        CelText(text: "\(b.lines) LINE\(b.lines > 1 ? "S" : "")", size: 13)
                        CelText(text: b.cost == 0 ? "FREE" : "\(b.cost) TIX", size: 11, fill: can ? Ink.butter : Ink.cream.opacity(0.5))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 10).fill(m.bet == b ? Ink.pink : Ink.ink.opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(m.bet == b ? Ink.butter : .clear, lineWidth: 3))
                    .opacity(can ? 1 : 0.5)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One reel of the machine: the strip scrolls past three rows.
struct PullReel: View {
    let reel: Int
    let position: Double
    var teasing = false
    var body: some View {
        GeometryReader { g in
            let h = g.size.height / 3
            let base = position.rounded(.down)
            let frac = position - base
            ZStack(alignment: .top) {
                if teasing { Ink.butter.opacity(0.35) }
                ForEach(-1..<4, id: \.self) { k in
                    ReelSymbolView(symbol: Presentation.pullSymbol(reel: reel, at: base, row: k + Pull.strips[reel].count))
                        .padding(6)
                        .frame(width: g.size.width, height: h)
                        .offset(y: (Double(k) - frac) * h)
                }
            }
        }
    }
}

/// A machine symbol: the board's art for fruit, bells, bars, sevens and
/// diamonds; the clover for WILD; lettered coins for x2, x3 and BONUS.
struct ReelSymbolView: View {
    let symbol: ReelSymbol
    var body: some View {
        switch symbol {
        case .x2, .x3:
            coin(symbol == .x2 ? "2X" : "3X", fill: symbol == .x2 ? Ink.sky : Ink.mult, label: "WILD")
        case .bonus:
            ZStack {
                StarShape().fill(Ink.butter).overlay(StarShape().stroke(Ink.ink, lineWidth: 3))
                CelText(text: "BONUS", size: 11)
            }
        case .wild:
            ZStack(alignment: .bottom) {
                SymbolImage(symbol: .clover)
                CelText(text: "WILD", size: 11, fill: Ink.mint).offset(y: 4)
            }
        default:
            SymbolImage(symbol: symbol.target)
        }
    }

    func coin(_ text: String, fill: Color, label: String) -> some View {
        ZStack {
            Circle().fill(fill).overlay(Circle().strokeBorder(Ink.ink, lineWidth: 3))
            VStack(spacing: -2) {
                CelText(text: text, size: 20)
                CelText(text: label, size: 8)
            }
        }
    }
}

/// A slot-machine lever: drag the ball down past halfway and let go.
struct Lever: View {
    let enabled: Bool
    let pull: () -> Void
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            let travel = g.size.height - 44
            ZStack(alignment: .top) {
                Capsule().fill(Ink.ink.opacity(0.6)).frame(width: 10).frame(maxHeight: .infinity)
                Circle()
                    .fill(enabled ? Ink.mult : Ink.cream.opacity(0.5))
                    .overlay(Circle().strokeBorder(Ink.ink, lineWidth: 3))
                    .overlay(Circle().fill(.white.opacity(0.6)).frame(width: 10, height: 10).offset(x: -7, y: -7))
                    .frame(width: 44, height: 44)
                    .offset(y: drag)
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { v in if enabled { drag = min(travel, max(0, v.translation.height)) } }
                        .onEnded { _ in
                            if enabled && drag > travel * 0.5 { pull() }
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { drag = 0 }
                        })
            }
            .frame(width: g.size.width)
        }
    }
}
