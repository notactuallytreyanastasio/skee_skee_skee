import CoreGraphics
import CoreText
import Foundation
import SkeeCore

/// Style-aware drawing primitives. Everything above this file says *what* to
/// draw (a disc, a panel, a glyph, some text); the pen decides how each era
/// draws it: flat pixels, inked cartoon, lit and shaded, or glowing lines.
struct Pen {
    let ctx: CGContext
    let style: ArtStyle
    let pal: Palette
    let time: Double

    // MARK: shapes

    /// A filled shape in this style's manner.
    func fill(_ path: CGPath, _ color: RGB, light: Bool = true) {
        switch style {
        case .pixel:
            ctx.addPath(path); ctx.setFillColor(color.cg()); ctx.fillPath()
        case .cel:
            ctx.addPath(path); ctx.setFillColor(color.cg()); ctx.fillPath()
            if light {
                // One hard-edged highlight band: the top third, clipped.
                ctx.saveGState()
                ctx.addPath(path); ctx.clip()
                let b = path.boundingBox
                ctx.setFillColor(color.lighter(0.35).cg())
                ctx.fill(CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height * 0.3))
                ctx.restoreGState()
            }
            ink(path, width: 3)
        case .depth:
            let b = path.boundingBox
            ctx.saveGState()
            ctx.addPath(path); ctx.clip()
            if light {
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                   colors: [color.lighter(0.3).cg(), color.cg(), color.darker(0.3).cg()] as CFArray,
                                   locations: [0, 0.45, 1])!
                // Light from above and slightly left; extend past both ends
                // so wide shapes are fully covered.
                ctx.drawLinearGradient(g, start: CGPoint(x: b.minX, y: b.minY),
                                       end: CGPoint(x: b.minX + b.height * 0.25, y: b.maxY),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            } else {
                ctx.setFillColor(color.cg()); ctx.fill(b)
            }
            ctx.restoreGState()
        case .neon:
            ctx.addPath(path); ctx.setFillColor(color.cg(0.12)); ctx.fillPath()
            glow(path, color, width: 2)
        }
    }

    /// Black ink outline (cel), pixel outline, thin rim (depth), glow (neon).
    func ink(_ path: CGPath, width: CGFloat) {
        ctx.addPath(path)
        ctx.setStrokeColor(pal.outline.cg())
        ctx.setLineWidth(width)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    func glow(_ path: CGPath, _ color: RGB, width: CGFloat) {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 10, color: color.cg(0.9))
        ctx.addPath(path); ctx.setStrokeColor(color.cg(0.55)); ctx.setLineWidth(width * 2.5); ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(path); ctx.setStrokeColor(color.lighter(0.5).cg()); ctx.setLineWidth(width); ctx.strokePath()
    }

    /// A line in this style.
    func line(_ path: CGPath, _ color: RGB, width: CGFloat) {
        switch style {
        case .neon: glow(path, color, width: width)
        case .cel:
            ink(path, width: width + 3)
            ctx.addPath(path); ctx.setStrokeColor(color.cg()); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.strokePath()
        default:
            ctx.addPath(path); ctx.setStrokeColor(color.cg()); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.strokePath()
        }
    }

    /// A ball (or any sphere): flat disc, inked disc with a shine, lit sphere
    /// with a specular dot, or a glowing ring.
    func sphere(_ c: CGPoint, _ r: CGFloat, _ color: RGB, shade: RGB) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        let disc = CGPath(ellipseIn: rect, transform: nil)
        switch style {
        case .pixel:
            ctx.addPath(disc); ctx.setFillColor(color.cg()); ctx.fillPath()
            ctx.setFillColor(shade.cg())
            ctx.addPath(CGPath(ellipseIn: rect.insetBy(dx: r * 0.15, dy: r * 0.15).offsetBy(dx: r * 0.25, dy: r * 0.25), transform: nil))
            ctx.addPath(disc)
            ctx.fillPath(using: .evenOdd)
            ctx.setFillColor(RGB(0xFFFFFF).cg())
            ctx.fill(CGRect(x: c.x - r * 0.5, y: c.y - r * 0.55, width: max(1, r * 0.35), height: max(1, r * 0.35)))
            ink(disc, width: 1)
        case .cel:
            ctx.addPath(disc); ctx.setFillColor(color.cg()); ctx.fillPath()
            ctx.saveGState(); ctx.addPath(disc); ctx.clip()
            ctx.setFillColor(shade.cg())
            ctx.fillEllipse(in: rect.offsetBy(dx: r * 0.45, dy: r * 0.45).insetBy(dx: -r * 0.2, dy: -r * 0.2))
            ctx.restoreGState()
            ctx.setFillColor(RGB(0xFFFFFF).cg())
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.6, width: r * 0.45, height: r * 0.3))
            ink(disc, width: 3)
        case .depth:
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [RGB(0xFFFFFF).cg(), color.cg(), shade.cg(), shade.darker(0.6).cg()] as CFArray,
                               locations: [0, 0.25, 0.75, 1])!
            ctx.saveGState(); ctx.addPath(disc); ctx.clip()
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0,
                                   endCenter: c, endRadius: r * 1.05, options: [.drawsAfterEndLocation])
            ctx.restoreGState()
        case .neon:
            ctx.addPath(disc); ctx.setFillColor(color.cg(0.25)); ctx.fillPath()
            glow(disc, shade, width: 2)
            ctx.setFillColor(RGB(0xFFFFFF).cg())
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.2, y: c.y - r * 0.2, width: r * 0.4, height: r * 0.4))
        }
    }

    func shadow(_ c: CGPoint, _ r: CGFloat, alpha: CGFloat) {
        guard style != .neon else { return }
        ctx.setFillColor(RGB(0x000000).cg(alpha * (style == .depth ? 0.55 : 0.35)))
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.45, width: 2 * r, height: r * 0.9))
    }

    /// A rounded panel / card / button.
    func panel(_ rect: CGRect, fill: RGB? = nil, edge: RGB? = nil, radius: CGFloat = 10) {
        let fillC = fill ?? pal.panel, edgeC = edge ?? pal.panelEdge
        switch style {
        case .pixel:
            let r = rect.integral
            ctx.setFillColor(pal.outline.cg()); ctx.fill(r.insetBy(dx: -2, dy: -2))
            ctx.setFillColor(edgeC.cg()); ctx.fill(r)
            ctx.setFillColor(fillC.cg()); ctx.fill(r.insetBy(dx: 2, dy: 2))
        case .cel:
            let p = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.saveGState()
            ctx.translateBy(x: 4, y: 5)
            ctx.addPath(p); ctx.setFillColor(pal.outline.cg()); ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(p); ctx.setFillColor(fillC.cg()); ctx.fillPath()
            ink(p, width: 3)
        case .depth:
            let p = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 14, color: RGB(0x000000).cg(0.7))
            ctx.addPath(p); ctx.setFillColor(fillC.cg()); ctx.fillPath()
            ctx.restoreGState()
            self.fill(p, fillC)
            ctx.addPath(p); ctx.setStrokeColor(edgeC.cg(0.8)); ctx.setLineWidth(1.5); ctx.strokePath()
        case .neon:
            let p = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.addPath(p); ctx.setFillColor(fillC.cg(0.85)); ctx.fillPath()
            glow(p, edgeC, width: 1.5)
        }
    }

    // MARK: glyphs

    /// A reel symbol in `rect`.
    func glyph(_ s: Symbol, in rect: CGRect) {
        let parts = Glyphs.parts(s)
        guard !parts.isEmpty else {
            if style != .pixel {
                text("-", at: CGPoint(x: rect.midX, y: rect.midY), size: rect.height * 0.5, color: pal.textDim, align: .center)
            }
            return
        }
        var t = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height)
        for part in parts {
            guard let p = part.path.copy(using: &t) else { continue }
            if style == .pixel && part.role == .dark {
                // Lettering is finer than a pixel at this size: draw the
                // classic dark band across the plate instead.
                ctx.setFillColor(pal.outline.cg())
                ctx.fill(CGRect(x: rect.minX + rect.width * 0.18, y: rect.midY - rect.height * 0.07,
                                width: rect.width * 0.64, height: max(3, rect.height * 0.14)))
                continue
            }
            let c = pal.symbol(s, part.role)
            switch style {
            case .cel:
                ctx.addPath(p); ctx.setFillColor(c.cg()); ctx.fillPath()
            case .neon:
                if part.role == .primary || part.role == .secondary { glow(p, c, width: 1.4) }
                else { ctx.addPath(p); ctx.setFillColor(c.cg()); ctx.fillPath() }
            case .depth where part.role == .primary:
                fill(p, c)
            default:
                ctx.addPath(p); ctx.setFillColor(c.cg()); ctx.fillPath()
            }
        }
        if style == .cel || style == .pixel {
            // Ink the silhouette of the main shapes.
            for part in parts where part.role == .primary {
                if let p = part.path.copy(using: &t) { ink(p, width: style == .cel ? 2 : 1) }
            }
        }
    }

    // MARK: text

    enum Align { case left, center, right }

    /// Text in the era's typeface. Pixel uses the 5x7 bitmap font; the others
    /// use outline fonts treated in-style.
    @discardableResult
    func text(_ s: String, at p: CGPoint, size: CGFloat, color: RGB, align: Align = .left, bold: Bool = true) -> CGFloat {
        if style == .pixel { return pixelText(s.uppercased(), at: p, size: size, color: color, align: align) }
        let name: String = switch style {
        case .cel: "AvenirNext-Heavy"
        case .depth: bold ? "Georgia-Bold" : "Georgia"
        case .neon: "AvenirNextCondensed-DemiBold"
        case .pixel: ""
        }
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let tracking: CGFloat = style == .neon ? size * 0.12 : 0
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cg(),
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
        ]
        let str = style == .neon ? s.uppercased() : s
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: str, attributes: attrs))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let x: CGFloat = switch align {
        case .left: p.x
        case .center: p.x - width / 2
        case .right: p.x - width
        }
        let baseline = p.y + size * 0.35
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        switch style {
        case .cel:
            // Thick ink outline behind the fill.
            ctx.setTextDrawingMode(.stroke)
            ctx.setLineWidth(max(2, size * 0.16)); ctx.setLineJoin(.round)
            let outlineAttrs = attrs.merging([NSAttributedString.Key(kCTForegroundColorAttributeName as String): pal.outline.cg()]) { $1 }
            let ol = CTLineCreateWithAttributedString(NSAttributedString(string: str, attributes: outlineAttrs))
            ctx.setStrokeColor(pal.outline.cg())
            ctx.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(ol, ctx)
            ctx.setTextDrawingMode(.fill)
        case .depth:
            ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: RGB(0x000000).cg(0.8))
        case .neon:
            ctx.setShadow(offset: .zero, blur: size * 0.5, color: color.cg(0.9))
        case .pixel: break
        }
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        return width
    }

    @discardableResult
    func pixelText(_ s: String, at p: CGPoint, size: CGFloat, color: RGB, align: Align) -> CGFloat {
        // Cells snap to whole low-res pixels or the glyphs smear.
        let k = Renderer.pixelScale
        let cell = max(k, ((size / 7) / k + 0.2).rounded(.down) * k)
        let width = CGFloat(PixelFont.cells(s)) * cell
        var x: CGFloat = switch align {
        case .left: p.x
        case .center: p.x - width / 2
        case .right: p.x - width
        }
        x = x.rounded()
        let top = (p.y - 3.5 * cell).rounded()
        func draw(_ c: RGB, dx: CGFloat, dy: CGFloat) {
            ctx.setFillColor(c.cg())
            var cx = x
            for ch in s {
                if let rows = PixelFont.rows(ch) {
                    for (ry, row) in rows.enumerated() {
                        for (rx, bit) in row.enumerated() where bit == "#" {
                            ctx.fill(CGRect(x: cx + CGFloat(rx) * cell + dx, y: top + CGFloat(ry) * cell + dy, width: cell, height: cell))
                        }
                    }
                }
                cx += CGFloat(PixelFont.width + 1) * cell
            }
        }
        draw(pal.outline, dx: cell, dy: cell)   // drop shadow, one cell
        draw(color, dx: 0, dy: 0)
        return width
    }

    /// Characters per line that fit `width` at `size` in this style.
    func chars(fitting width: CGFloat, size: CGFloat) -> Int {
        if style == .pixel {
            let k = Renderer.pixelScale
            let cell = max(k, ((size / 7) / k + 0.2).rounded(.down) * k)
            return max(4, Int(width / (CGFloat(PixelFont.width + 1) * cell)))
        }
        return max(4, Int(width / (size * (style == .neon ? 0.62 : 0.56))))
    }

    /// Wrap `s` to lines of at most `chars` characters.
    static func wrap(_ s: String, chars: Int) -> [String] {
        var lines: [String] = [], cur = ""
        for word in s.split(separator: " ") {
            if cur.isEmpty { cur = String(word) }
            else if cur.count + 1 + word.count <= chars { cur += " " + word }
            else { lines.append(cur); cur = String(word) }
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }
}
