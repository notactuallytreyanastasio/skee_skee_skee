import CoreGraphics
import SkeeCore

public struct RGB: Hashable, Sendable {
    public var r, g, b: CGFloat
    public init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    init(r: CGFloat, g: CGFloat, b: CGFloat) { self.r = r; self.g = g; self.b = b }

    public func cg(_ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    public func mix(_ o: RGB, _ t: CGFloat) -> RGB {
        RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }
    public func lighter(_ t: CGFloat) -> RGB { mix(RGB(0xFFFFFF), t) }
    public func darker(_ t: CGFloat) -> RGB { mix(RGB(0x000000), t) }
}

/// Every colour a style uses. Each style is a full palette, not a tint, so
/// the transitions between eras feel like walking into a different arcade.
public struct Palette: Sendable {
    public var background: RGB
    public var backgroundDeep: RGB
    public var boardFelt: RGB
    public var ringZones: [RGB]       // 40 cup outward to 10
    public var ringLip: RGB
    public var hole: RGB
    public var lane: RGB
    public var laneLine: RGB
    public var hinge: RGB
    public var ball: RGB
    public var ballShade: RGB
    public var outline: RGB
    public var text: RGB
    public var textDim: RGB
    public var chips: RGB
    public var mult: RGB
    public var tickets: RGB
    public var good: RGB
    public var bad: RGB
    public var panel: RGB
    public var panelEdge: RGB

    public func symbol(_ s: Symbol, _ role: GlyphPart.Role) -> RGB {
        let base: (RGB, RGB, RGB) = switch s {
        case .cherry: (RGB(0xE43B44), RGB(0x3E8948), RGB(0xFFFFFF))
        case .lemon: (RGB(0xFEE761), RGB(0x63C74D), RGB(0xFFFFFF))
        case .bell: (RGB(0xFEAE34), RGB(0xB86F50), RGB(0xFFF4C0))
        case .bar: (RGB(0xC0CBDC), RGB(0x5A6988), RGB(0xFFFFFF))
        case .seven: (RGB(0xE43B44), RGB(0x9E2835), RGB(0xFFD0D0))
        case .diamond: (RGB(0x2CE8F5), RGB(0x0099DB), RGB(0xFFFFFF))
        case .clover: (RGB(0x63C74D), RGB(0x265C42), RGB(0xC8FFB0))
        case .blank: (RGB(0x5A6988), RGB(0x3A4466), RGB(0x8B9BB4))
        }
        switch role {
        case .primary: return base.0
        case .secondary: return base.1
        case .accent: return base.2
        case .dark: return outline
        }
    }

    public static func of(_ style: ArtStyle) -> Palette {
        switch style {
        case .pixel:
            // Endesga-32-ish: a small, warm, slightly dusty set.
            Palette(background: RGB(0x181425), backgroundDeep: RGB(0x0E0B18),
                    boardFelt: RGB(0x262B44),
                    ringZones: [RGB(0x3A4466), RGB(0x262B44), RGB(0x3A4466), RGB(0x262B44)],
                    ringLip: RGB(0xFEAE34), hole: RGB(0x0E0B18),
                    lane: RGB(0xB86F50), laneLine: RGB(0x743F39), hinge: RGB(0xE4A672),
                    ball: RGB(0xF4F4F4), ballShade: RGB(0x8B9BB4), outline: RGB(0x0E0B18),
                    text: RGB(0xFFFFFF), textDim: RGB(0x8B9BB4),
                    chips: RGB(0x0099DB), mult: RGB(0xE43B44), tickets: RGB(0xFEE761),
                    good: RGB(0x63C74D), bad: RGB(0xE43B44),
                    panel: RGB(0x262B44), panelEdge: RGB(0xFEAE34))
        case .cel:
            // Saturday-morning cartoon: big flat colours, black ink lines.
            Palette(background: RGB(0xFFC94D), backgroundDeep: RGB(0xF79E2C),
                    boardFelt: RGB(0x2F9FD7),
                    ringZones: [RGB(0xFF5D73), RGB(0xFFE066), RGB(0x7BE07B), RGB(0x6FD3FF)],
                    ringLip: RGB(0xFFFFFF), hole: RGB(0x1A1A2E),
                    lane: RGB(0xF2A65A), laneLine: RGB(0xC46A2B), hinge: RGB(0xFFFFFF),
                    ball: RGB(0xFFFFFF), ballShade: RGB(0xB8C4FF), outline: RGB(0x111111),
                    text: RGB(0x111111), textDim: RGB(0x5A3A1A),
                    chips: RGB(0x2F7BFF), mult: RGB(0xFF3B3B), tickets: RGB(0xFFD60A),
                    good: RGB(0x2BB24C), bad: RGB(0xE5383B),
                    panel: RGB(0xFFF4D6), panelEdge: RGB(0x111111))
        case .depth:
            // A real cabinet: maple lane, green felt, brass lips, chrome ball.
            Palette(background: RGB(0x14100E), backgroundDeep: RGB(0x060404),
                    boardFelt: RGB(0x1D4D3A),
                    ringZones: [RGB(0x2A6B50), RGB(0x225C44), RGB(0x2A6B50), RGB(0x225C44)],
                    ringLip: RGB(0xD9A441), hole: RGB(0x050505),
                    lane: RGB(0xC8925A), laneLine: RGB(0x8E5E33), hinge: RGB(0xE8C48A),
                    ball: RGB(0xE9EEF2), ballShade: RGB(0x5B6670), outline: RGB(0x0B0806),
                    text: RGB(0xF6EBD9), textDim: RGB(0xA89A85),
                    chips: RGB(0x4DA3FF), mult: RGB(0xFF5A4D), tickets: RGB(0xF2C14E),
                    good: RGB(0x6BD18B), bad: RGB(0xFF5A4D),
                    panel: RGB(0x2A1E16), panelEdge: RGB(0xD9A441))
        case .neon:
            // Vector monitor at midnight: black glass, glowing strokes.
            Palette(background: RGB(0x05010F), backgroundDeep: RGB(0x000000),
                    boardFelt: RGB(0x0A0420),
                    ringZones: [RGB(0xFF2BD6), RGB(0x8A2BFF), RGB(0x2B6BFF), RGB(0x00E5FF)],
                    ringLip: RGB(0x00E5FF), hole: RGB(0x000000),
                    lane: RGB(0x0A0420), laneLine: RGB(0xFF2BD6), hinge: RGB(0xFFE14D),
                    ball: RGB(0xFFFFFF), ballShade: RGB(0x00E5FF), outline: RGB(0x000000),
                    text: RGB(0xE8FCFF), textDim: RGB(0x6A7FA8),
                    chips: RGB(0x00E5FF), mult: RGB(0xFF2BD6), tickets: RGB(0xFFE14D),
                    good: RGB(0x39FF88), bad: RGB(0xFF3355),
                    panel: RGB(0x0A0420), panelEdge: RGB(0xFF2BD6))
        }
    }
}
