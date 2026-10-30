import CoreGraphics
import Foundation
import ImageIO
import SkeeCore
import SkeeRender
import UniformTypeIdentifiers

// PNG output: the same Renderer the app uses, drawn into a bitmap.

let duoInnerSize = CGSize(width: 669, height: 951)
let duoOuterSize = CGSize(width: 466, height: 678)
/// --size outer renders the folded (outer) display instead of the inner one.
var duoInner: CGSize { flag("size") == "outer" ? duoOuterSize : duoInnerSize }

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

