import CoreGraphics
import SkeeCore
import SkeeRender

extension Textures {
    /// A prize from the shelf, drawn in the same cel style as the symbols:
    /// flat fills, one hard highlight, ink outlines. `owned` false draws it
    /// as a dim silhouette, the way a prize counter shows what you can't
    /// have yet.
    public static func prize(_ p: Prize, owned: Bool = true) -> CGImage {
        cached("prize-\(p.rawValue)-\(owned)") {
            let n = 256
            let c = context(n, n)
            drawPrize(p, in: CGRect(x: 16, y: 16, width: n - 32, height: n - 32), c, silhouette: !owned)
            return c.makeImage()!
        }
    }

    static func drawPrize(_ prize: Prize, in r: CGRect, _ c: CGContext, silhouette: Bool) {
        let line = r.width * 0.035
        let shadow = RGB(0x7A6A8C)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, round: CGFloat = 0) -> CGPath {
            let rr = CGRect(x: r.minX + x * r.width, y: r.minY + y * r.height, width: w * r.width, height: h * r.height)
            let k = min(round * r.width, rr.width / 2, rr.height / 2)
            return CGPath(roundedRect: rr, cornerWidth: k, cornerHeight: k, transform: nil)
        }
        func oval(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: r.minX + (x - rx) * r.width, y: r.minY + (y - ry) * r.height,
                                     width: 2 * rx * r.width, height: 2 * ry * r.height), transform: nil)
        }
        func fill(_ p: CGPath, _ color: RGB, highlight: Bool = true) {
            let col = silhouette ? shadow : color
            c.addPath(p); c.setFillColor(col.cg()); c.fillPath()
            if highlight && !silhouette {
                c.saveGState(); c.addPath(p); c.clip()
                let b = p.boundingBox
                c.setFillColor(col.lighter(0.45).cg())
                c.fillEllipse(in: CGRect(x: b.minX + b.width * 0.14, y: b.minY + b.height * 0.1, width: b.width * 0.34, height: b.height * 0.24))
                c.restoreGState()
            }
            c.addPath(p); c.setStrokeColor(ink.cg()); c.setLineWidth(line); c.setLineJoin(.round); c.strokePath()
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ rad: CGFloat) {
            c.setFillColor((silhouette ? shadow.darker(0.3) : ink).cg())
            c.fillEllipse(in: CGRect(x: r.minX + (x - rad) * r.width, y: r.minY + (y - rad) * r.height, width: 2 * rad * r.width, height: 2 * rad * r.height))
        }
        func stroke(_ p: CGPath, _ color: RGB, width: CGFloat) {
            c.addPath(p); c.setStrokeColor(ink.cg()); c.setLineWidth(width + line * 2); c.setLineCap(.round); c.setLineJoin(.round); c.strokePath()
            c.addPath(p); c.setStrokeColor((silhouette ? shadow : color).cg()); c.setLineWidth(width); c.strokePath()
        }
        func star(_ cx: CGFloat, _ cy: CGFloat, _ outer: CGFloat, _ inner: CGFloat) -> CGPath {
            let p = CGMutablePath()
            for i in 0..<10 {
                let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let rad = i % 2 == 0 ? outer : inner
                let q = pt(cx + rad * cos(a), cy + rad * sin(a))
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
            return p
        }

        switch prize {
        case .sticker:
            fill(oval(0.5, 0.52, 0.44, 0.44), RGB(0xFFF8EC), highlight: false)
            fill(star(0.5, 0.54, 0.36, 0.16), RGB(0xFFD84D))
        case .rubberDuck:
            fill(oval(0.46, 0.68, 0.38, 0.22), RGB(0xFFD84D))
            fill(oval(0.66, 0.36, 0.2, 0.2), RGB(0xFFD84D))
            let beak = CGMutablePath()
            beak.move(to: pt(0.82, 0.34)); beak.addQuadCurve(to: pt(0.98, 0.42), control: pt(0.98, 0.32))
            beak.addQuadCurve(to: pt(0.82, 0.46), control: pt(0.92, 0.48)); beak.closeSubpath()
            fill(beak, RGB(0xFF8A3D), highlight: false)
            dot(0.7, 0.32, 0.03)
            let wing = CGMutablePath()
            wing.move(to: pt(0.24, 0.62)); wing.addQuadCurve(to: pt(0.5, 0.66), control: pt(0.36, 0.52))
            stroke(wing, RGB(0xF2B400), width: line)
        case .kazoo:
            let body = CGMutablePath()
            body.move(to: pt(0.08, 0.46)); body.addLine(to: pt(0.82, 0.38)); body.addLine(to: pt(0.92, 0.52))
            body.addLine(to: pt(0.82, 0.66)); body.addLine(to: pt(0.08, 0.58)); body.closeSubpath()
            fill(body, RGB(0xFF4D6D))
            fill(rect(0.42, 0.26, 0.16, 0.18, round: 0.04), RGB(0xC9CED8))
            for x in [0.3, 0.68] { fill(rect(x, 0.42, 0.04, 0.2), RGB(0xFFD84D), highlight: false) }
        case .yoyo:
            let string = CGMutablePath()
            string.move(to: pt(0.5, 0.04)); string.addQuadCurve(to: pt(0.5, 0.44), control: pt(0.62, 0.22))
            stroke(string, RGB(0xFFF8EC), width: line * 0.6)
            fill(oval(0.5, 0.62, 0.34, 0.34), RGB(0x5FC8FF))
            fill(oval(0.5, 0.62, 0.14, 0.14), RGB(0xFFF8EC), highlight: false)
            dot(0.5, 0.62, 0.04)
        case .slinky:
            for i in 0..<7 {
                let y = 0.22 + CGFloat(i) * 0.09
                let x = 0.5 + 0.08 * sin(CGFloat(i) * 0.7)
                fill(oval(x, y, 0.32, 0.08), i % 2 == 0 ? RGB(0xC9CED8) : RGB(0xB0B6C4), highlight: i == 0)
            }
        case .plushFrog:
            fill(oval(0.5, 0.66, 0.38, 0.28), RGB(0x7EDC7A))
            fill(oval(0.32, 0.32, 0.13, 0.13), RGB(0x7EDC7A), highlight: false)
            fill(oval(0.68, 0.32, 0.13, 0.13), RGB(0x7EDC7A), highlight: false)
            for x in [0.32, 0.68] { fill(oval(x, 0.32, 0.07, 0.07), RGB(0xFFF8EC), highlight: false); dot(x, 0.33, 0.03) }
            fill(oval(0.5, 0.74, 0.22, 0.14), RGB(0xD8F5C8), highlight: false)
            let smile = CGMutablePath()
            smile.move(to: pt(0.36, 0.52)); smile.addQuadCurve(to: pt(0.64, 0.52), control: pt(0.5, 0.62))
            stroke(smile, RGB(0xFF7FAE), width: line * 0.5)
        case .lavaLamp:
            let glass = CGMutablePath()
            glass.move(to: pt(0.38, 0.16)); glass.addLine(to: pt(0.62, 0.16))
            glass.addLine(to: pt(0.74, 0.72)); glass.addLine(to: pt(0.26, 0.72)); glass.closeSubpath()
            fill(glass, RGB(0xB57BFF))
            fill(oval(0.5, 0.36, 0.08, 0.1), RGB(0xFF7FAE), highlight: false)
            fill(oval(0.46, 0.6, 0.12, 0.08), RGB(0xFF7FAE), highlight: false)
            fill(rect(0.32, 0.04, 0.36, 0.13, round: 0.04), RGB(0x6F55D6))
            let base = CGMutablePath()
            base.move(to: pt(0.26, 0.72)); base.addLine(to: pt(0.74, 0.72))
            base.addLine(to: pt(0.84, 0.96)); base.addLine(to: pt(0.16, 0.96)); base.closeSubpath()
            fill(base, RGB(0x6F55D6))
        case .robot:
            fill(rect(0.24, 0.42, 0.52, 0.44, round: 0.06), RGB(0xC9CED8))
            fill(rect(0.28, 0.1, 0.44, 0.3, round: 0.06), RGB(0xC9CED8))
            for x in [0.4, 0.6] { fill(oval(x, 0.24, 0.06, 0.06), RGB(0xFFD84D), highlight: false) }
            fill(rect(0.36, 0.52, 0.28, 0.12, round: 0.02), RGB(0x5FC8FF), highlight: false)
            let key = CGMutablePath()
            key.move(to: pt(0.76, 0.62)); key.addLine(to: pt(0.92, 0.62))
            stroke(key, RGB(0xFFD84D), width: line)
            fill(oval(0.94, 0.62, 0.05, 0.1), RGB(0xFFD84D), highlight: false)
            let antenna = CGMutablePath()
            antenna.move(to: pt(0.5, 0.1)); antenna.addLine(to: pt(0.5, 0.02))
            stroke(antenna, RGB(0xC9CED8), width: line * 0.6)
            dot(0.5, 0.02, 0.03)
        case .giantBear:
            fill(oval(0.26, 0.2, 0.12, 0.12), RGB(0xC98A5A), highlight: false)
            fill(oval(0.74, 0.2, 0.12, 0.12), RGB(0xC98A5A), highlight: false)
            fill(oval(0.5, 0.74, 0.36, 0.24), RGB(0xC98A5A))
            fill(oval(0.5, 0.38, 0.3, 0.26), RGB(0xC98A5A))
            fill(oval(0.5, 0.48, 0.12, 0.09), RGB(0xF2D3B0), highlight: false)
            dot(0.4, 0.34, 0.03); dot(0.6, 0.34, 0.03); dot(0.5, 0.45, 0.035)
            let bow = CGMutablePath()
            bow.move(to: pt(0.5, 0.62)); bow.addLine(to: pt(0.36, 0.55)); bow.addLine(to: pt(0.36, 0.69)); bow.closeSubpath()
            bow.move(to: pt(0.5, 0.62)); bow.addLine(to: pt(0.64, 0.55)); bow.addLine(to: pt(0.64, 0.69)); bow.closeSubpath()
            fill(bow, RGB(0xFF4D6D), highlight: false)
        case .trophy:
            let cup = CGMutablePath()
            cup.move(to: pt(0.22, 0.1)); cup.addLine(to: pt(0.78, 0.1))
            cup.addQuadCurve(to: pt(0.5, 0.6), control: pt(0.78, 0.56))
            cup.addQuadCurve(to: pt(0.22, 0.1), control: pt(0.22, 0.56)); cup.closeSubpath()
            for side: CGFloat in [-1, 1] {
                let h = CGMutablePath()
                h.move(to: pt(0.5 + side * 0.26, 0.18))
                h.addQuadCurve(to: pt(0.5 + side * 0.22, 0.4), control: pt(0.5 + side * 0.46, 0.2))
                stroke(h, RGB(0xFFC83D), width: line * 1.2)
            }
            fill(cup, RGB(0xFFC83D))
            fill(rect(0.44, 0.58, 0.12, 0.16), RGB(0xFFC83D), highlight: false)
            fill(rect(0.28, 0.74, 0.44, 0.16, round: 0.03), RGB(0x6F55D6))
            fill(star(0.5, 0.3, 0.12, 0.05), RGB(0xFFF8EC), highlight: false)
        }
    }
}
