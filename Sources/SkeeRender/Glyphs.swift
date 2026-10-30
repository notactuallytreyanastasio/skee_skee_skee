import CoreGraphics
import SkeeCore

/// Procedural reel symbols. Every symbol is a set of filled shapes in a unit
/// box (0...1, y down), each tagged with a colour role, so each art style
/// can fill, outline, shade or glow the same geometry its own way.
/// No emoji, no bitmaps.
public struct GlyphPart: @unchecked Sendable { // CGPath is immutable
    public enum Role: Sendable { case primary, secondary, accent, dark }
    public var path: CGPath
    public var role: Role
}

public enum Glyphs {
    public static func parts(_ s: Symbol) -> [GlyphPart] {
        switch s {
        case .blank: []
        case .cherry: cherry
        case .lemon: lemon
        case .bell: bell
        case .bar: bar
        case .seven: seven
        case .diamond: diamond
        case .clover: clover
        }
    }

    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2), transform: nil)
    }

    static func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    static func stroke(_ path: CGPath, width: CGFloat) -> CGPath {
        path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4)
    }

    static let cherry: [GlyphPart] = {
        let stems = CGMutablePath()
        stems.move(to: CGPoint(x: 0.30, y: 0.62))
        stems.addQuadCurve(to: CGPoint(x: 0.62, y: 0.14), control: CGPoint(x: 0.36, y: 0.30))
        stems.move(to: CGPoint(x: 0.70, y: 0.66))
        stems.addQuadCurve(to: CGPoint(x: 0.62, y: 0.14), control: CGPoint(x: 0.72, y: 0.36))
        let leaf = CGMutablePath()
        leaf.move(to: CGPoint(x: 0.62, y: 0.15))
        leaf.addQuadCurve(to: CGPoint(x: 0.90, y: 0.20), control: CGPoint(x: 0.80, y: 0.02))
        leaf.addQuadCurve(to: CGPoint(x: 0.62, y: 0.15), control: CGPoint(x: 0.78, y: 0.30))
        return [
            GlyphPart(path: stroke(stems, width: 0.06), role: .secondary),
            GlyphPart(path: leaf, role: .secondary),
            GlyphPart(path: circle(0.30, 0.70, 0.19), role: .primary),
            GlyphPart(path: circle(0.70, 0.73, 0.19), role: .primary),
            GlyphPart(path: circle(0.24, 0.64, 0.05), role: .accent),
            GlyphPart(path: circle(0.64, 0.67, 0.05), role: .accent),
        ]
    }()

    static let lemon: [GlyphPart] = {
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 0.08, y: 0.52))
        body.addQuadCurve(to: CGPoint(x: 0.50, y: 0.20), control: CGPoint(x: 0.18, y: 0.20))
        body.addQuadCurve(to: CGPoint(x: 0.92, y: 0.48), control: CGPoint(x: 0.82, y: 0.20))
        body.addQuadCurve(to: CGPoint(x: 0.50, y: 0.80), control: CGPoint(x: 0.82, y: 0.80))
        body.addQuadCurve(to: CGPoint(x: 0.08, y: 0.52), control: CGPoint(x: 0.18, y: 0.80))
        body.closeSubpath()
        return [
            GlyphPart(path: body, role: .primary),
            GlyphPart(path: circle(0.36, 0.40, 0.07), role: .accent),
        ]
    }()

    static let bell: [GlyphPart] = {
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 0.50, y: 0.12))
        body.addCurve(to: CGPoint(x: 0.80, y: 0.66), control1: CGPoint(x: 0.76, y: 0.12), control2: CGPoint(x: 0.72, y: 0.52))
        body.addLine(to: CGPoint(x: 0.90, y: 0.76))
        body.addLine(to: CGPoint(x: 0.10, y: 0.76))
        body.addLine(to: CGPoint(x: 0.20, y: 0.66))
        body.addCurve(to: CGPoint(x: 0.50, y: 0.12), control1: CGPoint(x: 0.28, y: 0.52), control2: CGPoint(x: 0.24, y: 0.12))
        body.closeSubpath()
        return [
            GlyphPart(path: circle(0.50, 0.84, 0.09), role: .secondary),
            GlyphPart(path: body, role: .primary),
            GlyphPart(path: circle(0.50, 0.10, 0.05), role: .secondary),
            GlyphPart(path: poly([(0.34, 0.30), (0.40, 0.30), (0.34, 0.62), (0.28, 0.62)]), role: .accent),
        ]
    }()

    static let bar: [GlyphPart] = {
        let plate = CGPath(roundedRect: CGRect(x: 0.06, y: 0.30, width: 0.88, height: 0.40),
                           cornerWidth: 0.06, cornerHeight: 0.06, transform: nil)
        // Letters B A R as blocky polygons so every style can draw them.
        let letters = CGMutablePath()
        // B
        letters.addRect(CGRect(x: 0.15, y: 0.38, width: 0.05, height: 0.24))
        letters.addRect(CGRect(x: 0.15, y: 0.38, width: 0.13, height: 0.05))
        letters.addRect(CGRect(x: 0.15, y: 0.475, width: 0.13, height: 0.05))
        letters.addRect(CGRect(x: 0.15, y: 0.57, width: 0.13, height: 0.05))
        letters.addRect(CGRect(x: 0.26, y: 0.38, width: 0.05, height: 0.24))
        // A
        letters.addRect(CGRect(x: 0.40, y: 0.38, width: 0.05, height: 0.24))
        letters.addRect(CGRect(x: 0.53, y: 0.38, width: 0.05, height: 0.24))
        letters.addRect(CGRect(x: 0.40, y: 0.38, width: 0.18, height: 0.05))
        letters.addRect(CGRect(x: 0.40, y: 0.48, width: 0.18, height: 0.05))
        // R
        letters.addRect(CGRect(x: 0.67, y: 0.38, width: 0.05, height: 0.24))
        letters.addRect(CGRect(x: 0.67, y: 0.38, width: 0.16, height: 0.05))
        letters.addRect(CGRect(x: 0.78, y: 0.38, width: 0.05, height: 0.13))
        letters.addRect(CGRect(x: 0.67, y: 0.475, width: 0.16, height: 0.05))
        letters.addPath(poly([(0.74, 0.52), (0.80, 0.52), (0.85, 0.62), (0.79, 0.62)]))
        return [
            GlyphPart(path: plate, role: .primary),
            GlyphPart(path: letters, role: .dark),
        ]
    }()

    static let seven: [GlyphPart] = [
        GlyphPart(path: poly([(0.16, 0.14), (0.86, 0.14), (0.86, 0.28), (0.52, 0.90),
                              (0.32, 0.90), (0.64, 0.30), (0.16, 0.30)]), role: .primary),
        GlyphPart(path: poly([(0.22, 0.18), (0.80, 0.18), (0.80, 0.22), (0.22, 0.22)]), role: .accent),
    ]

    static let diamond: [GlyphPart] = [
        GlyphPart(path: poly([(0.50, 0.08), (0.92, 0.42), (0.50, 0.94), (0.08, 0.42)]), role: .primary),
        GlyphPart(path: poly([(0.30, 0.42), (0.50, 0.24), (0.70, 0.42), (0.50, 0.80)]), role: .secondary),
        GlyphPart(path: poly([(0.50, 0.08), (0.62, 0.42), (0.50, 0.42), (0.38, 0.42)]), role: .accent),
    ]

    static let clover: [GlyphPart] = {
        let stem = CGMutablePath()
        stem.move(to: CGPoint(x: 0.50, y: 0.50))
        stem.addQuadCurve(to: CGPoint(x: 0.66, y: 0.94), control: CGPoint(x: 0.50, y: 0.80))
        let leaves = CGMutablePath()
        for (cx, cy) in [(0.50, 0.27), (0.27, 0.48), (0.73, 0.48), (0.50, 0.66)] {
            leaves.addPath(circle(cx, cy, 0.17))
        }
        return [
            GlyphPart(path: stroke(stem, width: 0.07), role: .secondary),
            GlyphPart(path: leaves, role: .primary),
            GlyphPart(path: circle(0.50, 0.48, 0.06), role: .accent),
        ]
    }()
}

/// A 5x7 bitmap font, drawn cell by cell. The pixel style uses it for all
/// text; other styles use it for tiny labels where it reads better than a
/// scaled-down outline font.
public enum PixelFont {
    public static let width = 5, height = 7

    public static func rows(_ c: Character) -> [String]? { table[Character(c.uppercased())] }

    /// Width of a string in cells, with one blank column between glyphs.
    public static func cells(_ s: String) -> Int { max(0, s.count * (width + 1) - 1) }

    static let table: [Character: [String]] = [
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
        " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
        ".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
        ",": [".....", ".....", ".....", ".....", ".##..", "..#..", ".#..."],
        ":": [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."],
        "!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
        "?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
        "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
        "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
        "/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
        "%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
        "(": ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."],
        ")": [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."],
        "'": ["..#..", "..#..", ".....", ".....", ".....", ".....", "....."],
        "=": [".....", ".....", "#####", ".....", "#####", ".....", "....."],
        "*": [".....", "#.#.#", ".###.", "#####", ".###.", "#.#.#", "....."],
        "#": [".#.#.", "#####", ".#.#.", ".#.#.", ".#.#.", "#####", ".#.#."],
        "<": ["...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#."],
        ">": [".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#..."],
    ]
}
