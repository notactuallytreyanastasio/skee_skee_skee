import CoreGraphics
import Foundation
import ImageIO
import SkeeCore
import SkeeRender
import UniformTypeIdentifiers

// PNG output: the same Renderer the app uses, drawn into a bitmap.

let duoInner = CGSize(width: 669, height: 951)

func bitmap(_ size: CGSize, scale: CGFloat = 1) -> CGContext {
    let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // y-down, top-left origin, like SwiftUI Canvas.
    ctx.translateBy(x: 0, y: size.height * scale)
    ctx.scaleBy(x: scale, y: -scale)
    return ctx
}

func writePNG(_ img: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

/// Rebuild the presentation for a save: state before the last action, with
/// the last action's step queued, so `t` scrubs through its animation.
func presentationForSave(_ path: String?) -> (Presentation, RunState) {
    guard let path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let file = try? JSONDecoder().decode(SaveFile.self, from: data) else {
        let s = newRun(seed: 1)
        return (Presentation(state: s), s)
    }
    var state = newRun(seed: file.seed)
    var last: Step?
    var before = state
    for a in file.actions {
        before = state
        guard case .success(let step) = apply(a, to: state) else { fail("save does not replay") }
        state = step.state; last = step
    }
    var p = Presentation(state: last == nil ? state : before)
    if let last { p.enqueue(last) }
    return (p, state)
}

func uiFromFlags() -> UIState {
    var ui = UIState()
    ui.screen = has("title") ? .title : .game
    ui.fold = Double(flag("fold") ?? "0") ?? 0
    if let o = flag("select") { ui.selectedOffer = Int(o) }
    if let d = flag("drag") {
        let n = d.split(separator: ",").compactMap { Double($0) }
        if n.count == 4 { ui.dragStart = CGPoint(x: n[0], y: n[1]); ui.dragNow = CGPoint(x: n[2], y: n[3]) }
    }
    return ui
}

/// A presentation forced into a given style (for previewing every era).
func restyled(_ p: Presentation, _ style: ArtStyle?) -> Presentation {
    guard let style else { return p }
    var s = p.shown
    s.ante = [ArtStyle.pixel: 1, .cel: 3, .depth: 5, .neon: 7][style]!
    var q = Presentation(state: s)
    // Carry the queued beats by re-enqueueing is not possible generically;
    // for still frames of the resting state this is what we want.
    q.advance(p.clock)
    return q
}

func renderCommand() {
    let out = flag("out") ?? "out/frame.png"
    var (p, _) = presentationForSave(flag("save"))
    let t = Double(flag("t") ?? "0") ?? 0
    if has("settle") { p.skip() } else { p.advance(t) }
    if let st = flag("style") { p = restyled(p, ArtStyle(rawValue: st) ?? .pixel) }
    let layout = Layout(size: duoInner)
    let ctx = bitmap(duoInner)
    Renderer.draw(p, ui: uiFromFlags(), layout: layout, in: ctx)
    try? FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    writePNG(ctx.makeImage()!, out)
    print(out)
}

/// Contact sheet: the last action's animation sampled every `dt` seconds,
/// laid out in a grid of thumbnails. One PNG to judge a whole throw.
func filmCommand() {
    let out = flag("out") ?? "out/film.png"
    let frames = Int(flag("frames") ?? "12") ?? 12
    let dt = Double(flag("dt") ?? "0.2") ?? 0.2
    let cols = Int(flag("cols") ?? "4") ?? 4
    let thumb: CGFloat = CGFloat(Double(flag("scale") ?? "0.5") ?? 0.5)
    var (p, _) = presentationForSave(flag("save"))
    let layout = Layout(size: duoInner)
    let rows = (frames + cols - 1) / cols
    let tw = duoInner.width * thumb, th = duoInner.height * thumb
    let sheet = bitmap(CGSize(width: tw * CGFloat(cols), height: th * CGFloat(rows)))
    let ui = uiFromFlags()
    for i in 0..<frames {
        let ctx = bitmap(duoInner)
        Renderer.draw(p, ui: ui, layout: layout, in: ctx)
        let img = ctx.makeImage()!
        let x = CGFloat(i % cols) * tw, y = CGFloat(i / cols) * th
        sheet.saveGState()
        sheet.translateBy(x: x, y: y + th); sheet.scaleBy(x: 1, y: -1)
        sheet.draw(img, in: CGRect(x: 0, y: 0, width: tw, height: th))
        sheet.restoreGState()
        p.advance(dt)
    }
    try? FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    writePNG(sheet.makeImage()!, out)
    print(out)
}
