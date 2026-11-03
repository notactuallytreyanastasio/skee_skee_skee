import SwiftUI

/// The trailer's type and backdrop, in the game's own ink. Only `skee film`
/// uses these; they live here because `CelText` and `Ink` do.
public struct FilmCaption: View {
    let lines: [String], sub: String, size: CGFloat
    public init(text: String, sub: String, size: CGFloat) {
        lines = text.split(separator: "\n").map(String.init)
        self.sub = sub; self.size = size
    }
    public var body: some View {
        VStack(spacing: size * 0.22) {
            VStack(spacing: -size * 0.08) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                    CelText(text: l, size: size * 1.25, fill: [Ink.butter, Ink.pink, Ink.sky][i % 3])
                }
            }
            if !sub.isEmpty { CelText(text: sub, size: size * 0.4) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Rays from the bottom, an arcade carpet at closing time.
public struct FilmBackdrop: View {
    public init() {}
    public var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0x1B1340), Ink.violet.opacity(0.9)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let o = CGPoint(x: size.width / 2, y: size.height * 1.1), r = size.width + size.height
            for i in stride(from: 0, to: 24, by: 2) {
                let a = Double(i) / 24 * 2 * .pi, b = Double(i + 1) / 24 * 2 * .pi
                var p = Path(); p.move(to: o)
                p.addLine(to: CGPoint(x: o.x + cos(a) * r, y: o.y + sin(a) * r))
                p.addLine(to: CGPoint(x: o.x + cos(b) * r, y: o.y + sin(b) * r))
                ctx.fill(p, with: .color(Ink.cream.opacity(0.04)))
            }
        }
    }
}

public struct FilmCard: View {
    public let line: String, sub: String
    public init(line: String, sub: String) { self.line = line; self.sub = sub }
    public var body: some View {
        ZStack {
            FilmBackdrop()
            VStack(spacing: 26) {
                if line == "SKEE SKEE SKEE" {
                    VStack(spacing: -24) {
                        CelText(text: "SKEE", size: 170, fill: Ink.butter)
                        CelText(text: "SKEE", size: 170, fill: Ink.pink)
                        CelText(text: "SKEE", size: 170, fill: Ink.sky)
                    }
                    .rotationEffect(.degrees(-6))
                } else {
                    CelText(text: line, size: 74, fill: Ink.butter)
                }
                if !sub.isEmpty { CelText(text: sub, size: 38) }
            }
        }
    }
}
