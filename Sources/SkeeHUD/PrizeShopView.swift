import SkeeCore
import SkeeScene
import SwiftUI

/// The prize shop: winnings from finished runs buy prizes for a shelf.
/// Nothing here reaches a run; it is the wall of plushies behind an arcade
/// counter. Prizes you can't afford yet show as silhouettes with a price.
struct PrizeShopView: View {
    let wallet: Wallet
    let buy: (Prize) -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            Ink.violet.ignoresSafeArea()
            StripeBackdrop().ignoresSafeArea()
            VStack(spacing: 10) {
                CelText(text: "PRIZE SHOP", size: 32, fill: Ink.butter)
                CelText(text: wallet.room.name.uppercased(), size: 13)
                Pill(fill: Ink.butter) {
                    HStack(spacing: 6) {
                        StarShape().fill(Ink.cream).overlay(StarShape().stroke(Ink.ink, lineWidth: 2)).frame(width: 20, height: 20)
                        CelText(text: "\(wallet.balance) WINNINGS", size: 18)
                    }
                }
                CelText(text: "just for show · prizes never change a run", size: 11)
                // A fixed grid, three to a shelf: ten prizes fit on the
                // folded screen without scrolling.
                let shelf = wallet.room.prizes
                let rows = stride(from: 0, to: shelf.count, by: 3).map { Array(shelf[$0..<min($0 + 3, shelf.count)]) }
                VStack(spacing: 8) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 8) {
                            ForEach(rows[r], id: \.self) { p in card(p) }
                            ForEach(0..<(3 - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                        }
                    }
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 0)
                Button(action: close) {
                    Pill(fill: Ink.mint, radius: 18) { CelText(text: "BACK", size: 22) }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
            .padding(.top, 28)
        }
    }

    func card(_ p: Prize) -> some View {
        let owned = wallet.owned.contains(p)
        let affordable = wallet.balance >= p.price
        return Button { if !owned { buy(p) } } label: {
            VStack(spacing: 4) {
                Image(decorative: Textures.prize(p, owned: owned || affordable), scale: 2)
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(height: 52)
                    .opacity(owned || affordable ? 1 : 0.7)
                CelText(text: p.name, size: 11)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if owned {
                    CelText(text: "ON SHELF", size: 12, fill: Ink.mint)
                } else {
                    CelText(text: "\(p.price)", size: 16, fill: affordable ? Ink.butter : Ink.cream.opacity(0.6))
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Ink.ink).offset(y: 3)
                    RoundedRectangle(cornerRadius: 14).fill(owned ? Ink.violet : Ink.lilac)
                    RoundedRectangle(cornerRadius: 14).strokeBorder(owned ? Ink.butter : Ink.ink, lineWidth: 3)
                }
            }
        }
        .buttonStyle(.plain)
        // Not .disabled: SwiftUI would grey out the prizes you own, the ones
        // that should look best. The action already ignores them.
    }
}

/// The shelf: everything bought so far, in a row.
struct PrizeShelfStrip: View {
    let owned: [Prize]
    var body: some View {
        if !owned.isEmpty {
            HStack(spacing: 2) {
                ForEach(owned, id: \.self) { p in
                    Image(decorative: Textures.prize(p), scale: 2).resizable().aspectRatio(contentMode: .fit).frame(width: 30, height: 30)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Ink.ink.opacity(0.45)))
        }
    }
}

/// Diagonal candy stripes, faint, like a prize booth's wallpaper.
struct StripeBackdrop: View {
    var body: some View {
        Canvas { c, size in
            var x = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                c.stroke(p, with: .color(Ink.lilac.opacity(0.35)), lineWidth: 18)
                x += 48
            }
        }
    }
}

struct StarShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double(i) * .pi / 5
            let rad = (i % 2 == 0 ? 0.5 : 0.22) * min(r.width, r.height)
            let q = CGPoint(x: r.midX + rad * cos(a), y: r.midY + rad * sin(a))
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }
}

/// The walkthrough's coach: what to do now, in a sentence or two. Only its
/// buttons take touches, so a flick that starts under it still throws.
struct CoachView: View {
    let card: CoachCard
    let skip: () -> Void
    let gotIt: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CelText(text: card.title, size: 20, fill: Ink.butter)
                Spacer()
                Button(action: skip) {
                    CelText(text: "SKIP", size: 13)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Ink.ink.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
            Text(card.body)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.cream)
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)
            if card.needsTap {
                Button(action: gotIt) {
                    Pill(fill: Ink.mint, radius: 16) { CelText(text: "GOT IT", size: 18) }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Ink.ink).offset(y: 4)
                RoundedRectangle(cornerRadius: 16).fill(Ink.violet.opacity(0.94))
                RoundedRectangle(cornerRadius: 16).strokeBorder(Ink.butter, lineWidth: 3)
            }
            .allowsHitTesting(false)
        }
    }
}
