import CoreGraphics
import Foundation
import SkeeCore
import SkeeScene

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
