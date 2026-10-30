import SkeeCore
import SkeeRender
import SwiftUI

/// The prize counter: slides up over the lane half, leaving the board in
/// view above the crease so stamps and gilds can be aimed by tapping a hole.
struct CounterView: View {
    let state: HUDState
    let counter: PrizeCounter
    let actions: HUDActions

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28).fill(Ink.ink).offset(y: 5)
            RoundedRectangle(cornerRadius: 28).fill(Ink.lilac)
            RoundedRectangle(cornerRadius: 28).strokeBorder(Ink.ink, lineWidth: 4)
            VStack(spacing: 10) {
                HStack {
                    CelText(text: "PRIZE COUNTER", size: 24, fill: Ink.butter)
                    Spacer()
                    Pill(fill: Ink.butter) {
                        HStack(spacing: 6) {
                            TicketShape().fill(Ink.pink).overlay(TicketShape().stroke(Ink.ink, lineWidth: 2)).frame(width: 22, height: 14)
                            CelText(text: "\(state.tickets)", size: 20)
                        }
                    }
                }
                if state.selectedOffer != nil {
                    CelText(text: "tap a hole on the board  ↑", size: 16, fill: Ink.butter)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(counter.offers.enumerated()), id: \.offset) { i, offer in
                        OfferCard(offer: offer, affordable: (offer?.cost ?? 0) <= state.tickets, selected: state.selectedOffer == i)
                            .onTapGesture {
                                guard let offer else { return }
                                if offer.needsTarget { actions.selectOffer(state.selectedOffer == i ? nil : i) } else { actions.buy(i) }
                            }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    Button(action: actions.reroll) {
                        Pill(fill: Ink.sky, radius: 18) { CelText(text: "REROLL \(counter.rerollCost)", size: 20).frame(maxWidth: .infinity) }
                    }
                    Button(action: actions.leave) {
                        Pill(fill: Ink.mint, radius: 18) { CelText(text: "NEXT ROUND", size: 20).frame(maxWidth: .infinity) }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .padding(.top, 18)
    }
}

struct OfferCard: View {
    let offer: Offer?
    let affordable: Bool
    let selected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Ink.ink).offset(y: 4)
            RoundedRectangle(cornerRadius: 16).fill(offer == nil ? Ink.cream.opacity(0.4) : Ink.cream)
            RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Ink.mult : Ink.ink, lineWidth: selected ? 5 : 3)
            if let offer {
                HStack(spacing: 8) {
                    icon(offer).frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(offer)).font(.system(size: 15, weight: .black, design: .rounded)).foregroundStyle(Ink.ink)
                        Text(blurb(offer)).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Ink.ink.opacity(0.8))
                            .lineLimit(3).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        CelText(text: "\(offer.cost) TIX", size: 14, fill: affordable ? Ink.butter : Ink.mult)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
            } else {
                CelText(text: "SOLD", size: 22, fill: Ink.cream)
            }
        }
        .frame(height: 104)
        .opacity(offer != nil && !affordable ? 0.6 : 1)
    }

    @ViewBuilder func icon(_ o: Offer) -> some View {
        switch o {
        case .charm(let c): CharmToken(charm: c)
        case .stamp(let s): SymbolImage(symbol: s)
        case .gild: ZStack { Circle().fill(Ink.butter).overlay(Circle().stroke(Ink.ink, lineWidth: 3)); CelText(text: "+10", size: 14) }
        case .purge: ZStack { Circle().fill(Ink.pink).overlay(Circle().stroke(Ink.ink, lineWidth: 3)); CelText(text: "×", size: 26) }
        case .powerUp(let p): PowerToken(power: p, armed: false)
        }
    }

    func title(_ o: Offer) -> String {
        switch o {
        case .charm(let c): c.name
        case .stamp(let s): "\(s.rawValue.capitalized) stamp"
        case .gild: "Gild"
        case .purge: "Purge"
        case .powerUp(let p): p.name
        }
    }

    func blurb(_ o: Offer) -> String {
        switch o {
        case .charm(let c): c.blurb
        case .stamp(let s): "Add a \(s.rawValue) to a hole's reel"
        case .gild: "+\(Offer.gildAmount) chips on a hole, for good"
        case .purge: "Take the showing symbol off a hole's reel"
        case .powerUp(let p): p.blurb
        }
    }
}
