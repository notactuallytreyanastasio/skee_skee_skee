import CoreGraphics
import SkeeCore

/// Shell-owned interaction state, as a plain value the renderer can draw and
/// the hit tester can read.
public struct UIState: Hashable, Sendable {
    public enum Screen: Hashable, Sendable { case title, game }
    public var screen: Screen = .title
    /// Current drag on the lane, for the aim guide.
    public var dragStart: CGPoint?
    public var dragNow: CGPoint?
    /// Prize-counter offer waiting for a hole to be tapped.
    public var selectedOffer: Int?
    /// Charm tapped once at the counter; a second tap sells it.
    public var selectedCharm: Int?
    /// 0 = flat open, 1 = folded to a steep ramp. From the hinge sensor.
    public var fold: Double = 0
    public var message: String?

    public init() {}
}

/// What a tap means. The shell turns intents into reducer actions or UI
/// state changes; it never inspects coordinates itself.
public enum Intent: Hashable, Sendable {
    case none
    case startRun
    case selectOffer(Int)
    case act(Action)
    case cancelSelection
    case selectCharm(Int)
}

/// Fixed rectangles for every tappable thing. Used by both the renderer and
/// the hit tester so they can never disagree.
public struct Rects: Sendable {
    public let layout: Layout

    public init(_ layout: Layout) { self.layout = layout }

    public var frameSlots: [CGRect] {
        (0..<3).map { CGRect(x: 18 + CGFloat($0) * 50, y: layout.trayRect.minY + 14, width: 44, height: 44) }
    }
    public var powerUpSlots: [CGRect] {
        let x0: CGFloat = layout.compact ? layout.size.width - 18 - 102 : 184
        return (0..<2).map { CGRect(x: x0 + CGFloat($0) * 54, y: layout.trayRect.minY + 14, width: 48, height: 48) }
    }
    public var charmSlots: [CGRect] {
        let gap: CGFloat = 6
        if layout.compact {
            let w = (layout.size.width - 36 - 4 * gap) / 5
            return (0..<5).map { CGRect(x: 18 + CGFloat($0) * (w + gap), y: layout.trayRect.minY + 86, width: w, height: 56) }
        }
        let w: CGFloat = 62
        let x0 = layout.size.width - 18 - 5 * w - 4 * gap
        return (0..<5).map { CGRect(x: x0 + CGFloat($0) * (w + gap), y: layout.trayRect.minY + 10, width: w, height: 62) }
    }

    /// The prize counter sits in the lane half; the board stays visible above
    /// so stamps and gilds can be aimed at a hole by tapping it.
    public var counter: CGRect {
        CGRect(x: 12, y: layout.hingeY + 10, width: layout.size.width - 24,
               height: layout.trayRect.minY - layout.hingeY - 18)
    }
    public var offerCards: [CGRect] {
        let c = counter
        let gap: CGFloat = 10
        let w = (c.width - 24 - 3 * gap) / 4
        return (0..<4).map { CGRect(x: c.minX + 12 + CGFloat($0) * (w + gap), y: c.minY + 48, width: w, height: c.height - 48 - 72) }
    }
    public var rerollButton: CGRect {
        CGRect(x: counter.minX + 12, y: counter.maxY - 60, width: counter.width / 2 - 18, height: 48)
    }
    public var leaveButton: CGRect {
        CGRect(x: counter.midX + 6, y: counter.maxY - 60, width: counter.width / 2 - 18, height: 48)
    }
    public var bigButton: CGRect {
        CGRect(x: layout.size.width / 2 - 130, y: layout.hingeY + 120, width: 260, height: 64)
    }
}

/// World position of each hole's reel window on the board: on the ring
/// band itself, out to the side where the band is widest on screen. Ring
/// reels are drawn on both sides (`mirror`); holes and pockets once.
public func reelAnchor(_ hole: Hole, board: BoardSpec = .standard, mirror: Bool = false) -> Vec2 {
    let c = board.ringCenter, w = board.ringWalls
    let side = mirror ? 1.0 : -1.0
    switch hole {
    case .ring50: return board.centerHole
    case .ring40: return Vec2(c.x + side * w[0] * 0.66, c.y - 0.012)
    case .ring30: return Vec2(c.x + side * (w[0] + w[1]) / 2, c.y)
    case .ring20: return Vec2(c.x + side * (w[1] + w[2]) / 2, c.y)
    case .ring10: return Vec2(c.x + side * (w[2] + w[3]) / 2, c.y)
    case .pocketLeft: return board.pockets[0].center
    case .pocketRight: return board.pockets[1].center
    case .gutter: return Vec2(0, -0.1)
    }
}

/// Every place a hole's reel is drawn (one or two).
public func reelAnchors(_ hole: Hole, board: BoardSpec = .standard) -> [Vec2] {
    switch hole {
    case .ring40, .ring30, .ring20, .ring10: [reelAnchor(hole, board: board), reelAnchor(hole, board: board, mirror: true)]
    default: [reelAnchor(hole, board: board)]
    }
}

/// Pure tap resolution.
public func intent(at p: CGPoint, layout: Layout, state: RunState, ui: UIState, busy: Bool) -> Intent {
    let rects = Rects(layout)
    if ui.screen == .title { return .startRun }
    switch state.phase {
    case .won, .lost:
        return busy ? .none : (rects.bigButton.insetBy(dx: -20, dy: -20).contains(p) ? .startRun : .none)
    case .throwing:
        guard !busy else { return .none }
        for (i, r) in rects.powerUpSlots.enumerated() where r.contains(p) && i < state.powerUps.count {
            return .act(.arm(i))
        }
        return .none
    case .prizeCounter(let counter):
        if let sel = ui.selectedOffer {
            if p.y < layout.hingeY {
                let proj = Projection(layout: layout, style: ArtStyle.forAnte(state.ante))
                let board = difficultyTable(ante: state.ante).board
                let near = BoardSetup.reelHoles.flatMap { h in reelAnchors(h, board: board).map { (h, dist(proj.board($0), p)) } }
                if let hit = near.min(by: { $0.1 < $1.1 }), hit.1 < 50 { return .act(.buy(sel, target: hit.0)) }
            }
            return .cancelSelection
        }
        for (i, r) in rects.offerCards.enumerated() where r.contains(p) && i < counter.offers.count {
            guard let offer = counter.offers[i] else { return .none }
            return offer.needsTarget ? .selectOffer(i) : .act(.buy(i, target: nil))
        }
        if rects.rerollButton.contains(p) { return .act(.reroll) }
        if rects.leaveButton.contains(p) { return .act(.leaveCounter) }
        for (i, r) in rects.charmSlots.enumerated() where r.contains(p) && i < state.charms.count {
            return ui.selectedCharm == i ? .act(.sell(i)) : .selectCharm(i)
        }
        return .cancelSelection
    }
}

func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
