import SkeeCore
import SwiftUI

/// What the host's table shows: the conversation, the offer, the host's
/// patience, and whether a reply is on its way.
public struct HostState: Sendable {
    public var haggle: Haggle
    public var thinking: Bool
    public var error: String?
    public init(haggle: Haggle, thinking: Bool, error: String?) {
        self.haggle = haggle; self.thinking = thinking; self.error = error
    }
}

/// The host's table: talk them up, then shake on it. The room is yours
/// whatever happens; the perks are what you haggle over.
struct HostView: View {
    let host: HostState
    let say: (String) -> Void
    let retry: () -> Void
    let deal: () -> Void
    let close: () -> Void
    @State private var draft = ""

    var h: Haggle { host.haggle }

    var body: some View {
        ZStack {
            Ink.violet.ignoresSafeArea()
            StripeBackdrop().ignoresSafeArea()
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    CelText(text: h.host.name.uppercased(), size: 26, fill: Ink.butter)
                    CelText(text: "your host · \(h.room.name)", size: 12)
                }
                offerCard
                transcript
                if h.status == .open { controls } else { ending }
            }
            .padding(.horizontal, 14)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
    }

    var offerCard: some View {
        VStack(spacing: 4) {
            HStack(spacing: 14) {
                term("\(h.offer.nights)", h.offer.nights == 1 ? "NIGHT" : "NIGHTS")
                term("+\(h.offer.tickets)", "TIX / NIGHT")
                term("\(h.offer.credit)", "CREDIT")
            }
            HStack(spacing: 4) {
                CelText(text: "PATIENCE", size: 10)
                ForEach(0..<Haggle.maxPatience, id: \.self) { i in
                    Circle().fill(i < h.patience ? Ink.mult : Ink.ink.opacity(0.4))
                        .overlay(Circle().strokeBorder(Ink.ink, lineWidth: 1.5)).frame(width: 12, height: 12)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.ink.opacity(0.5)))
    }

    func term(_ value: String, _ label: String) -> some View {
        VStack(spacing: -2) {
            CelText(text: value, size: 26, fill: Ink.butter)
            CelText(text: label, size: 10)
        }
    }

    /// Newest at the bottom; older lines slide off the top. Not a
    /// ScrollView: a haggle is a handful of lines, and ImageRenderer (the
    /// CLI's screenshots) drops ScrollView contents.
    var transcript: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            ForEach(Array(h.lines.enumerated()), id: \.offset) { _, line in bubble(line) }
            if host.thinking {
                Text("\(h.host.name) is thinking…").font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.cream.opacity(0.8))
            }
            if let e = host.error {
                VStack(alignment: .leading, spacing: 4) {
                    Text(e).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Ink.butter)
                    if h.lines.last?.speaker == .player {
                        Button(action: retry) { Pill(fill: Ink.sky, radius: 12) { CelText(text: "ASK AGAIN", size: 14) } }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .clipped()
        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.ink.opacity(0.35)))
    }

    func bubble(_ line: HaggleLine) -> some View {
        let mine = line.speaker == .player
        return HStack {
            if mine { Spacer(minLength: 40) }
            Text(line.text)
                .font(.system(size: 15, weight: line.speaker == .stage ? .heavy : .bold, design: .rounded))
                .italic(line.speaker == .stage)
                .foregroundStyle(mine ? Ink.ink : Ink.cream)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14).fill(mine ? Ink.butter : (line.speaker == .stage ? Ink.mult : Ink.lilac)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.ink, lineWidth: 2))
            if !mine { Spacer(minLength: 40) }
        }
    }

    /// Type anything; or use a nudge; or shake on what's on the table.
    var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(["One more night?", "Tickets would help.", "Some credit?"], id: \.self) { s in
                    Button { say(s) } label: {
                        Text(s).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Ink.cream)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Capsule().fill(Ink.ink.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .disabled(host.thinking)
            HStack(spacing: 6) {
                TextField("Make your case…", text: $draft)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Ink.cream))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.ink, lineWidth: 2))
                    .submitLabel(.send)
                    .onSubmit(send)
                Button(action: send) { Pill(fill: Ink.sky, radius: 12) { CelText(text: "SAY", size: 16) } }
                    .buttonStyle(.plain)
            }
            .disabled(host.thinking)
            Button(action: deal) {
                Pill(fill: Ink.mint, radius: 18) { CelText(text: "DEAL", size: 24) }
            }
            .buttonStyle(.plain)
            .disabled(host.thinking)
        }
    }

    func send() {
        let t = draft
        draft = ""
        say(t)
    }

    var ending: some View {
        VStack(spacing: 8) {
            CelText(text: h.status == .signed ? "DEAL!" : "\(h.host.name.uppercased()) LEFT", size: 26,
                    fill: h.status == .signed ? Ink.mint : Ink.mult)
            let f = h.final
            CelText(text: "\(h.room.name) is yours · \(f.nights) night\(f.nights == 1 ? "" : "s") · +\(f.tickets) tix · \(f.credit) credit", size: 13)
            Button(action: close) { Pill(fill: Ink.mint, radius: 18) { CelText(text: "CHECK IN", size: 24) } }
                .buttonStyle(.plain)
        }
    }
}

/// The rooms on the title: yours to pick, the next one with what it takes.
struct RoomPicker: View {
    let wallet: Wallet
    let pick: (Room) -> Void
    let host: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Room.allCases, id: \.self) { r in
                    let owned = wallet.rooms.contains(r)
                    Button { if owned { pick(r) } } label: {
                        VStack(spacing: 0) {
                            CelText(text: short(r), size: 12, fill: r == wallet.room ? Ink.butter : Ink.cream)
                            CelText(text: owned ? (wallet.comps[r].map { "\($0.nights) COMP" } ?? "OPEN") : "\(r.compThreshold)",
                                    size: 9, fill: owned ? Ink.mint : Ink.cream.opacity(0.6))
                        }
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 10).fill(r == wallet.room ? Ink.pink : Ink.ink.opacity(owned ? 0.55 : 0.3)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(r == wallet.room ? Ink.butter : .clear, lineWidth: 2))
                        .opacity(owned ? 1 : 0.6)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let due = wallet.hostDue {
                Button(action: host) {
                    Pill(fill: Ink.butter, radius: 16) {
                        VStack(spacing: -2) {
                            CelText(text: "THE HOST WANTS A WORD", size: 17)
                            CelText(text: "a comped stay in \(due.name)", size: 11, fill: Ink.violet)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    func short(_ r: Room) -> String {
        switch r {
        case .boardwalk: "BOARDWALK"
        case .neonLounge: "NEON"
        case .highRoller: "HIGH ROLLER"
        case .penthouse: "PENTHOUSE"
        }
    }
}
