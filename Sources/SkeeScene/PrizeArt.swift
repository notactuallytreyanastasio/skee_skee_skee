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

        // The Neon Lounge
        case .glowSticks:
            for (i, col) in [RGB(0x7EDC7A), RGB(0xFF7FAE), RGB(0x5FC8FF)].enumerated() {
                let x = 0.3 + CGFloat(i) * 0.2
                let stick = CGMutablePath()
                stick.move(to: pt(x - 0.06, 0.88)); stick.addLine(to: pt(x + 0.06, 0.12))
                stroke(stick, col, width: r.width * 0.09)
            }
        case .rollerSkates:
            fill(rect(0.18, 0.14, 0.34, 0.5, round: 0.08), RGB(0xFF7FAE))
            fill(rect(0.18, 0.5, 0.64, 0.18, round: 0.06), RGB(0xFF7FAE))
            fill(rect(0.12, 0.66, 0.76, 0.08, round: 0.03), RGB(0xFFF8EC), highlight: false)
            for x in [0.26, 0.5, 0.74] { fill(oval(x, 0.84, 0.09, 0.09), RGB(0xFFD84D), highlight: false) }
            for y in [0.24, 0.34, 0.44] { dot(0.35, y, 0.02) }
        case .discoBall:
            let chain = CGMutablePath()
            chain.move(to: pt(0.5, 0.02)); chain.addLine(to: pt(0.5, 0.16))
            stroke(chain, RGB(0xC9CED8), width: line * 0.6)
            fill(oval(0.5, 0.55, 0.38, 0.38), RGB(0xC9CED8))
            for i in 1..<5 {
                let y = 0.17 + CGFloat(i) * 0.152
                let row = CGMutablePath(); row.move(to: pt(0.14, y)); row.addLine(to: pt(0.86, y))
                c.saveGState(); c.addPath(oval(0.5, 0.55, 0.38, 0.38)); c.clip()
                c.addPath(row); c.setStrokeColor(ink.cg(0.5)); c.setLineWidth(line * 0.5); c.strokePath()
                c.restoreGState()
            }
            if !silhouette { fill(star(0.32, 0.42, 0.08, 0.03), RGB(0xFFF8EC), highlight: false) }
        case .neonSign:
            fill(rect(0.06, 0.2, 0.88, 0.6, round: 0.08), RGB(0x2A1D33), highlight: false)
            let heart = CGMutablePath()
            heart.move(to: pt(0.5, 0.7))
            heart.addCurve(to: pt(0.5, 0.36), control1: pt(0.14, 0.5), control2: pt(0.3, 0.2))
            heart.addCurve(to: pt(0.5, 0.7), control1: pt(0.7, 0.2), control2: pt(0.86, 0.5))
            stroke(heart, RGB(0xFF4D6D), width: line * 1.1)
        case .jukebox:
            let body = CGMutablePath()
            body.move(to: pt(0.16, 0.94)); body.addLine(to: pt(0.16, 0.42))
            body.addArc(center: pt(0.5, 0.42), radius: 0.34 * r.width, startAngle: .pi, endAngle: 0, clockwise: false)
            body.addLine(to: pt(0.84, 0.94)); body.closeSubpath()
            fill(body, RGB(0xFF8A3D))
            fill(rect(0.28, 0.3, 0.44, 0.24, round: 0.1), RGB(0xFFD84D), highlight: false)
            for x in [0.3, 0.42, 0.54, 0.66] { fill(rect(x, 0.62, 0.06, 0.24, round: 0.02), RGB(0x5FC8FF), highlight: false) }
        case .arcadeCabinet:
            fill(rect(0.24, 0.06, 0.52, 0.9, round: 0.04), RGB(0x6F55D6))
            fill(rect(0.3, 0.16, 0.4, 0.3, round: 0.03), RGB(0x2A1D33), highlight: false)
            fill(star(0.5, 0.31, 0.08, 0.035), RGB(0xFFD84D), highlight: false)
            fill(rect(0.24, 0.52, 0.52, 0.12), RGB(0xFF6FA5), highlight: false)
            fill(oval(0.4, 0.58, 0.04, 0.04), RGB(0xFF4D6D), highlight: false)
            fill(oval(0.58, 0.58, 0.035, 0.035), RGB(0x7EDC7A), highlight: false)

        // The High Roller Suite
        case .cufflinks:
            for x in [0.3, 0.7] {
                fill(oval(x, 0.5, 0.18, 0.18), RGB(0xFFC83D))
                fill(oval(x, 0.5, 0.08, 0.08), RGB(0x5FC8FF), highlight: false)
            }
        case .champagne:
            let bottle = CGMutablePath()
            bottle.move(to: pt(0.42, 0.06)); bottle.addLine(to: pt(0.58, 0.06)); bottle.addLine(to: pt(0.58, 0.34))
            bottle.addQuadCurve(to: pt(0.72, 0.5), control: pt(0.72, 0.38)); bottle.addLine(to: pt(0.72, 0.94))
            bottle.addLine(to: pt(0.28, 0.94)); bottle.addLine(to: pt(0.28, 0.5))
            bottle.addQuadCurve(to: pt(0.42, 0.34), control: pt(0.28, 0.38)); bottle.closeSubpath()
            fill(bottle, RGB(0x3E8E5A))
            fill(rect(0.4, 0.04, 0.2, 0.16, round: 0.03), RGB(0xFFC83D), highlight: false)
            fill(rect(0.3, 0.58, 0.4, 0.2, round: 0.02), RGB(0xFFF8EC), highlight: false)
        case .pearlNecklace:
            for i in 0..<11 {
                let a = CGFloat.pi * (0.1 + 0.8 * CGFloat(i) / 10)
                fill(oval(0.5 - 0.36 * cos(a), 0.3 + 0.48 * sin(a), 0.065, 0.065), RGB(0xFFF8EC))
            }
        case .goldWatch:
            fill(rect(0.38, 0.02, 0.24, 0.96, round: 0.06), RGB(0x8A5A3C), highlight: false)
            fill(oval(0.5, 0.5, 0.3, 0.3), RGB(0xFFC83D))
            fill(oval(0.5, 0.5, 0.22, 0.22), RGB(0xFFF8EC), highlight: false)
            let hands = CGMutablePath()
            hands.move(to: pt(0.5, 0.36)); hands.addLine(to: pt(0.5, 0.5)); hands.addLine(to: pt(0.6, 0.56))
            stroke(hands, RGB(0x2A1D33), width: line * 0.5)
        case .chandelier:
            let chain = CGMutablePath(); chain.move(to: pt(0.5, 0.0)); chain.addLine(to: pt(0.5, 0.2))
            stroke(chain, RGB(0xFFC83D), width: line * 0.6)
            let arms = CGMutablePath()
            arms.move(to: pt(0.12, 0.42)); arms.addQuadCurve(to: pt(0.88, 0.42), control: pt(0.5, 0.78))
            stroke(arms, RGB(0xFFC83D), width: line)
            for x in [0.12, 0.31, 0.5, 0.69, 0.88] {
                fill(rect(x - 0.035, 0.28, 0.07, 0.14), RGB(0xFFF8EC), highlight: false)
                fill(oval(x, 0.24, 0.025, 0.04), RGB(0xFFD84D), highlight: false)
                fill(oval(x, 0.72, 0.04, 0.07), RGB(0xBFEFFF), highlight: false)
            }
        case .sportsCar:
            let body = CGMutablePath()
            body.move(to: pt(0.04, 0.7)); body.addLine(to: pt(0.06, 0.52)); body.addLine(to: pt(0.32, 0.46))
            body.addQuadCurve(to: pt(0.66, 0.44), control: pt(0.48, 0.24)); body.addLine(to: pt(0.94, 0.54))
            body.addLine(to: pt(0.96, 0.7)); body.closeSubpath()
            fill(body, RGB(0xFF4D6D))
            fill(rect(0.4, 0.34, 0.18, 0.1, round: 0.03), RGB(0xBFEFFF), highlight: false)
            for x in [0.24, 0.76] { fill(oval(x, 0.72, 0.1, 0.1), RGB(0x2A1D33), highlight: false); fill(oval(x, 0.72, 0.04, 0.04), RGB(0xC9CED8), highlight: false) }

        // The Penthouse
        case .goldenFlamingo:
            let neck = CGMutablePath()
            neck.move(to: pt(0.5, 0.52)); neck.addQuadCurve(to: pt(0.6, 0.16), control: pt(0.3, 0.3))
            stroke(neck, RGB(0xFFC83D), width: line * 1.6)
            fill(oval(0.62, 0.16, 0.08, 0.07), RGB(0xFFC83D), highlight: false)
            fill(oval(0.56, 0.58, 0.26, 0.15), RGB(0xFFC83D))
            for x in [0.5, 0.58] {
                let leg = CGMutablePath(); leg.move(to: pt(x, 0.7)); leg.addLine(to: pt(x, 0.96))
                stroke(leg, RGB(0xFFC83D), width: line * 0.7)
            }
            dot(0.64, 0.14, 0.015)
        case .hotTub:
            fill(rect(0.06, 0.46, 0.88, 0.44, round: 0.1), RGB(0x8A5A3C))
            fill(oval(0.5, 0.48, 0.42, 0.1), RGB(0x5FC8FF), highlight: false)
            for (x, y, rr) in [(0.32, 0.3, 0.05), (0.5, 0.2, 0.07), (0.68, 0.32, 0.045)] { fill(oval(x, y, rr, rr), RGB(0xFFF8EC), highlight: false) }
        case .grandPiano:
            let lid = CGMutablePath()
            lid.move(to: pt(0.1, 0.5)); lid.addLine(to: pt(0.84, 0.5))
            lid.addQuadCurve(to: pt(0.6, 0.2), control: pt(0.9, 0.2)); lid.addLine(to: pt(0.1, 0.2)); lid.closeSubpath()
            fill(lid, RGB(0x2A1D33))
            fill(rect(0.1, 0.5, 0.74, 0.12), RGB(0x2A1D33), highlight: false)
            for i in 0..<7 { fill(rect(0.12 + CGFloat(i) * 0.1, 0.5, 0.09, 0.08), RGB(0xFFF8EC), highlight: false) }
            for x in [0.16, 0.78] { fill(rect(x, 0.62, 0.05, 0.3), RGB(0x2A1D33), highlight: false) }
        case .yacht:
            let hull = CGMutablePath()
            hull.move(to: pt(0.04, 0.6)); hull.addLine(to: pt(0.96, 0.6)); hull.addLine(to: pt(0.82, 0.82))
            hull.addLine(to: pt(0.16, 0.82)); hull.closeSubpath()
            fill(hull, RGB(0xFFF8EC))
            fill(rect(0.26, 0.42, 0.46, 0.18, round: 0.04), RGB(0xFFF8EC))
            fill(rect(0.36, 0.28, 0.24, 0.14, round: 0.04), RGB(0xFFF8EC))
            for x in [0.32, 0.46, 0.6] { fill(rect(x, 0.47, 0.08, 0.06, round: 0.02), RGB(0x5FC8FF), highlight: false) }
            let wave = CGMutablePath(); wave.move(to: pt(0.02, 0.9)); wave.addQuadCurve(to: pt(0.98, 0.9), control: pt(0.5, 0.98))
            stroke(wave, RGB(0x5FC8FF), width: line)
        case .privateJet:
            let body = CGMutablePath()
            body.move(to: pt(0.04, 0.52)); body.addQuadCurve(to: pt(0.2, 0.42), control: pt(0.06, 0.42))
            body.addLine(to: pt(0.86, 0.42)); body.addLine(to: pt(0.96, 0.24)); body.addLine(to: pt(0.96, 0.56))
            body.addLine(to: pt(0.2, 0.6)); body.closeSubpath()
            fill(body, RGB(0xFFF8EC))
            let wing = CGMutablePath()
            wing.move(to: pt(0.4, 0.56)); wing.addLine(to: pt(0.62, 0.56)); wing.addLine(to: pt(0.46, 0.84)); wing.addLine(to: pt(0.36, 0.84)); wing.closeSubpath()
            fill(wing, RGB(0xC9CED8))
            for i in 0..<5 { fill(oval(0.28 + CGFloat(i) * 0.1, 0.49, 0.025, 0.03), RGB(0x5FC8FF), highlight: false) }
        case .diamondCrown:
            let crown = CGMutablePath()
            crown.move(to: pt(0.1, 0.8)); crown.addLine(to: pt(0.1, 0.3)); crown.addLine(to: pt(0.3, 0.52))
            crown.addLine(to: pt(0.5, 0.18)); crown.addLine(to: pt(0.7, 0.52)); crown.addLine(to: pt(0.9, 0.3))
            crown.addLine(to: pt(0.9, 0.8)); crown.closeSubpath()
            fill(crown, RGB(0xFFC83D))
            fill(rect(0.1, 0.72, 0.8, 0.12, round: 0.02), RGB(0xFFD84D), highlight: false)
            for (x, col) in [(0.3, RGB(0xFF4D6D)), (0.5, RGB(0x5FC8FF)), (0.7, RGB(0x7EDC7A))] { fill(oval(x, 0.78, 0.05, 0.04), col, highlight: false) }
            fill(star(0.5, 0.44, 0.09, 0.04), RGB(0xBFEFFF), highlight: false)
        }
    }
}
