import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `skee icon --out f.png`: the App Store icon, 1024 square. No alpha:
/// App Store Connect refuses an icon with an alpha channel, so it's drawn
/// into an opaque context. The target rings and the ball are the game's
/// own, and it has no text because text is lost at home-screen size.
func iconCommand() {
    let out = flag("out") ?? "App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
    let n = 1024
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let c = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    func col(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: a)
    }
    func disc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ fill: CGColor) {
        c.setFillColor(fill); c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    func radial(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ colors: [CGColor]) {
        let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: nil)!
        c.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r,
                             options: [.drawsAfterEndLocation])
    }
    let mid = CGFloat(n) / 2, ink: UInt32 = 0x2A1A4A

    // Violet stage with a sunburst behind the target.
    radial(mid, mid, 760, [col(0x8A6CF0), col(0x4A2FB0), col(0x24135E)])
    c.saveGState()
    c.translateBy(x: mid, y: mid)
    for i in 0..<16 {
        let a = CGFloat(i) / 16 * 2 * .pi, w = CGFloat.pi / 16
        c.move(to: .zero)
        c.addLine(to: CGPoint(x: cos(a - w / 2) * 900, y: sin(a - w / 2) * 900))
        c.addLine(to: CGPoint(x: cos(a + w / 2) * 900, y: sin(a + w / 2) * 900))
        c.closePath()
    }
    c.setFillColor(col(0xFFD84D, 0.16)); c.fillPath()
    c.restoreGState()

    // Target rings, outlined the way the game's cel style outlines things.
    for (r, fill) in [(404, 0xFF6FA5), (316, 0xFFF8EC), (228, 0x5FC8FF), (140, 0xFFD84D)] as [(CGFloat, UInt32)] {
        disc(mid, mid - 8, r + 16, col(ink))
        disc(mid, mid - 8, r, col(fill))
    }
    disc(mid, mid - 8, 60, col(ink))

    // The ball, mid-flight toward the hole, with its shine.
    let bx = mid + 150, by = mid - 170, br: CGFloat = 158
    disc(bx + 14, by - 22, br + 6, col(0x000000, 0.28))
    disc(bx, by, br + 16, col(ink))
    c.saveGState()
    c.addEllipse(in: CGRect(x: bx - br, y: by - br, width: 2 * br, height: 2 * br)); c.clip()
    radial(bx - 56, by + 62, 300, [col(0xFFB3CC), col(0xFF4D6D), col(0xB01E4A)])
    c.restoreGState()
    disc(bx - 58, by + 70, 44, col(0xFFFFFF, 0.92))
    disc(bx - 4, by + 104, 15, col(0xFFFFFF, 0.8))

    let url = URL(fileURLWithPath: out)
    guard let image = c.makeImage(), let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("could not write \(out)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(out)") }
    print("wrote \(out)")
}
