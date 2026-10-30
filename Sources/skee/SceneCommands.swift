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
    for h in Hole.allCases where h != .gutter { cab.setPlate(h, s.showing(h)) }

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
                  screen: HUDState.Screen = .game, selectedOffer: Int? = nil) -> CGImage? {
    guard let scene3D = snapshot(cab, size: CGSize(width: size.width * scale, height: size.height * scale)) else { return nil }
    let a = Float(size.width / size.height)
    let hud = HUDState.make(p, holeOnScreen: { hole in
        let w = cab.world
        let f = presenter.rig.project(w.board(w.table.board.holeCenter(hole)), aspect: a)
        return CGPoint(x: CGFloat(f.x) * size.width, y: CGFloat(f.y) * size.height)
    }, center: CGPoint(x: size.width / 2, y: size.height * 0.2), selectedOffer: selectedOffer, screen: screen)
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
    var (p, _) = presentationForSave(flag("save"))
    let cab = Cabinet()
    let presenter = ScenePresenter(cabinet: cab, aspect: Float(size.width / size.height))
    let t = has("settle") ? 30 : (Double(flag("t") ?? "0") ?? 0)
    var clock = 0.0
    while clock < t && (p.isBusy || clock < 0.05) { p.advance(1.0 / 60); presenter.update(p, held: nil, dt: 1.0 / 60); clock += 1.0 / 60 }
    presenter.update(p, held: nil, dt: 0)
    guard let img = composeFrame(p, cab: cab, presenter: presenter, size: size, screen: has("title") ? .title : .game,
                                 selectedOffer: flag("select").flatMap(Int.init)) else { fail("render failed") }
    try? FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    writePNG(img, out)
    print(out)
}

/// skee thumbprobe: how thumb movement on screen maps to lane metres, and
/// which release speeds score from a typical release point.
@MainActor
func thumbProbe() {
    let size = CGSize(width: 626, height: 890)
    let a = Float(size.width / size.height)
    let cab = Cabinet()
    let pr = ScenePresenter(cabinet: cab, aspect: a)
    let g = pr.strokeGeometry(size: size)
    print("crease at y =", Int(g.creaseY), "pt; foul above", Int(g.foulY))
    var prev: Double?
    for y in stride(from: 860.0, through: 450, by: -50) {
        let p = pr.lanePoint(screen: SIMD2(0.5, Float(y / size.height)), aspect: a)!
        let s = pr.laneCoordinates(p).s
        if let prev { print("y \(Int(y)): s = \(f2(s)) m  (\(String(format: "%.1f", (s - prev) / 50 * 1000)) mm per pt)") } else { print("y \(Int(y)): s = \(f2(s)) m") }
        prev = s
    }
    for from in [1.2, 1.7, 2.1] {
        var line = "from \(f2(from)) m:"
        for sp in stride(from: 1.5, through: 4.5, by: 0.15) {
            let h = simulateShot(Launch(speed: sp, from: from, aim: 0), on: .standard).hole
            line += " \(f2(sp)):\(h.faceValue)"
        }
        print(line)
    }
}
