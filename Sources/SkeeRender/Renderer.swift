import CoreGraphics
import Foundation
import SkeeCore

/// Draws one frame. Stateless: everything comes in through the arguments.
/// The context must be y-down with its origin at the top left (SwiftUI
/// Canvas already is; the CLI flips its bitmap before calling).
public enum Renderer {
    /// Pixel style draws the whole scene at 1/pixelScale resolution with
    /// antialiasing off, then blows it up with nearest-neighbour sampling.
    public static let pixelScale: CGFloat = 2

    public static func draw(_ p: Presentation, ui: UIState, layout: Layout, in ctx: CGContext) {
        if let (from, to, u) = p.restyleProgress {
            drawStyled(from, p, ui, layout, ctx)
            // Iris wipe from the hinge: the new era grows out of the fold.
            let c = CGPoint(x: layout.size.width / 2, y: layout.hingeY)
            let maxR = hypot(layout.size.width, layout.size.height)
            let r = maxR * CGFloat(min(1, max(0, (u - 0.15) / 0.7)))
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ctx.clip()
            drawStyled(to, p, ui, layout, ctx)
            ctx.restoreGState()
            let seam = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
            ctx.addPath(seam); ctx.setStrokeColor(RGB(0xFFFFFF).cg(0.9)); ctx.setLineWidth(6); ctx.strokePath()
            let pen = Pen(ctx: ctx, style: to, pal: Palette.of(to), time: p.clock)
            pen.panel(CGRect(x: 60, y: layout.hingeY - 46, width: layout.size.width - 120, height: 92))
            pen.text(to.title, at: CGPoint(x: layout.size.width / 2, y: layout.hingeY), size: 36,
                     color: Palette.of(to).text, align: .center)
            return
        }
        drawStyled(p.style, p, ui, layout, ctx)
    }

    static func drawStyled(_ style: ArtStyle, _ p: Presentation, _ ui: UIState, _ layout: Layout, _ ctx: CGContext) {
        guard style == .pixel else {
            SceneDrawer(p: p, ui: ui, layout: layout, pen: Pen(ctx: ctx, style: style, pal: .of(style), time: p.clock)).draw()
            return
        }
        let k = pixelScale
        let w = Int((layout.size.width / k).rounded(.up)), h = Int((layout.size.height / k).rounded(.up))
        guard let low = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        low.translateBy(x: 0, y: CGFloat(h))
        low.scaleBy(x: 1 / k, y: -1 / k)
        low.setShouldAntialias(false)
        low.interpolationQuality = .none
        SceneDrawer(p: p, ui: ui, layout: layout, pen: Pen(ctx: low, style: .pixel, pal: .of(.pixel), time: p.clock)).draw()
        guard let img = low.makeImage() else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.translateBy(x: 0, y: CGFloat(h) * k)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: CGFloat(w) * k, height: CGFloat(h) * k))
        ctx.restoreGState()
    }
}

/// Composes a frame from the presentation in one style.
struct SceneDrawer {
    let p: Presentation
    let ui: UIState
    let layout: Layout
    let pen: Pen
    var ctx: CGContext { pen.ctx }
    var pal: Palette { pen.pal }
    var s: RunState { p.shown }
    var proj: Projection { Projection(layout: layout, style: pen.style) }
    var rects: Rects { Rects(layout) }
    var board: BoardSpec { difficultyTable(ante: s.ante).board }

    func draw() {
        ctx.saveGState()
        if p.shake > 0 {
            let a = CGFloat(p.shake) * 7
            ctx.translateBy(x: sin(p.clock * 71) * a, y: cos(p.clock * 53) * a)
        }
        background()
        drawBoard()
        drawHinge()
        drawLane()
        drawBall()
        if ui.screen == .title {
            title()
            ctx.restoreGState()
            return
        }
        hud()
        tray()
        tally()
        popups()
        if case .prizeCounter(let c) = s.phase, !p.isBusy { counter(c) }
        if case .lost = s.phase, !p.isBusy { gameOver(won: false) }
        if case .won = s.phase, !p.isBusy { gameOver(won: true) }
        bannerOverlay()
        ctx.restoreGState()
        if p.flash > 0 {
            ctx.setFillColor(RGB(0xFFFFFF).cg(CGFloat(p.flash) * 0.45))
            ctx.fill(CGRect(origin: .zero, size: layout.size))
        }
    }

    // MARK: background, board, hinge, lane

    func background() {
        let full = CGRect(origin: .zero, size: layout.size)
        switch pen.style {
        case .depth, .neon:
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [pal.background.cg(), pal.backgroundDeep.cg()] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: full.midX, y: layout.hingeY), startRadius: 0,
                                   endCenter: CGPoint(x: full.midX, y: layout.hingeY), endRadius: full.height * 0.7,
                                   options: [.drawsAfterEndLocation])
            if pen.style == .neon {
                // Perspective grid on the floor of the void.
                ctx.setStrokeColor(pal.ringZones[1].cg(0.25)); ctx.setLineWidth(1)
                for i in 0..<12 {
                    let y = layout.hingeY + pow(CGFloat(i) / 11, 1.8) * (layout.size.height - layout.hingeY)
                    ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: full.maxX, y: y))
                }
                ctx.strokePath()
            }
        case .cel:
            ctx.setFillColor(pal.background.cg()); ctx.fill(full)
            // Comic sunburst behind the board.
            let c = CGPoint(x: full.midX, y: layout.hingeY * 0.55)
            ctx.setFillColor(pal.backgroundDeep.cg())
            for i in 0..<16 where i % 2 == 0 {
                let a0 = Double(i) / 16 * 2 * .pi + p.clock * 0.05, a1 = a0 + 2 * .pi / 16
                ctx.move(to: c)
                ctx.addLine(to: CGPoint(x: c.x + cos(a0) * 900, y: c.y + sin(a0) * 900))
                ctx.addLine(to: CGPoint(x: c.x + cos(a1) * 900, y: c.y + sin(a1) * 900))
                ctx.closePath()
            }
            ctx.fillPath()
        case .pixel:
            ctx.setFillColor(pal.background.cg()); ctx.fill(full)
            // Starfield, deterministic.
            var rng = SplitMix64(seed: 77)
            ctx.setFillColor(pal.textDim.cg(0.6))
            for _ in 0..<60 {
                let x = rng.nextUnit() * Double(full.width), y = rng.nextUnit() * Double(full.height)
                ctx.fill(CGRect(x: x, y: y, width: 3, height: 3))
            }
        }
    }

    func polygon(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: pts)
        path.closeSubpath()
        return path
    }

    /// A circle on the board, projected (an ellipse in flat styles, a
    /// foreshortened oval in depth).
    func boardCircle(_ c: Vec2, _ r: Double, segments: Int = 56) -> CGPath {
        polygon((0..<segments).map { i in
            let a = Double(i) / Double(segments) * 2 * .pi
            return proj.board(Vec2(c.x + cos(a) * r, c.y + sin(a) * r))
        })
    }

    func drawBoard() {
        let hb = board.width / 2, H = board.height
        let surface = polygon([proj.board(Vec2(-hb, 0)), proj.board(Vec2(hb, 0)),
                               proj.board(Vec2(hb, H)), proj.board(Vec2(-hb, H))])
        pen.fill(surface, pal.boardFelt, light: false)
        if pen.style == .depth {
            // Felt texture: faint diagonal weave.
            ctx.saveGState(); ctx.addPath(surface); ctx.clip()
            ctx.setStrokeColor(RGB(0x000000).cg(0.08)); ctx.setLineWidth(1)
            var x: CGFloat = -layout.size.width
            while x < layout.size.width { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x + 400, y: 400)); x += 6 }
            ctx.strokePath(); ctx.restoreGState()
        }
        // Backwall.
        let back = polygon([proj.board(Vec2(-hb, H - 0.03)), proj.board(Vec2(hb, H - 0.03)),
                            proj.board(Vec2(hb, H)), proj.board(Vec2(-hb, H))])
        pen.fill(back, pal.ringLip.darker(0.3))

        // Ring zones, outermost first, then the lips on top.
        let c = board.ringCenter
        for (i, wall) in board.ringWalls.enumerated().reversed() {
            pen.fill(boardCircle(c, wall), pal.ringZones[i], light: pen.style == .cel)
        }
        for wall in board.ringWalls {
            let lip = boardCircle(c, wall)
            switch pen.style {
            case .neon: pen.glow(lip, pal.ringLip, width: 2)
            case .cel: pen.ink(lip, width: 5); ctx.addPath(lip); ctx.setStrokeColor(pal.ringLip.cg()); ctx.setLineWidth(2); ctx.strokePath()
            case .depth:
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 4, color: RGB(0x000000).cg(0.6))
                ctx.addPath(lip); ctx.setStrokeColor(pal.ringLip.cg()); ctx.setLineWidth(4); ctx.strokePath()
                ctx.restoreGState()
                ctx.addPath(lip); ctx.setStrokeColor(pal.ringLip.lighter(0.5).cg(0.8)); ctx.setLineWidth(1); ctx.strokePath()
            case .pixel:
                ctx.addPath(lip); ctx.setStrokeColor(pal.ringLip.cg()); ctx.setLineWidth(3); ctx.strokePath()
            }
        }

        // Holes with their reels.
        for hole in [Hole.ring50, .pocketLeft, .pocketRight] {
            let (center, radius): (Vec2, Double) = hole == .ring50
                ? (board.centerHole, board.centerHoleRadius)
                : (board.pockets.first { $0.hole == hole }!.center, board.pockets.first { $0.hole == hole }!.radius)
            let path = boardCircle(center, radius * 1.15, segments: 32)
            ctx.addPath(path); ctx.setFillColor(pal.hole.cg()); ctx.fillPath()
            if pen.style == .neon { pen.glow(path, hole == .ring50 ? pal.mult : pal.tickets, width: 1.5) }
            else { ctx.addPath(path); ctx.setStrokeColor(pal.ringLip.darker(0.2).cg()); ctx.setLineWidth(2); ctx.strokePath() }
            let sc = proj.board(center)
            let size = max(22, path.boundingBox.height * 1.1)
            reelWindow(hole, CGRect(x: sc.x - size / 2, y: sc.y - size / 2, width: size, height: size), framed: false)
            label("\(board.chipsLabel(hole, setup: s.setup))", at: CGPoint(x: sc.x, y: sc.y - size / 2 - 9), small: true)
        }
        for hole in [Hole.ring40, .ring30, .ring20, .ring10] {
            for anchor in reelAnchors(hole, board: board) {
                let a = proj.board(anchor)
                let scale = proj.boardDepth(anchor.y)
                let band = CGFloat(board.ringWalls[1] - board.ringWalls[0]) * proj.hingeScale
                let w = min(hole == .ring40 ? 40 : 46, band * 0.92) * scale, h = min(36, band * 0.72) * scale
                let r = CGRect(x: a.x - w / 2, y: a.y - h / 2 + 6, width: w, height: h)
                reelWindow(hole, r, framed: true)
                label(board.chipsLabel(hole, setup: s.setup), at: CGPoint(x: a.x, y: r.minY - 9), small: true)
            }
        }
        // The dead zone below the rings drains to the gutter.
        let gutter = polygon([proj.board(Vec2(-hb, 0)), proj.board(Vec2(hb, 0)),
                              proj.board(Vec2(hb, 0.035)), proj.board(Vec2(-hb, 0.035))])
        ctx.addPath(gutter); ctx.setFillColor(pal.hole.cg(0.7)); ctx.fillPath()

        if ui.selectedOffer != nil {
            let pulse = 0.5 + 0.5 * sin(p.clock * 8)
            for hole in BoardSetup.reelHoles {
                for anchor in reelAnchors(hole, board: board) {
                    let a = proj.board(anchor)
                    let ring = CGPath(ellipseIn: CGRect(x: a.x - 30, y: a.y - 24, width: 60, height: 52), transform: nil)
                    ctx.addPath(ring); ctx.setStrokeColor(pal.tickets.cg(0.5 + 0.5 * pulse)); ctx.setLineWidth(3); ctx.strokePath()
                }
            }
        }
    }

    func label(_ t: String, at pt: CGPoint, small: Bool) {
        pen.text(t, at: pt, size: small ? 12 : 15, color: pal.text, align: .center)
    }

    /// A reel window showing the hole's symbol; scrolls while spinning.
    func reelWindow(_ hole: Hole, _ r: CGRect, framed: Bool) {
        let strip = s.setup.reel(hole)
        let pos = p.reelPositions[hole] ?? 0
        let n = strip.count
        let base = Int(floor(pos))
        let frac = CGFloat(pos - floor(pos))
        if framed {
            pen.panel(r.insetBy(dx: -2, dy: -2), fill: pal.panel.lighter(pen.style == .cel ? 0 : 0.1), radius: 5)
        }
        ctx.saveGState()
        ctx.clip(to: r)
        let g = r.insetBy(dx: r.width * 0.1, dy: r.height * 0.06)
        let cur = strip[((base % n) + n) % n], next = strip[(((base + 1) % n) + n) % n]
        pen.glyph(cur, in: CGRect(x: g.midX - g.height / 2, y: g.minY - frac * r.height, width: g.height, height: g.height))
        if frac > 0.001 {
            pen.glyph(next, in: CGRect(x: g.midX - g.height / 2, y: g.minY + (1 - frac) * r.height, width: g.height, height: g.height))
        }
        ctx.restoreGState()
        if let gild = s.setup.gild[hole], gild > 0 {
            pen.text("+\(gild)", at: CGPoint(x: r.maxX + 16, y: r.midY), size: 11, color: pal.tickets, align: .center)
        }
    }

    func drawHinge() {
        let y = layout.hingeY
        let band = CGRect(x: 0, y: y - 7, width: layout.size.width, height: 14)
        let L = Table.standard.lane.length
        let left = proj.lane(x: -board.width / 2, s: L), right = proj.lane(x: board.width / 2, s: L)
        let ramp = CGRect(x: left.x - 6, y: y - 9, width: right.x - left.x + 12, height: 18)
        switch pen.style {
        case .neon:
            pen.glow(CGPath(rect: ramp, transform: nil), pal.hinge, width: 1.5)
        case .depth:
            ctx.setFillColor(RGB(0x000000).cg(0.5)); ctx.fill(band)
            pen.fill(CGPath(roundedRect: ramp, cornerWidth: 9, cornerHeight: 9, transform: nil), pal.hinge)
        default:
            ctx.setFillColor(pal.outline.cg(0.6)); ctx.fill(band)
            pen.fill(CGPath(rect: ramp, transform: nil), pal.hinge)
        }
        // Chevrons: the ramp lifts the ball over the fold.
        ctx.setStrokeColor((pen.style == .neon ? pal.hinge : pal.outline).cg(0.55)); ctx.setLineWidth(2)
        var x = ramp.minX + 14
        while x < ramp.maxX - 10 {
            ctx.move(to: CGPoint(x: x - 6, y: y + 4)); ctx.addLine(to: CGPoint(x: x, y: y - 3)); ctx.addLine(to: CGPoint(x: x + 6, y: y + 4))
            x += 26
        }
        ctx.strokePath()
        if ui.fold > 0.02 {
            let deg = Int((Table.standard.hinge.launchAngle(fold: ui.fold) * 180 / .pi).rounded())
            pen.text("RAMP \(deg)", at: CGPoint(x: ramp.maxX - 4, y: y + 22), size: 12, color: pal.hinge, align: .right)
        }
    }

    func drawLane() {
        let L = Table.standard.lane.length, hw = board.width / 2
        let quad = polygon([proj.lane(x: -hw, s: 0), proj.lane(x: hw, s: 0), proj.lane(x: hw, s: L), proj.lane(x: -hw, s: L)])
        pen.fill(quad, pal.lane, light: pen.style != .pixel)
        // Boards of the alley.
        ctx.saveGState(); ctx.addPath(quad); ctx.clip()
        let planks = 9
        for i in 1..<planks {
            let x = -hw + Double(i) / Double(planks) * 2 * hw
            let path = CGMutablePath()
            path.move(to: proj.lane(x: x, s: 0)); path.addLine(to: proj.lane(x: x, s: L))
            ctx.addPath(path)
            ctx.setStrokeColor(pal.laneLine.cg(pen.style == .neon ? 0.5 : 0.45)); ctx.setLineWidth(pen.style == .pixel ? 3 : 1.5)
            ctx.strokePath()
        }
        // Aiming dots and arrows, like a bowling lane.
        for (i, x) in [-0.2, -0.1, 0, 0.1, 0.2].enumerated() {
            let s0 = 0.55 + (i == 2 ? 0.2 : abs(x) * -0.6 + 0.12)
            let tip = proj.lane(x: x, s: s0 + 0.12), l = proj.lane(x: x - 0.025, s: s0), r = proj.lane(x: x + 0.025, s: s0)
            let arrow = polygon([tip, r, l])
            if pen.style == .neon { pen.glow(arrow, pal.laneLine, width: 1) }
            else { ctx.addPath(arrow); ctx.setFillColor(pal.laneLine.darker(0.2).cg()); ctx.fillPath() }
        }
        ctx.restoreGState()
        if pen.style != .pixel { pen.ink(quad, width: pen.style == .cel ? 4 : 1) }
        // Foul line.
        let foul = CGMutablePath()
        foul.move(to: proj.lane(x: -hw, s: 0.25)); foul.addLine(to: proj.lane(x: hw, s: 0.25))
        pen.line(foul, pal.bad, width: 2)
    }

    // MARK: ball and aim

    func drawBall() {
        for (i, t) in p.trail.enumerated() where pen.style != .pixel {
            let (b, _, r) = proj.place(t)
            let a = CGFloat(i + 1) / CGFloat(p.trail.count + 1)
            ctx.setFillColor((pen.style == .neon ? pal.ballShade : pal.ball).cg(a * 0.35))
            ctx.fillEllipse(in: CGRect(x: b.x - r * a, y: b.y - r * a, width: 2 * r * a, height: 2 * r * a))
        }
        if let sample = p.ball {
            let (b, sh, r) = proj.place(sample)
            pen.shadow(sh, r * 0.9, alpha: 1)
            pen.sphere(b, r, pal.ball, shade: pal.ballShade)
            return
        }
        guard ui.screen == .game, case .throwing = s.phase, !p.isBusy else { return }
        // The next ball waits at the release line, under your thumb if dragging.
        let rest = proj.lane(x: 0, s: 0.12)
        let at = ui.dragNow.map { CGPoint(x: $0.x, y: min(max($0.y, layout.hingeY + 20), layout.laneRect.maxY)) } ?? rest
        let r = proj.ballRadius(alongBoard: nil, s: 0.1, z: 0) * 1.25
        pen.shadow(CGPoint(x: at.x, y: at.y + r * 0.6), r, alpha: 1)
        pen.sphere(at, r, s.round.armed == .goldenBall ? pal.tickets : pal.ball, shade: pal.ballShade)
        if let start = ui.dragStart, let now = ui.dragNow, now.y < start.y - 4 {
            let dir = CGPoint(x: now.x - start.x, y: now.y - start.y)
            let len = hypot(dir.x, dir.y)
            let guide = CGMutablePath()
            guide.move(to: now)
            guide.addLine(to: CGPoint(x: now.x + dir.x / len * 220, y: now.y + dir.y / len * 220))
            ctx.saveGState()
            ctx.setLineDash(phase: CGFloat(p.clock * 40), lengths: [8, 8])
            pen.line(guide, pal.tickets, width: 3)
            ctx.restoreGState()
        } else if s.round.frames.isEmpty && s.round.currentBalls.isEmpty && s.ante == 1 && s.round.kind == .warmup {
            let a = 0.5 + 0.5 * sin(p.clock * 4)
            pen.text("FLICK UP OVER THE HINGE", at: CGPoint(x: layout.size.width / 2, y: at.y - 46), size: 18,
                     color: pal.text.mix(pal.tickets, CGFloat(a)), align: .center)
        }
    }

    // MARK: HUD and tray

    func hud() {
        let w = layout.size.width
        let bar = CGRect(x: 8, y: 6, width: w - 16, height: layout.hudHeight - 10)
        pen.panel(bar, radius: 12)
        let shownScore = s.round.score + p.talliedBonus + (p.tallyProgress.map { partialTotal($0.0, $0.1) } ?? 0)
        let isBoss = s.round.kind == .boss
        pen.text("ANTE \(s.ante)/\(s.config.antes)", at: CGPoint(x: bar.minX + 14, y: bar.minY + 16), size: 14, color: pal.textDim)
        pen.text(isBoss ? s.boss.name.uppercased() : s.round.kind.title.uppercased(), at: CGPoint(x: bar.minX + 14, y: bar.minY + 37),
                 size: 16, color: isBoss ? pal.bad : pal.text)
        pen.text("\(shownScore)", at: CGPoint(x: w / 2 - 6, y: bar.minY + 20), size: 26, color: pal.text, align: .right)
        pen.text("/ \(s.round.target)", at: CGPoint(x: w / 2 + 4, y: bar.minY + 20), size: 18, color: pal.textDim)
        // Progress to target.
        let track = CGRect(x: w / 2 - 110, y: bar.minY + 38, width: 220, height: 8)
        ctx.setFillColor(pal.outline.cg(0.5)); ctx.fill(track)
        let frac = min(1, CGFloat(shownScore) / CGFloat(max(s.round.target, 1)))
        ctx.setFillColor((frac >= 1 ? pal.good : pal.chips).cg()); ctx.fill(CGRect(x: track.minX, y: track.minY, width: track.width * frac, height: track.height))
        // Tickets.
        ticketIcon(CGRect(x: bar.maxX - 92, y: bar.minY + 8, width: 26, height: 18))
        pen.text("\(s.tickets)", at: CGPoint(x: bar.maxX - 14, y: bar.minY + 17), size: 18, color: pal.tickets, align: .right)
        // Jackpot meter: one bulb per point of heat.
        let n = s.config.feverHeat
        for i in 0..<n {
            let lit = i < s.heat || s.fever
            let c = CGPoint(x: bar.maxX - 96 + CGFloat(i) * 8.5, y: bar.minY + 40)
            let rr: CGFloat = 3
            let bulb = CGPath(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr), transform: nil)
            if lit {
                if pen.style == .neon { pen.glow(bulb, pal.mult, width: 1) }
                ctx.addPath(bulb); ctx.setFillColor((s.fever ? pal.tickets : pal.mult).cg()); ctx.fillPath()
            } else {
                ctx.addPath(bulb); ctx.setFillColor(pal.textDim.cg(0.4)); ctx.fillPath()
            }
        }
        if s.fever {
            pen.text("FEVER", at: CGPoint(x: bar.maxX - 54, y: bar.minY + 52), size: 11, color: pal.tickets, align: .center)
        }
        if isBoss {
            pen.text(s.boss.blurb, at: CGPoint(x: w / 2, y: layout.hudHeight + 12), size: 12, color: pal.bad, align: .center, bold: false)
        }
    }

    func ticketIcon(_ r: CGRect) {
        let t = CGMutablePath()
        t.addRoundedRect(in: r, cornerWidth: 3, cornerHeight: 3)
        pen.fill(t, pal.tickets)
        ctx.setFillColor(pal.outline.cg(0.6))
        ctx.fillEllipse(in: CGRect(x: r.minX - 3, y: r.midY - 3, width: 6, height: 6))
        ctx.fillEllipse(in: CGRect(x: r.maxX - 3, y: r.midY - 3, width: 6, height: 6))
    }

    func tray() {
        let tr = layout.trayRect
        ctx.setFillColor(pal.backgroundDeep.cg(pen.style == .cel ? 0.25 : 0.85)); ctx.fill(tr)
        if pen.style == .neon {
            let edge = CGMutablePath(); edge.move(to: CGPoint(x: 0, y: tr.minY)); edge.addLine(to: CGPoint(x: tr.maxX, y: tr.minY))
            pen.glow(edge, pal.laneLine, width: 1)
        }
        // The payline: this frame's symbols so far.
        let balls: [BallRecord] = p.tallyProgress?.0.balls ?? s.round.currentBalls
        for (i, r) in rects.frameSlots.enumerated() {
            pen.panel(r, fill: pal.panel.lighter(0.08), radius: 6)
            if i < balls.count { pen.glyph(balls[i].symbol, in: r.insetBy(dx: 6, dy: 6)) }
        }
        let left = s.round.ballsLeft
        pen.text("\(left) BALL\(left == 1 ? "" : "S")  FRAME \(min(s.round.frames.count + 1, s.round.framesTotal))/\(s.round.framesTotal)",
                 at: CGPoint(x: 18, y: tr.minY + 76), size: 12, color: pal.textDim)
        // Specialty balls.
        for (i, r) in rects.powerUpSlots.enumerated() {
            pen.panel(r, fill: pal.panel, radius: 24)
            if i < s.powerUps.count {
                powerUpIcon(s.powerUps[i], in: r.insetBy(dx: 9, dy: 9))
            }
        }
        if let armed = s.round.armed {
            pen.text("ARMED: \(armed.name.uppercased())", at: CGPoint(x: rects.powerUpSlots[0].minX, y: tr.minY + 76), size: 11, color: pal.tickets)
        }
        // Charms.
        for (i, r) in rects.charmSlots.enumerated() {
            if i < s.charms.count {
                charmToken(s.charms[i], in: r, selected: ui.selectedCharm == i)
            } else {
                let slot = CGPath(roundedRect: r.insetBy(dx: 4, dy: 4), cornerWidth: 8, cornerHeight: 8, transform: nil)
                ctx.addPath(slot); ctx.setStrokeColor(pal.textDim.cg(0.4)); ctx.setLineWidth(1.5)
                ctx.setLineDash(phase: 0, lengths: [4, 4]); ctx.strokePath(); ctx.setLineDash(phase: 0, lengths: [])
            }
        }
    }

    func powerUpIcon(_ pu: PowerUp, in r: CGRect) {
        let c = CGPoint(x: r.midX, y: r.midY)
        let color: RGB = switch pu {
        case .goldenBall: pal.tickets
        case .feather: RGB(0xE0F0FF)
        case .magnet: pal.mult
        case .wildBall: pal.good
        case .hold: pal.chips
        }
        pen.sphere(c, r.width / 2, color, shade: color.darker(0.4))
        let letter = switch pu {
        case .goldenBall: "G"
        case .feather: "F"
        case .magnet: "M"
        case .wildBall: "W"
        case .hold: "H"
        }
        pen.text(letter, at: c, size: 14, color: pal.outline == RGB(0x000000) ? pal.text : pal.outline, align: .center)
    }

    func charmToken(_ charm: Charm, in r: CGRect, selected: Bool) {
        let hue = Double(Charm.allCases.firstIndex(of: charm)!) / Double(Charm.allCases.count)
        let color = hsv(hue, 0.55, 0.95)
        pen.panel(r.insetBy(dx: 2, dy: 2), fill: color, edge: selected ? pal.bad : pal.panelEdge, radius: 10)
        let words = charm.name.split(separator: " ")
        let mono = words.prefix(2).map { String($0.prefix(1)) }.joined()
        pen.text(mono, at: CGPoint(x: r.midX, y: r.midY - 6), size: 22, color: pal.outline == RGB(0x000000) ? RGB(0x05010F) : pal.outline, align: .center)
        if pen.style != .pixel {
            pen.text(String(words.last ?? ""), at: CGPoint(x: r.midX, y: r.maxY - 12), size: 9, color: RGB(0x111111), align: .center, bold: false)
        }
        if selected {
            pen.text("TAP TO SELL +\(charm.cost / 2)", at: CGPoint(x: r.midX, y: r.minY - 10), size: 10, color: pal.bad, align: .center)
        }
    }

    func hsv(_ h: Double, _ sat: Double, _ v: Double) -> RGB {
        let i = Int(h * 6) % 6, f = h * 6 - floor(h * 6)
        let pp = v * (1 - sat), q = v * (1 - f * sat), t = v * (1 - (1 - f) * sat)
        let (r, g, b): (Double, Double, Double) = switch i {
        case 0: (v, t, pp)
        case 1: (q, v, pp)
        case 2: (pp, v, t)
        case 3: (pp, q, v)
        case 4: (t, pp, v)
        default: (v, pp, q)
        }
        return RGB(r: CGFloat(r), g: CGFloat(g), b: CGFloat(b))
    }

    // MARK: scoring juice

    func partialTotal(_ f: FrameScore, _ k: Int) -> Int {
        let (c, m) = fold(f.steps.prefix(k))
        return k >= f.steps.count ? f.total : Int(Double(c) * m)
    }

    func fold<S: Sequence>(_ steps: S) -> (Int, Double) where S.Element == ScoreStep {
        var chips = 0, mult = 1.0
        for st in steps {
            switch st.effect {
            case .base(let c, let m): chips = c; mult = m
            case .chips(let c): chips += c
            case .mult(let m): mult += m
            case .timesMult(let x): mult *= x
            case .tickets, .note: break
            }
        }
        return (chips, mult)
    }

    /// Balatro-style counter: chips box times mult box, filling in step by step.
    func tally() {
        guard let (f, k) = p.tallyProgress else { return }
        let (chips, mult) = fold(f.steps.prefix(k))
        let cx = layout.size.width / 2, y = layout.hingeY - 120
        let panelR = CGRect(x: cx - 170, y: y - 44, width: 340, height: 104)
        pen.panel(panelR)
        let chipBox = CGRect(x: cx - 150, y: y - 30, width: 120, height: 48)
        let multBox = CGRect(x: cx + 30, y: y - 30, width: 120, height: 48)
        pen.panel(chipBox, fill: pal.chips, edge: pal.outline, radius: 8)
        pen.panel(multBox, fill: pal.mult, edge: pal.outline, radius: 8)
        pen.text("\(chips)", at: CGPoint(x: chipBox.midX, y: chipBox.midY), size: 26, color: RGB(0xFFFFFF), align: .center)
        pen.text(mult == mult.rounded() ? "\(Int(mult))" : String(format: "%.1f", mult),
                 at: CGPoint(x: multBox.midX, y: multBox.midY), size: 26, color: RGB(0xFFFFFF), align: .center)
        pen.text("X", at: CGPoint(x: cx, y: y - 6), size: 24, color: pal.text, align: .center)
        if k > 0 {
            pen.text(stepLabel(f, f.steps[k - 1]), at: CGPoint(x: cx, y: y + 40), size: 14, color: pal.tickets, align: .center)
        }
    }

    func stepLabel(_ f: FrameScore, _ st: ScoreStep) -> String {
        let what: String = switch st.effect {
        case .base: ""
        case .chips(let c): "+\(c) CHIPS"
        case .mult(let m): "+\(m == m.rounded() ? "\(Int(m))" : String(format: "%.1f", m)) MULT"
        case .timesMult(let x): "X\(x == x.rounded() ? "\(Int(x))" : String(format: "%.1f", x)) MULT"
        case .tickets(let t): "+\(t) TICKETS"
        case .note(let n): n.uppercased()
        }
        switch st.source {
        case .base: return "FRAME"
        case .ball(let i): return "BALL \(i + 1)  \(what)"
        case .payline:
            switch f.payline {
            case .none: return what
            case .pair(let s): return "PAIR OF \(s.rawValue.uppercased())S  \(what)"
            case .triple(let s): return "THREE \(s.rawValue.uppercased())S  \(what)"
            }
        case .charm(let c): return "\(c.name.uppercased())  \(what)"
        case .fever: return "FEVER  \(what)"
        }
    }

    func popups() {
        for pop in p.popups {
            let rise = CGFloat(pop.age) * 50
            let alpha = CGFloat(1 - pop.age * pop.age)
            let at: CGPoint = switch pop.anchor {
            case .hole(let h): h == .gutter ? CGPoint(x: layout.size.width / 2, y: layout.hingeY - 20) : proj.board(reelAnchor(h, board: board))
            case .center: CGPoint(x: layout.size.width / 2, y: layout.hingeY - 210)
            case .hud: CGPoint(x: layout.size.width / 2, y: layout.hudHeight + 30)
            }
            let color: RGB = switch pop.kind {
            case .chips: pal.chips
            case .mult: pal.mult
            case .tickets: pal.tickets
            case .bad: pal.bad
            case .jackpot: pal.tickets
            }
            let size: CGFloat = pop.kind == .jackpot ? 34 : (pop.anchor == .center ? 22 : 20)
            ctx.saveGState(); ctx.setAlpha(alpha)
            pen.text(pop.text, at: CGPoint(x: at.x, y: at.y - 18 - rise), size: size, color: color, align: .center)
            ctx.restoreGState()
        }
    }

    func bannerOverlay() {
        guard let (title, sub, u) = p.banner else { return }
        let inA = min(1, u * 5), outA = min(1, (1 - u) * 5)
        let a = CGFloat(min(inA, outA))
        ctx.saveGState(); ctx.setAlpha(a)
        let y = layout.hingeY - 150
        let r = CGRect(x: 30, y: y - 50, width: layout.size.width - 60, height: sub.isEmpty ? 80 : 110)
        pen.panel(r, radius: 16)
        pen.text(title, at: CGPoint(x: layout.size.width / 2, y: y - 6), size: 40, color: pal.tickets, align: .center)
        if !sub.isEmpty { pen.text(sub, at: CGPoint(x: layout.size.width / 2, y: y + 34), size: 16, color: pal.text, align: .center) }
        ctx.restoreGState()
    }

    // MARK: panels

    func counter(_ c: PrizeCounter) {
        let box = rects.counter
        pen.panel(box, radius: 16)
        pen.text("PRIZE COUNTER", at: CGPoint(x: box.minX + 18, y: box.minY + 24), size: 22, color: pal.text)
        ticketIcon(CGRect(x: box.maxX - 110, y: box.minY + 14, width: 26, height: 18))
        pen.text("\(s.tickets)", at: CGPoint(x: box.maxX - 20, y: box.minY + 24), size: 20, color: pal.tickets, align: .right)
        for (i, r) in rects.offerCards.enumerated() where i < c.offers.count {
            guard let offer = c.offers[i] else {
                pen.panel(r, fill: pal.panel.darker(0.3), radius: 10)
                pen.text("SOLD", at: CGPoint(x: r.midX, y: r.midY), size: 18, color: pal.textDim, align: .center)
                continue
            }
            let affordable = offer.cost <= s.tickets
            let selected = ui.selectedOffer == i
            pen.panel(r, fill: selected ? pal.panel.lighter(0.25) : pal.panel.lighter(0.1), edge: selected ? pal.tickets : nil, radius: 10)
            let icon = CGRect(x: r.midX - 26, y: r.minY + 12, width: 52, height: 52)
            switch offer {
            case .charm(let ch): charmToken(ch, in: icon.insetBy(dx: -4, dy: -4), selected: false)
            case .stamp(let sym): pen.glyph(sym, in: icon)
            case .gild: pen.sphere(CGPoint(x: icon.midX, y: icon.midY), 22, pal.tickets, shade: pal.tickets.darker(0.4))
                pen.text("+10", at: CGPoint(x: icon.midX, y: icon.midY), size: 13, color: RGB(0x111111), align: .center)
            case .purge:
                pen.glyph(.blank, in: icon)
                let x = CGMutablePath()
                x.move(to: CGPoint(x: icon.minX + 8, y: icon.minY + 8)); x.addLine(to: CGPoint(x: icon.maxX - 8, y: icon.maxY - 8))
                x.move(to: CGPoint(x: icon.maxX - 8, y: icon.minY + 8)); x.addLine(to: CGPoint(x: icon.minX + 8, y: icon.maxY - 8))
                pen.line(x, pal.bad, width: 5)
            case .powerUp(let pu): powerUpIcon(pu, in: icon.insetBy(dx: 4, dy: 4))
            }
            let (name, blurb) = offerText(offer)
            var y = icon.maxY + 16
            let pixel = pen.style == .pixel
            for line in Pen.wrap(name.uppercased(), chars: pen.chars(fitting: r.width - 10, size: 13)) {
                pen.text(line, at: CGPoint(x: r.midX, y: y), size: 13, color: pal.text, align: .center); y += pixel ? 25 : 16
            }
            y += 4
            let lineH: CGFloat = pixel ? 24 : 13
            let room = max(0, Int((r.maxY - 34 - y) / lineH) + 1)
            for line in Pen.wrap(blurb, chars: pen.chars(fitting: r.width - 8, size: 10.5)).prefix(room) {
                pen.text(line, at: CGPoint(x: r.midX, y: y), size: 10.5, color: pal.textDim, align: .center, bold: false); y += lineH
            }
            pen.text("\(offer.cost) TIX", at: CGPoint(x: r.midX, y: r.maxY - 14), size: 15,
                     color: affordable ? pal.tickets : pal.bad, align: .center)
        }
        pen.panel(rects.rerollButton, fill: pal.chips, radius: 12)
        pen.text("REROLL  \(c.rerollCost)", at: CGPoint(x: rects.rerollButton.midX, y: rects.rerollButton.midY), size: 18, color: RGB(0xFFFFFF), align: .center)
        pen.panel(rects.leaveButton, fill: pal.good, radius: 12)
        pen.text("NEXT ROUND", at: CGPoint(x: rects.leaveButton.midX, y: rects.leaveButton.midY), size: 18, color: RGB(0x111111), align: .center)
        if ui.selectedOffer != nil {
            pen.text("TAP A HOLE ON THE BOARD", at: CGPoint(x: layout.size.width / 2, y: layout.hingeY - 22), size: 18, color: pal.tickets, align: .center)
        }
    }

    func offerText(_ o: Offer) -> (String, String) {
        switch o {
        case .charm(let c): (c.name, c.blurb)
        case .stamp(let sym): ("\(sym.rawValue) stamp", "Add a \(sym.rawValue) to a hole's reel")
        case .gild: ("Gild", "+\(Offer.gildAmount) chips on a hole, for good")
        case .purge: ("Purge", "Remove a hole's showing symbol from its reel")
        case .powerUp(let pu): (pu.name, pu.blurb)
        }
    }

    func gameOver(won: Bool) {
        let box = CGRect(x: 40, y: layout.hingeY - 60, width: layout.size.width - 80, height: 340)
        pen.panel(box, radius: 18)
        pen.text(won ? "YOU BEAT THE ARCADE" : "GAME OVER", at: CGPoint(x: box.midX, y: box.minY + 40), size: 32,
                 color: won ? pal.tickets : pal.bad, align: .center)
        let lines = [
            "ANTE \(s.ante)  \(s.round.kind.title.uppercased())",
            "BEST FRAME \(s.stats.bestFrame)",
            "JACKPOTS \(s.stats.jackpots)   RATTLES \(s.stats.rattles)",
            "BALLS THROWN \(s.stats.balls)",
        ]
        for (i, l) in lines.enumerated() {
            pen.text(l, at: CGPoint(x: box.midX, y: box.minY + 86 + CGFloat(i) * 26), size: 16, color: pal.text, align: .center)
        }
        pen.panel(rects.bigButton, fill: pal.good, radius: 14)
        pen.text("NEW RUN", at: CGPoint(x: rects.bigButton.midX, y: rects.bigButton.midY), size: 24, color: RGB(0x111111), align: .center)
    }

    func title() {
        let w = layout.size.width
        let wob = CGFloat(sin(p.clock * 2.2)) * 4
        pen.panel(CGRect(x: 40, y: 120 + wob, width: w - 80, height: 150), radius: 20)
        pen.text("SKEE SKEE SKEE", at: CGPoint(x: w / 2, y: 175 + wob), size: 46, color: pal.tickets, align: .center)
        pen.text("A SKEE-BALL ROGUELIKE", at: CGPoint(x: w / 2, y: 228 + wob), size: 18, color: pal.text, align: .center)
        let a = CGFloat(0.5 + 0.5 * sin(p.clock * 3))
        pen.text("TAP TO PLAY", at: CGPoint(x: w / 2, y: layout.hingeY + 150), size: 28, color: pal.text.mix(pal.tickets, a), align: .center)
        pen.text("FLICK THE BALL UP THE LANE AND OVER THE HINGE", at: CGPoint(x: w / 2, y: layout.hingeY + 200), size: 13, color: pal.textDim, align: .center)
        pen.text("HALF-FOLD THE PHONE FOR A STEEPER RAMP", at: CGPoint(x: w / 2, y: layout.hingeY + 222), size: 13, color: pal.textDim, align: .center)
    }
}

extension BoardSpec {
    func chipsLabel(_ hole: Hole, setup: BoardSetup) -> String { "\(setup.chips(for: hole))" }
}
