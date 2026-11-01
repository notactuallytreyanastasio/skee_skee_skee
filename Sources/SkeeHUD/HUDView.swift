import SkeeCore
import SkeeRender
import SkeeScene
import SwiftUI

/// What the HUD can ask the shell to do.
public struct HUDActions {
    public var buy: (Int) -> Void = { _ in }
    public var selectOffer: (Int?) -> Void = { _ in }
    public var reroll: () -> Void = {}
    public var leave: () -> Void = {}
    public var tapCharm: (Int) -> Void = { _ in }
    public var arm: (Int) -> Void = { _ in }
    public var start: () -> Void = {}
    public var newRun: () -> Void = {}
    public var openShop: () -> Void = {}
    public var closeShop: () -> Void = {}
    public var buyPrize: (Prize) -> Void = { _ in }
    public var skipWalkthrough: () -> Void = {}
    public var gotIt: () -> Void = {}
    public var howToPlay: () -> Void = {}
    public var pull: () -> Void = {}
    public var setBet: (Bet) -> Void = { _ in }
    public var pickRoom: (Room) -> Void = { _ in }
    public var openHost: () -> Void = {}
    public var hostSay: (String) -> Void = { _ in }
    public var hostRetry: () -> Void = {}
    public var hostDeal: () -> Void = {}
    public var closeHost: () -> Void = {}
    public init() {}
}

// MARK: - The cel look, in SwiftUI

enum Ink {
    static let ink = Color(hex: Toon.ink)
    static let cream = Color(hex: 0xFFF8EC)
    static let pink = Color(hex: 0xFF6FA5)
    static let lilac = Color(hex: 0x9B83F2)
    static let violet = Color(hex: 0x6F55D6)
    static let butter = Color(hex: 0xFFD84D)
    static let sky = Color(hex: 0x5FC8FF)
    static let mint = Color(hex: 0x7EDC7A)
    static let chips = Color(hex: 0x3D8BFF)
    static let mult = Color(hex: 0xFF4D6D)
}

extension Color {
    init(hex v: UInt32) {
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Rounded black type with an ink outline and a hard drop, like the toon
/// kit's outlines.
struct CelText: View {
    let text: String
    var size: CGFloat
    var fill: Color = Ink.cream
    var body: some View {
        let t = Text(text).font(.system(size: size, weight: .black, design: .rounded)).monospacedDigit()
        let w = max(1.5, size * 0.08)
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) / 8 * 2 * .pi
                t.foregroundStyle(Ink.ink).offset(x: cos(a) * w, y: sin(a) * w + w * 0.6)
            }
            t.foregroundStyle(fill)
        }
        .fixedSize()
    }
}

/// A chunky toon panel: fill, ink border, ink drop beneath.
struct Pill<Content: View>: View {
    var fill: Color = Ink.lilac
    var radius: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius).fill(Ink.ink).offset(y: 4)
                    RoundedRectangle(cornerRadius: radius).fill(fill)
                    RoundedRectangle(cornerRadius: radius).strokeBorder(Ink.ink, lineWidth: 3)
                }
            }
    }
}

struct SymbolImage: View {
    let symbol: Symbol
    var body: some View {
        Image(decorative: Textures.symbol(symbol), scale: 2).resizable().aspectRatio(contentMode: .fit)
    }
}


// MARK: - HUD

public struct HUDView: View {
    let state: HUDState
    let actions: HUDActions

    public init(state: HUDState, actions: HUDActions = HUDActions()) {
        self.state = state
        self.actions = actions
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if state.screen == .title {
                    TitleCard(start: actions.start, shop: actions.openShop, howToPlay: actions.howToPlay, wallet: state.wallet,
                              pickRoom: actions.pickRoom, host: actions.openHost)
                } else {
                    VStack(spacing: 6) {
                        topBar
                        topSlot
                        if state.isBoss { CelText(text: state.bossBlurb, size: 12, fill: Ink.butter).padding(.horizontal, 20) }
                        Spacer()
                    }
                    .padding(.top, 8)
                    .allowsHitTesting(false)

                    sideTrays(geo.size)
                    meter(geo.size)
                    guide()
                    trail()
                    if let m = state.machine, state.counter == nil, state.over == nil {
                        MachineView(m: m, pull: actions.pull, setBet: actions.setBet)
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.74)
                    }
                    // The slot sits on the backboard under the rings: up top
                    // it hid the pockets and the 50, the symbols that matter most.
                    VStack(spacing: 4) { slot; hint }
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.445)
                        .allowsHitTesting(false)

                    if let t = state.tally { TallyView(tally: t).position(x: geo.size.width / 2, y: geo.size.height * 0.27).allowsHitTesting(false) }
                    ForEach(Array(state.popups.enumerated()), id: \.offset) { _, p in popup(p) }
                    if let b = state.banner { BannerView(banner: b).position(x: geo.size.width / 2, y: geo.size.height * 0.3).allowsHitTesting(false) }
                    if state.firstThrow && !state.busy && state.counter == nil && state.coach == nil && state.machine == nil {
                        VStack(spacing: 2) {
                            CelText(text: "thumb down on your line", size: 20)
                            CelText(text: "then flick straight up", size: 15, fill: Ink.butter)
                        }
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.62)
                        .allowsHitTesting(false)
                    }
                    if let c = state.counter {
                        CounterView(state: state, counter: c, actions: actions)
                            .frame(width: geo.size.width, height: geo.size.height * 0.5)
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.75)
                    }
                    if let over = state.over {
                        GameOverView(won: over.won, stats: over.stats, ante: state.ante, wallet: state.wallet,
                                     newRun: actions.newRun, shop: actions.openShop, host: actions.openHost)
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.5)
                    }
                }
                if state.screen == .game, let card = state.coach, !state.busy {
                    // Low over the ball tray, out of the flick's path; high
                    // when the prize counter fills the bottom half.
                    VStack {
                        if !card.high { Spacer() }
                        CoachView(card: card, skip: actions.skipWalkthrough, gotIt: actions.gotIt)
                            .frame(width: min(geo.size.width - 24, 420))
                        if card.high { Spacer() }
                    }
                    .padding(.vertical, card.high ? geo.size.height * 0.12 : 14)
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                if state.shopOpen {
                    PrizeShopView(wallet: state.wallet, buy: actions.buyPrize, close: actions.closeShop)
                }
                if let host = state.host {
                    HostView(host: host, say: actions.hostSay, retry: actions.hostRetry, deal: actions.hostDeal, close: actions.closeHost)
                }
            }
        }
    }

    var topBar: some View {
        HStack(alignment: .top) {
            Pill(fill: state.isBoss ? Ink.mult : Ink.lilac) {
                VStack(alignment: .leading, spacing: 0) {
                    CelText(text: "ANTE \(state.ante)/\(state.antes)", size: 11)
                    CelText(text: state.isBoss ? state.bossName : state.roundTitle, size: 14, fill: Ink.butter)
                }
            }
            Spacer()
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    CelText(text: "\(state.score)", size: 34)
                    CelText(text: "/ \(state.target)", size: 16, fill: Ink.butter)
                }
                ProgressTrack(fraction: Double(state.score) / Double(max(state.target, 1)))
                    .frame(width: 150, height: 10)
            }
            Spacer()
            Pill(fill: Ink.butter) {
                HStack(spacing: 6) {
                    TicketShape().fill(Ink.pink).overlay(TicketShape().stroke(Ink.ink, lineWidth: 2)).frame(width: 22, height: 14)
                    CelText(text: "\(state.tickets)", size: 18)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    /// The frame's targets, the centre row of its pull. Hit a hole showing
    /// one of them and the combo climbs.
    var topSlot: some View {
        VStack(spacing: 1) {
            if state.combo > 0 {
                CelText(text: "COMBO x\(state.combo) · hit one to keep it", size: 11, fill: Ink.butter)
            } else {
                CelText(text: "TARGETS · hit one = combo", size: 10)
            }
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(Ink.cream)
                        if state.targets[i] != .blank { SymbolImage(symbol: state.targets[i]).padding(3) }
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.ink, lineWidth: 2)
                    }
                    .frame(width: 27, height: 27)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).fill(state.combo > 0 ? Ink.butter : Ink.pink))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Ink.ink, lineWidth: 3))
        }
    }

    /// The slot machine: this frame's three reels, and the fever meter.
    var slot: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Ink.ink).offset(y: 3)
                        RoundedRectangle(cornerRadius: 10).fill(state.frame[i] == nil ? Ink.cream.opacity(0.75) : Ink.cream)
                        if let s = state.frame[i] { SymbolImage(symbol: s).padding(5) }
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.ink, lineWidth: 3)
                    }
                    .frame(width: 44, height: 44)
                }
            }
            HStack(spacing: 3) {
                ForEach(0..<state.heatMax, id: \.self) { i in
                    Circle()
                        .fill(state.fever ? Ink.butter : (i < state.heat ? Ink.mult : Ink.cream.opacity(0.5)))
                        .overlay(Circle().stroke(Ink.ink, lineWidth: 1.5))
                        .frame(width: 9, height: 9)
                }
                if state.fever { CelText(text: "FEVER", size: 11, fill: Ink.butter) }
                CelText(text: "  FRAME \(state.frameNumber)/\(state.framesTotal) · \(state.ballsLeft) BALLS", size: 11)
            }
        }
    }

    /// What the slot wants next, in words.
    @ViewBuilder var hint: some View {
        if let h = state.hint, !h.text.isEmpty {
            HStack(spacing: 5) {
                CelText(text: h.text, size: h.hot ? 18 : 14, fill: h.hot ? Ink.butter : Ink.cream)
                if let sym = h.symbol { SymbolImage(symbol: sym).frame(width: h.hot ? 34 : 28, height: h.hot ? 34 : 28) }
                if !h.after.isEmpty { CelText(text: h.after, size: h.hot ? 18 : 14, fill: h.hot ? Ink.butter : Ink.cream) }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(Ink.ink.opacity(0.6)))
        }
    }

    /// Where your last flicks landed on the power scale, so the flick can be
    /// learned: a thin gauge with a tick per throw, coloured by the result.
    func meter(_ size: CGSize) -> some View {
        let h = size.height * 0.3
        return ZStack(alignment: .bottom) {
            Capsule().fill(Ink.ink.opacity(0.35)).frame(width: 8, height: h)
            ForEach(Array(state.throwsMeter.enumerated()), id: \.offset) { i, m in
                let newest = i == state.throwsMeter.count - 1
                let c: Color = switch m.hole {
                case .gutter: Ink.mult
                case .ring50, .pocketLeft, .pocketRight: Ink.butter
                case .ring40, .ring30: Ink.mint
                default: Ink.sky
                }
                Capsule().fill(c).overlay(Capsule().stroke(Ink.ink, lineWidth: 1.5))
                    .frame(width: newest ? 22 : 14, height: newest ? 6 : 4)
                    .offset(y: -CGFloat(m.power) * h)
                    .opacity(newest ? 1 : 0.7)
            }
        }
        .frame(height: h, alignment: .bottom)
        .position(x: size.width - 14, y: size.height * 0.62)
        .allowsHitTesting(false)
    }

    /// Dashes from the ball straight up its line: where a straight flick
    /// goes. Brighter while the thumb is down.
    func guide() -> some View {
        Canvas { ctx, _ in
            guard let first = state.guide.first else { return }
            var p = Path(); p.move(to: first)
            for q in state.guide.dropFirst() { p.addLine(to: q) }
            let a = state.aiming ? 0.9 : 0.4
            let dash = StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 12])
            ctx.stroke(p, with: .color(Ink.ink.opacity(a * 0.6)), style: StrokeStyle(lineWidth: 8, lineCap: .round, dash: [2, 12]))
            ctx.stroke(p, with: .color(Ink.cream.opacity(a)), style: dash)
        }
        .allowsHitTesting(false)
    }

    func trail() -> some View {
        Canvas { ctx, _ in
            for (a, b) in zip(state.trail, state.trail.dropFirst()) {
                var p = Path(); p.move(to: a.0); p.addLine(to: b.0)
                let fade = 1 - b.1
                ctx.stroke(p, with: .color(Ink.ink.opacity(0.5 * fade)), style: StrokeStyle(lineWidth: 16 * fade + 2, lineCap: .round))
                ctx.stroke(p, with: .color(Ink.butter.opacity(0.9 * fade)), style: StrokeStyle(lineWidth: 10 * fade + 1, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    /// Charms down the left edge, specialty balls down the right, clear of
    /// the thumb's path up the middle.
    func sideTrays(_ size: CGSize) -> some View {
        ZStack {
            VStack(spacing: 8) {
                ForEach(Array(state.charms.enumerated()), id: \.offset) { i, c in
                    Button { actions.tapCharm(i) } label: { CharmToken(charm: c, selected: state.selectedCharm == i) }
                        .buttonStyle(.plain)
                }
            }
            .position(x: 30, y: size.height * 0.68)
            VStack(spacing: 8) {
                ForEach(Array(state.powerUps.enumerated()), id: \.offset) { i, p in
                    Button { actions.arm(i) } label: { PowerToken(power: p, armed: false) }.buttonStyle(.plain)
                }
                if let a = state.armed { PowerToken(power: a, armed: true) }
            }
            .position(x: size.width - 30, y: size.height * 0.68)
        }
    }

    func popup(_ p: HUDState.ScreenPopup) -> some View {
        let color: Color = switch p.kind {
        case .chips: Ink.sky
        case .mult: Ink.mult
        case .tickets, .jackpot: Ink.butter
        case .bad: Ink.mult
        }
        return CelText(text: p.text, size: p.kind == .jackpot ? 34 : 24, fill: color)
            .scaleEffect(1 + 0.3 * (1 - min(1, p.age * 4)))
            .opacity(1 - p.age * p.age)
            .position(x: p.at.x, y: p.at.y - 30 - 50 * p.age)
            .allowsHitTesting(false)
    }
}

struct ProgressTrack: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.ink)
                Capsule().fill(fraction >= 1 ? Ink.mint : Ink.sky)
                    .frame(width: max(6, g.size.width * min(1, fraction)))
                    .padding(2)
            }
        }
    }
}

struct TicketShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: 3)
        p.addEllipse(in: CGRect(x: r.minX - 3, y: r.midY - 3, width: 6, height: 6))
        p.addEllipse(in: CGRect(x: r.maxX - 3, y: r.midY - 3, width: 6, height: 6))
        return p
    }
}

struct CharmToken: View {
    let charm: Charm
    var selected = false
    var body: some View {
        let hue = Double(Charm.allCases.firstIndex(of: charm)!) / Double(Charm.allCases.count)
        let words = charm.name.split(separator: " ")
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Ink.ink).offset(y: 3)
            RoundedRectangle(cornerRadius: 12).fill(Color(hue: hue, saturation: 0.45, brightness: 1))
            RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Ink.mult : Ink.ink, lineWidth: selected ? 4 : 3)
            CelText(text: words.prefix(2).map { String($0.prefix(1)) }.joined(), size: 18)
        }
        .frame(width: 46, height: 46)
        .overlay(alignment: .trailing) {
            if selected {
                Pill(fill: Ink.mult, radius: 10) { CelText(text: "SELL +\(charm.cost / 2)", size: 12) }
                    .fixedSize().offset(x: 96)
            }
        }
    }
}

struct PowerToken: View {
    let power: PowerUp
    let armed: Bool
    var body: some View {
        let color: Color = switch power {
        case .goldenBall: Ink.butter
        case .feather: Ink.cream
        case .magnet: Ink.mult
        case .wildBall: Ink.mint
        case .hold: Ink.sky
        }
        ZStack {
            Circle().fill(Ink.ink).offset(y: 3)
            Circle().fill(color)
            Circle().strokeBorder(armed ? Ink.butter : Ink.ink, lineWidth: armed ? 4 : 3)
            CelText(text: String(power.name.prefix(1)), size: 18)
        }
        .frame(width: 44, height: 44)
        .overlay(alignment: .top) { if armed { CelText(text: "ARMED", size: 10, fill: Ink.butter).offset(y: -14) } }
    }
}

struct TallyView: View {
    let tally: HUDState.Tally
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                box("\(tally.chips)", Ink.chips)
                CelText(text: "×", size: 30)
                box(HUDState.num(tally.mult), Ink.mult)
            }
            CelText(text: tally.label, size: 15, fill: Ink.butter)
        }
    }
    func box(_ t: String, _ c: Color) -> some View {
        Pill(fill: c, radius: 14) { CelText(text: t, size: 30).frame(minWidth: 84) }
    }
}

struct BannerView: View {
    let banner: HUDState.Banner
    var body: some View {
        let inA = min(1, banner.progress * 6), outA = min(1, (1 - banner.progress) * 5)
        VStack(spacing: 4) {
            CelText(text: banner.title, size: 52, fill: Ink.butter)
            if !banner.sub.isEmpty { CelText(text: banner.sub.uppercased(), size: 16) }
        }
        .scaleEffect(0.6 + 0.4 * inA + 0.05 * sin(banner.progress * 20))
        .opacity(min(inA, outA))
    }
}

struct TitleCard: View {
    let start: () -> Void
    let shop: () -> Void
    let howToPlay: () -> Void
    let wallet: Wallet
    let pickRoom: (Room) -> Void
    let host: () -> Void
    var body: some View {
        ZStack {
            // Tap anywhere to play; the shop button sits on top of that.
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: start)
            VStack(spacing: 18) {
                Spacer().frame(height: 60)
                VStack(spacing: -10) {
                    CelText(text: "SKEE", size: 72, fill: Ink.butter)
                    CelText(text: "SKEE", size: 72, fill: Ink.pink)
                    CelText(text: "SKEE", size: 72, fill: Ink.sky)
                }
                .rotationEffect(.degrees(-6))
                .allowsHitTesting(false)
                Spacer()
                Pill(fill: Ink.mint, radius: 22) { CelText(text: "TAP TO PLAY", size: 28) }
                    .allowsHitTesting(false)
                VStack(spacing: 2) {
                    CelText(text: wallet.room.name.uppercased(), size: 17, fill: Ink.butter)
                    CelText(text: wallet.room.blurb, size: 12)
                        .multilineTextAlignment(.center).frame(maxWidth: 320)
                }
                .allowsHitTesting(false)
                HStack(spacing: 10) {
                    Button(action: shop) {
                        Pill(fill: Ink.butter, radius: 18) { CelText(text: "PRIZE SHOP · \(wallet.balance)", size: 18) }
                    }
                    .buttonStyle(.plain)
                    Button(action: howToPlay) {
                        Pill(fill: Ink.sky, radius: 18) { CelText(text: "HOW TO PLAY", size: 18) }
                    }
                    .buttonStyle(.plain)
                }
                RoomPicker(wallet: wallet, pick: pickRoom, host: host)
                PrizeShelfStrip(owned: wallet.owned).allowsHitTesting(false)
                Spacer().frame(height: 60)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GameOverView: View {
    let won: Bool
    let stats: RunStats
    let ante: Int
    let wallet: Wallet
    let newRun: () -> Void
    let shop: () -> Void
    let host: () -> Void
    var body: some View {
        Pill(fill: won ? Ink.mint : Ink.pink, radius: 26) {
            VStack(spacing: 10) {
                CelText(text: won ? "YOU BEAT THE ARCADE" : "GAME OVER", size: 32, fill: Ink.butter)
                CelText(text: "ANTE \(ante)", size: 18)
                CelText(text: "BEST FRAME \(stats.bestFrame)", size: 16)
                CelText(text: "JACKPOTS \(stats.jackpots)  ·  RATTLES \(stats.rattles)", size: 14)
                CelText(text: "+\(winnings(stats: stats, won: won)) WINNINGS", size: 20, fill: Ink.butter)
                HStack(spacing: 10) {
                    Button(action: newRun) {
                        Pill(fill: Ink.butter, radius: 18) { CelText(text: "NEW RUN", size: 22) }
                    }
                    .buttonStyle(.plain)
                    Button(action: shop) {
                        Pill(fill: Ink.sky, radius: 18) { CelText(text: "PRIZES \(wallet.balance)", size: 18) }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
                if let due = wallet.compDue {
                    Button(action: host) {
                        Pill(fill: Ink.butter, radius: 16) { CelText(text: "THE HOST WANTS A WORD · \(due.name.uppercased())", size: 13) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}
