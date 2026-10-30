import CoreGraphics
import SkeeRender
import CoreText
import Foundation
import SkeeCore
import SkeeRender

/// Procedural textures, drawn to match the toon look: flat fills, one hard
/// highlight, ink (#3a2346) outlines. No image assets anywhere.
public enum Textures {
    static let ink = RGB(Toon.ink)

    static func context(_ w: Int, _ h: Int) -> CGContext {
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // y-down like the rest of the drawing code.
        c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)
        return c
    }

    nonisolated(unsafe) static var cache: [String: CGImage] = [:]
    static let lock = NSRecursiveLock()
    /// The render thread and the HUD both ask for textures.
    static func cached(_ k: String, _ make: () -> CGImage) -> CGImage {
        lock.lock(); defer { lock.unlock() }
        if let i = cache[k] { return i }
        let i = make(); cache[k] = i; return i
    }

    // MARK: lane

    /// Maple boards running up the lane, with bowling-style aiming arrows.
    /// u across the lane, v from the release end (bottom) to the hinge (top).
    public static var lane: CGImage {
        cached("lane") {
            let w = 512, h = 2048
            let c = context(w, h)
            c.setFillColor(RGB(0xF2B872).cg()); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            var rng = SplitMix64(seed: 11)
            let boards = 9
            let bw = CGFloat(w) / CGFloat(boards)
            for i in 0..<boards {
                let tone = RGB(0xF2B872).mix(RGB(0xE5A35E), CGFloat(rng.nextUnit()) * 0.6)
                c.setFillColor(tone.cg()); c.fill(CGRect(x: CGFloat(i) * bw, y: 0, width: bw, height: CGFloat(h)))
                // A few long grain streaks per board.
                c.setStrokeColor(RGB(0xE0A866).cg(0.55)); c.setLineWidth(2)
                for _ in 0..<3 {
                    let x = CGFloat(i) * bw + CGFloat(rng.nextUnit()) * bw
                    let y0 = CGFloat(rng.nextUnit()) * CGFloat(h)
                    c.move(to: CGPoint(x: x, y: y0)); c.addLine(to: CGPoint(x: x + 3, y: y0 + 300 + CGFloat(rng.nextUnit()) * 400))
                }
                c.strokePath()
            }
            c.setStrokeColor(RGB(0xC98B4E).cg()); c.setLineWidth(3)
            for i in 1..<boards { c.move(to: CGPoint(x: CGFloat(i) * bw, y: 0)); c.addLine(to: CGPoint(x: CGFloat(i) * bw, y: CGFloat(h))) }
            c.strokePath()
            // Arrows about a third of the way up (texture top = hinge end).
            for (k, x) in [-2, -1, 0, 1, 2].enumerated() {
                let cx = CGFloat(w) / 2 + CGFloat(x) * bw * 1.5
                let tipY = CGFloat(h) * (0.34 - (k == 2 ? -0.04 : abs(CGFloat(x)) * 0.015))
                let p = CGMutablePath()
                // Drawn pointing down: the lane flips v, so on the lane they
                // point up toward the target.
                p.move(to: CGPoint(x: cx, y: tipY + 70))
                p.addLine(to: CGPoint(x: cx + 22, y: tipY)); p.addLine(to: CGPoint(x: cx - 22, y: tipY)); p.closeSubpath()
                c.addPath(p); c.setFillColor(RGB(0xFF7FA8).cg()); c.fillPath()
                c.addPath(p); c.setStrokeColor(ink.cg()); c.setLineWidth(5); c.setLineJoin(.round); c.strokePath()
            }
            return c.makeImage()!
        }
    }

    // MARK: ball

    /// Equirectangular: six gores alternating two tones, so the roll reads
    /// from any angle, plus a white star at each pole.
    public static var ball: CGImage {
        cached("ball") {
            let w = 512, h = 256
            let c = context(w, h)
            let a = RGB(0xFF6F6F), b = RGB(0xFFE3C2)
            for i in 0..<6 {
                c.setFillColor((i % 2 == 0 ? a : b).cg())
                c.fill(CGRect(x: CGFloat(i) * CGFloat(w) / 6, y: 0, width: CGFloat(w) / 6 + 1, height: CGFloat(h)))
            }
            c.setStrokeColor(ink.cg(0.8)); c.setLineWidth(4)
            for i in 0..<6 { let x = CGFloat(i) * CGFloat(w) / 6; c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: CGFloat(h))) }
            c.strokePath()
            c.setFillColor(RGB(0xFFFFFF).cg())
            c.fill(CGRect(x: 0, y: 0, width: w, height: 18)); c.fill(CGRect(x: 0, y: h - 18, width: w, height: 18))
            return c.makeImage()!
        }
    }

    // MARK: symbols

    /// A reel symbol on a cream plate with an ink border.
    public static func plate(_ s: Symbol, lit: Bool = true) -> CGImage {
        cached("plate-\(s.rawValue)-\(lit)") {
            let n = 256
            let c = context(n, n)
            let bg = CGPath(roundedRect: CGRect(x: 8, y: 8, width: n - 16, height: n - 16), cornerWidth: 40, cornerHeight: 40, transform: nil)
            c.addPath(bg); c.setFillColor((lit ? RGB(0xFFF8EC) : RGB(0xCFC4D6)).cg()); c.fillPath()
            c.addPath(bg); c.setStrokeColor(ink.cg()); c.setLineWidth(12); c.strokePath()
            drawSymbol(s, in: CGRect(x: 36, y: 36, width: n - 72, height: n - 72), c)
            return c.makeImage()!
        }
    }

    /// The symbol alone on transparent, for the marquee reels.
    public static func symbol(_ s: Symbol) -> CGImage {
        cached("sym-\(s.rawValue)") {
            let n = 256
            let c = context(n, n)
            drawSymbol(s, in: CGRect(x: 20, y: 20, width: n - 40, height: n - 40), c)
            return c.makeImage()!
        }
    }

    static func drawSymbol(_ s: Symbol, in r: CGRect, _ c: CGContext) {
        let line = r.width * 0.045
        func shape(_ p: CGPath, _ fill: RGB, highlight: Bool = true) {
            c.addPath(p); c.setFillColor(fill.cg()); c.fillPath()
            if highlight {
                // Hard highlight band on the upper-left, clipped to the shape.
                c.saveGState(); c.addPath(p); c.clip()
                let b = p.boundingBox
                c.setFillColor(fill.lighter(0.45).cg())
                c.fillEllipse(in: CGRect(x: b.minX + b.width * 0.12, y: b.minY + b.height * 0.1, width: b.width * 0.38, height: b.height * 0.28))
                c.restoreGState()
            }
            c.addPath(p); c.setStrokeColor(ink.cg()); c.setLineWidth(line); c.setLineJoin(.round); c.strokePath()
        }
        func stroke(_ p: CGPath, _ color: RGB, width: CGFloat) {
            c.addPath(p); c.setStrokeColor(ink.cg()); c.setLineWidth(width + line * 2); c.setLineCap(.round); c.strokePath()
            c.addPath(p); c.setStrokeColor(color.cg()); c.setLineWidth(width); c.setLineCap(.round); c.strokePath()
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        func circle(_ x: CGFloat, _ y: CGFloat, _ rad: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: r.minX + (x - rad) * r.width, y: r.minY + (y - rad) * r.height, width: 2 * rad * r.width, height: 2 * rad * r.height), transform: nil)
        }

        switch s {
        case .blank:
            break
        case .cherry:
            let stems = CGMutablePath()
            stems.move(to: pt(0.30, 0.60)); stems.addQuadCurve(to: pt(0.60, 0.12), control: pt(0.34, 0.28))
            stems.move(to: pt(0.70, 0.64)); stems.addQuadCurve(to: pt(0.60, 0.12), control: pt(0.72, 0.34))
            stroke(stems, RGB(0x5BBE5B), width: r.width * 0.05)
            let leaf = CGMutablePath()
            leaf.move(to: pt(0.60, 0.14)); leaf.addQuadCurve(to: pt(0.92, 0.18), control: pt(0.80, 0.0))
            leaf.addQuadCurve(to: pt(0.60, 0.14), control: pt(0.78, 0.30)); leaf.closeSubpath()
            shape(leaf, RGB(0x6FD36F), highlight: false)
            shape(circle(0.30, 0.70, 0.19), RGB(0xFF4D6D))
            shape(circle(0.70, 0.72, 0.19), RGB(0xFF4D6D))
        case .lemon:
            let p = CGMutablePath()
            p.move(to: pt(0.06, 0.52))
            p.addQuadCurve(to: pt(0.50, 0.18), control: pt(0.16, 0.18))
            p.addQuadCurve(to: pt(0.94, 0.48), control: pt(0.84, 0.18))
            p.addQuadCurve(to: pt(0.50, 0.82), control: pt(0.84, 0.82))
            p.addQuadCurve(to: pt(0.06, 0.52), control: pt(0.16, 0.82)); p.closeSubpath()
            shape(p, RGB(0xFFE14D))
        case .bell:
            shape(circle(0.50, 0.84, 0.09), RGB(0xE09A3A), highlight: false)
            let p = CGMutablePath()
            p.move(to: pt(0.50, 0.10))
            p.addCurve(to: pt(0.80, 0.64), control1: pt(0.78, 0.10), control2: pt(0.72, 0.50))
            p.addQuadCurve(to: pt(0.92, 0.78), control: pt(0.92, 0.72))
            p.addLine(to: pt(0.08, 0.78))
            p.addQuadCurve(to: pt(0.20, 0.64), control: pt(0.08, 0.72))
            p.addCurve(to: pt(0.50, 0.10), control1: pt(0.28, 0.50), control2: pt(0.22, 0.10)); p.closeSubpath()
            shape(p, RGB(0xFFC23D))
        case .bar:
            let plate = CGPath(roundedRect: CGRect(x: r.minX, y: r.minY + r.height * 0.26, width: r.width, height: r.height * 0.48),
                               cornerWidth: r.width * 0.08, cornerHeight: r.width * 0.08, transform: nil)
            shape(plate, RGB(0x3A2346), highlight: false)
            text("BAR", in: CGRect(x: r.minX, y: r.minY + r.height * 0.26, width: r.width, height: r.height * 0.48),
                 size: r.height * 0.34, fill: RGB(0xFFF8EC), c)
        case .seven:
            text("7", in: r.insetBy(dx: 0, dy: -r.height * 0.05), size: r.height * 1.0, fill: RGB(0xFF3B5C), c, outline: line * 1.6)
        case .diamond:
            let outer = CGMutablePath()
            outer.addLines(between: [pt(0.5, 0.06), pt(0.94, 0.40), pt(0.5, 0.94), pt(0.06, 0.40)]); outer.closeSubpath()
            shape(outer, RGB(0x4DE0FF), highlight: false)
            let facets = CGMutablePath()
            facets.addLines(between: [pt(0.06, 0.40), pt(0.94, 0.40)])
            facets.move(to: pt(0.30, 0.40)); facets.addLine(to: pt(0.5, 0.94)); facets.move(to: pt(0.70, 0.40)); facets.addLine(to: pt(0.5, 0.94))
            facets.move(to: pt(0.30, 0.40)); facets.addLine(to: pt(0.5, 0.06)); facets.move(to: pt(0.70, 0.40)); facets.addLine(to: pt(0.5, 0.06))
            c.addPath(facets); c.setStrokeColor(ink.cg(0.7)); c.setLineWidth(line * 0.6); c.strokePath()
            let shine = CGMutablePath()
            shine.addLines(between: [pt(0.5, 0.10), pt(0.62, 0.38), pt(0.38, 0.38)]); shine.closeSubpath()
            c.addPath(shine); c.setFillColor(RGB(0xFFFFFF).cg(0.8)); c.fillPath()
        case .clover:
            let stem = CGMutablePath()
            stem.move(to: pt(0.5, 0.52)); stem.addQuadCurve(to: pt(0.68, 0.94), control: pt(0.5, 0.82))
            stroke(stem, RGB(0x3FAF5A), width: r.width * 0.06)
            for (x, y) in [(0.5, 0.27), (0.27, 0.48), (0.73, 0.48), (0.5, 0.68)] {
                shape(circle(x, y, 0.18), RGB(0x5BD67A))
            }
        }
    }

    /// Centred heavy text with an ink outline.
    static func text(_ s: String, in r: CGRect, size: CGFloat, fill: RGB, _ c: CGContext, outline: CGFloat = 0, font: String = "AvenirNext-Heavy") {
        let f = CTFontCreateWithName(font as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): f,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill.cg(),
        ]
        let lineRef = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let w = CGFloat(CTLineGetTypographicBounds(lineRef, &ascent, &descent, nil))
        let x = r.midX - w / 2
        let baseline = r.midY + (ascent - descent) / 2 - descent * 0.2
        c.saveGState()
        c.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        if outline > 0 {
            c.setTextDrawingMode(.stroke); c.setLineWidth(outline); c.setLineJoin(.round)
            c.setStrokeColor(ink.cg())
            c.textPosition = CGPoint(x: x, y: baseline); CTLineDraw(lineRef, c)
            c.setTextDrawingMode(.fill)
        }
        c.textPosition = CGPoint(x: x, y: baseline); CTLineDraw(lineRef, c)
        c.restoreGState()
    }

    /// The inside of a hole: near-black in the middle, a little lighter at
    /// the lip, with a soft inner ring, so a flat disc reads as a pit.
    public static var pit: CGImage {
        cached("pit") {
            let n = 256
            let c = context(n, n)
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [RGB(0x07040C).cg(), RGB(0x160C22).cg(), RGB(0x3A2346).cg()] as CFArray,
                               locations: [0, 0.62, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: n / 2, y: n / 2 + 18), startRadius: 0,
                                 endCenter: CGPoint(x: n / 2, y: n / 2), endRadius: CGFloat(n) / 2, options: [.drawsAfterEndLocation])
            return c.makeImage()!
        }
    }

    /// A score badge: cream (or gold for 50 and 100) with the number in ink.
    public static func badge(_ s: String, special: Bool) -> CGImage {
        cached("badge-\(s)-\(special)") {
            let w = 256, h = 140
            let c = context(w, h)
            c.setFillColor((special ? RGB(0xFFC94D) : RGB(0xFFF8EC)).cg()); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            text(s, in: CGRect(x: 0, y: 0, width: w, height: h), size: 112, fill: special ? RGB(0x3A2346) : RGB(0xFF4D6D), c,
                 outline: special ? 0 : 10)
            return c.makeImage()!
        }
    }

    /// A fat five-point star, cream with an ink edge, for drop bursts.
    public static var star: CGImage {
        cached("star") {
            let n = 128
            let c = context(n, n)
            let p = CGMutablePath()
            for i in 0..<10 {
                let r: CGFloat = i % 2 == 0 ? 56 : 26
                let a = CGFloat(i) / 10 * 2 * .pi - .pi / 2
                let pt = CGPoint(x: 64 + cos(a) * r, y: 64 + sin(a) * r)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
            c.addPath(p); c.setFillColor(RGB(0xFFFFFF).cg()); c.fillPath()
            c.addPath(p); c.setStrokeColor(ink.cg()); c.setLineWidth(7); c.setLineJoin(.round); c.strokePath()
            return c.makeImage()!
        }
    }

    /// Soft round shadow for under the ball.
    public static var blob: CGImage {
        cached("blob") {
            let n = 128
            let c = context(n, n)
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [RGB(0x3A2346).cg(0.55), RGB(0x3A2346).cg(0)] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: n / 2, y: n / 2), startRadius: 0,
                                 endCenter: CGPoint(x: n / 2, y: n / 2), endRadius: CGFloat(n) / 2, options: [])
            return c.makeImage()!
        }
    }

    /// A number painted on the board, e.g. "30".
    public static func label(_ s: String, color: UInt32 = Toon.ink) -> CGImage {
        cached("label-\(s)-\(color)") {
            let c = context(256, 128)
            text(s, in: CGRect(x: 0, y: 0, width: 256, height: 128), size: 96, fill: RGB(color), c)
            return c.makeImage()!
        }
    }

    public static func marqueeTitle() -> CGImage {
        cached("marquee") {
            let c = context(1024, 256)
            text("SKEE SKEE SKEE", in: CGRect(x: 0, y: 0, width: 1024, height: 256), size: 120, fill: RGB(0xFFF1A8), c, outline: 14)
            return c.makeImage()!
        }
    }
}
