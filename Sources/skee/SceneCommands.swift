import CoreGraphics
import Foundation
import SkeeCore
import SkeeScene
import SkeeHUD
import SkeeRender
import SwiftUI

/// skee scene: render the 3D cabinet to PNG at the Duo's inner display size.
@MainActor
func sceneCommand() {
    let out = flag("out") ?? "out/scene.png"
    let size = flag("size") == "outer" ? CGSize(width: 466, height: 678) : CGSize(width: 669, height: 951)
    let cab = Cabinet()
    let rig = Cabinet.fit(points: cab.framingPoints, aspect: Float(size.width / size.height))
    cab.apply(rig)
    let w = cab.world
    for (n, pt) in [("near", w.lane(x: 0, s: 0)), ("hump", w.lane(x: 0, s: w.table.lane.length)), ("board top", w.board(Vec2(0, 1))), ("marquee", cab.marqueeTop)] {
        print(n, rig.project(pt, aspect: Float(size.width / size.height)))
    }
    print("camera", cab.camera.simdPosition, "fov", cab.camera.camera!.fieldOfView)
    let s = newRun(seed: UInt64(flag("seed") ?? "7") ?? 7)
    for h in Hole.allCases where h != .gutter { cab.setReel(h, s.showing(h), turn: 0, glow: h == .ring30 ? 1 : (h == .pocketRight ? 2 : 0), pulse: 1) }

    cab.setWaiting(8)
    guard let img = snapshot(cab, size: CGSize(width: size.width * 2, height: size.height * 2)) else { fail("no Metal device") }
    try? FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    writePNG(img, out)
    print(out)
}

/// skee scenefilm: the last action of a save, animated in 3D, as a contact
/// sheet. One PNG to judge a whole throw: roll, hinge, flight, drop, reels.
@MainActor
func sceneFilmCommand() {
    let out = flag("out") ?? "out/scenefilm.png"
    let frames = Int(flag("frames") ?? "12") ?? 12
    let dt = Double(flag("dt") ?? "0.15") ?? 0.15
    let cols = Int(flag("cols") ?? "4") ?? 4
    let size = CGSize(width: 669, height: 951)
    let thumb = CGFloat(Double(flag("scale") ?? "0.4") ?? 0.4)
    var (p, _) = presentationForSave(flag("save"))
    let cab = Cabinet()
    let presenter = ScenePresenter(cabinet: cab, aspect: Float(size.width / size.height))
    let from = Double(flag("from") ?? "0") ?? 0
    var t = 0.0
    while t < from { p.advance(1.0 / 120); presenter.update(p, held: nil, dt: 1.0 / 120); t += 1.0 / 120 }
    let tw = size.width * thumb, th = size.height * thumb
    let rows = (frames + cols - 1) / cols
    let sheet = bitmap(CGSize(width: tw * CGFloat(cols), height: th * CGFloat(rows)))
    // Advance in small steps so rolling integrates smoothly between frames.
    let sub = 8
    for i in 0..<frames {
        presenter.update(p, held: nil, dt: 0)
        guard let img = snapshot(cab, size: CGSize(width: tw * 2, height: th * 2)) else { fail("no Metal") }
        let x = CGFloat(i % cols) * tw, y = CGFloat(i / cols) * th
        sheet.saveGState()
        sheet.translateBy(x: x, y: y + th); sheet.scaleBy(x: 1, y: -1)
        sheet.draw(img, in: CGRect(x: 0, y: 0, width: tw, height: th))
        sheet.restoreGState()
        for _ in 0..<sub { p.advance(dt / Double(sub)); presenter.update(p, held: nil, dt: dt / Double(sub)) }
    }
    try? FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    writePNG(sheet.makeImage()!, out)
    print(out)
}

/// One full app frame: the 3D scene with the SwiftUI HUD on top.
@MainActor
func composeFrame(_ p: Presentation, cab: Cabinet, presenter: ScenePresenter, size: CGSize, scale: CGFloat = 2,
                  screen: HUDState.Screen = .game, selectedOffer: Int? = nil, wallet: Wallet? = nil, coach: CoachCard? = nil,
                  line: Double? = nil, host: HostState? = nil, bet: Bet = .one, snapper: Snapper? = nil, time: TimeInterval = 0,
                  tweak: (inout HUDState) -> Void = { _ in }) -> CGImage? {
    let pixels = CGSize(width: size.width * scale, height: size.height * scale)
    guard let scene3D = snapper?.image(size: pixels, time: time) ?? snapshot(cab, size: pixels) else { return nil }
    let a = Float(size.width / size.height)
    var hud = HUDState.make(p, holeOnScreen: { hole in
        let w = cab.world
        let f = presenter.rig.project(w.board(w.table.board.holeCenter(hole)), aspect: a)
        return CGPoint(x: CGFloat(f.x) * size.width, y: CGFloat(f.y) * size.height)
    }, center: CGPoint(x: size.width / 2, y: size.height * 0.2), selectedOffer: selectedOffer, screen: screen, bet: bet)
    if let wallet { hud.wallet = wallet; hud.shopOpen = screen == .game }
    hud.coach = coach
    hud.host = host
    if let line { hud.guide = presenter.guide(line: line, size: size); hud.aiming = true }
    tweak(&hud)
    let renderer = ImageRenderer(content: HUDView(state: hud).frame(width: size.width, height: size.height))
    renderer.scale = scale
    guard let overlay = renderer.cgImage else { return scene3D }
    let c = bitmap(CGSize(width: size.width * scale, height: size.height * scale))
    // bitmap() is y-down; CGImage draws y-up, so flip for each image.
    for img in [scene3D, overlay] {
        c.saveGState()
        c.translateBy(x: 0, y: size.height * scale); c.scaleBy(x: 1, y: -1)
        c.draw(img, in: CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        c.restoreGState()
    }
    return c.makeImage()
}

/// skee frame: the last action of a save, `t` seconds in (or settled), as the
/// phone would show it, HUD included.
@MainActor
func frameCommand() {
    let out = flag("out") ?? "out/frame.png"
    let size = flag("size") == "outer" ? CGSize(width: 466, height: 678) : CGSize(width: 626, height: 890)
    var (p, s0) = presentationForSave(flag("save"))
    let cab = Cabinet(table: s0.room.table, palette: .of(s0.room))
    let presenter = ScenePresenter(cabinet: cab, aspect: Float(size.width / size.height))
    let t = has("settle") ? 30 : (Double(flag("t") ?? "0") ?? 0)
    var clock = 0.0
    while clock < t && (p.isBusy || clock < 0.05) { p.advance(1.0 / 60); presenter.update(p, held: nil, dt: 1.0 / 60); clock += 1.0 / 60 }
    // --line -1...1: the waiting ball on that line, with its guide.
    let line = flag("line").flatMap(Double.init)
    presenter.update(p, held: line.map(presenter.waitingBall), dt: 0)
    guard let img = composeFrame(p, cab: cab, presenter: presenter, size: size, screen: has("title") ? .title : .game,
                                 selectedOffer: flag("select").flatMap(Int.init),
                                 // --shop: the prize shop with a sample shelf (on the title with --title).
                                 wallet: has("shop") || has("title") ? Wallet(balance: 1340, lifetime: 2000, owned: [.sticker, .rubberDuck, .yoyo]) : nil,
                                 // --coach 0...6: the walkthrough card for that step.
                                 coach: flag("coach").flatMap(Int.init).flatMap(WalkthroughStep.init).map { Walkthrough(step: $0).card },
                                 line: line,
                                 // --host: the host's table mid-haggle, scripted (no network).
                                 host: has("host") ? sampleHaggle() : nil,
                                 // --confirm: the new-game question.
                                 tweak: { $0.confirmNew = has("confirm") })
            else { fail("render failed") }
    try? FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    writePNG(img, out)
    print(out)
}

/// skee flickprobe: synthetic human flicks (minimum-jerk reaches) through
/// the analyser: what it measures, what it throws, where the ball goes.
func flickProbe() {
    let g = FlickGeometry(creaseY: 445, laneCenterX: 313, laneHalfWidth: 260)
    func flick(_ D: Double, _ T: Double, lift: Double = 0.8, wobble: Double = 0) -> [FlickSample] {
        var out: [FlickSample] = [], t = 0.0
        while t <= T * lift { let u = t / T
            out.append(FlickSample(t: t, x: 313, y: 820 - D * (10 * pow(u, 3) - 15 * pow(u, 4) + 6 * pow(u, 5)) - wobble * sin(t * 90)))
            t += 1.0 / 120 }
        return out
    }
    print("dist  dur   lift wob | peak  release jerk  snap | power skid -> hole")
    for (D, T, lift, w) in [(150.0, 0.2, 0.8, 0.0), (220, 0.16, 0.8, 0), (220, 0.12, 0.8, 0), (300, 0.14, 0.7, 0), (220, 0.16, 0.6, 0),
                            (220, 0.16, 0.97, 0), (220, 0.16, 0.8, 4), (220, 0.16, 0.8, 9), (380, 0.18, 0.75, 0)] {
        let s = flick(D, T, lift: lift, wobble: w)
        guard case .release(let l) = analyzeFlick(s, in: g), let m = lastMetrics else { print("\(D) \(T): no throw"); continue }
        let h = simulateShot(l, on: .standard).hole
        print(String(format: "%4.0f  %.2f  %.2f %3.0f | %5.0f %6.0f  %5.1f %5.2f | %.2f  %.2f -> %@",
                     D, T, lift, w, m.peak, m.release, m.jerk, m.snap, l.power, l.skid, "\(h.faceValue)"))
    }
}

/// A haggle two turns in, with canned replies, for screenshots.
func sampleHaggle() -> HostState {
    var h = Haggle(room: .neonLounge, seed: 1)
    h.say("Two nights and some tickets would make this a real celebration.")
    h.hear(HostReply(say: "Two nights I could warm to, but 'some tickets' is a fog machine, not a number. Give me a reason worth the ink.",
                     offer: .init(nights: 2, tickets: 0, credit: 0)))
    h.say("I've been telling everyone on the boardwalk the Lounge is where the real players go. Make me look right?")
    h.hear(HostReply(say: "Now that's a compliment with legs. One ticket a night, and you keep talking us up on that boardwalk.",
                     offer: .init(nights: 2, tickets: 1, credit: 0), mood: 1))
    return HostState(haggle: h, thinking: false, error: nil)
}
