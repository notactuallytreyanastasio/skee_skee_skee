import SkeeCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// What the host's table shows: the conversation, the offer, the host's
/// patience, and whether a reply is on its way.
public struct HostState: Sendable {
    public var haggle: Haggle
    public var thinking: Bool
    /// Lay out as if a keyboard this tall were up, for the CLI's screenshots.
    public var keyboard: CGFloat = 0
    /// Nil when this build has no live host. False asks for permission
    /// before anything typed leaves the phone; see `consentCard`.
    public var aiChat: Bool?
    public var asking = false
    /// The model is writing the hello, so the stock one stays hidden.
    public var greeting = false
    public init(haggle: Haggle, thinking: Bool) {
        self.haggle = haggle; self.thinking = thinking
    }
}

/// The host's table: talk them up, then shake on it. The room is yours
/// whatever happens; the perks are what you haggle over.
struct HostView: View {
    let host: HostState
    let say: (String) -> Void
    let deal: () -> Void
    let close: () -> Void
    let consent: (Bool) -> Void
    let reconsider: () -> Void
    @State private var draft = ""
    @State private var keyboardUp: CGFloat = 0
    @FocusState private var writing: Bool

    var h: Haggle { host.haggle }
    var keyboard: CGFloat { max(keyboardUp, host.keyboard) }
    /// The app ignores the keyboard so the cabinet never resizes, so this
    /// screen has to get out of its way. With half the screen gone, only
    /// what the host said and the box to answer in stay.
    var typing: Bool { keyboard > 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Ink.violet.ignoresSafeArea()
                StripeBackdrop().ignoresSafeArea()
                VStack(spacing: 10) {
                    if !typing {
                        VStack(spacing: 0) {
                            CelText(text: h.host.name.uppercased(), size: 26, fill: Ink.butter)
                            if let on = host.aiChat {
                                Button(action: reconsider) {
                                    CelText(text: on ? "AI CHAT IS ON · TAP TO CHANGE" : "AI CHAT IS OFF · TAP TO CHANGE", size: 10, fill: Ink.sky)
                                }
                                .buttonStyle(.plain)
                            }
                            CelText(text: h.visit == .arrival ? "your first loadout" : "your host · \(h.room.name)", size: 14)
                        }
                        offerCard
                    }
                    transcript
                    if h.status == .open { controls } else { ending }
                }
                .padding(.horizontal, 14)
                .padding(.top, 26)
                .padding(.bottom, typing ? keyboard + 8 : 20)
                if host.asking { consentCard }
            }
            .onKeyboard { top, seconds in
                let covered = max(0, geo.frame(in: .global).maxY - top)
                withAnimation(.easeOut(duration: seconds)) { keyboardUp = covered }
            }
        }
    }

    /// Apple asks for this before anything typed goes to an outside AI, and
    /// it has to say where it goes. The privacy policy names the provider.
    var consentCard: some View {
        ZStack {
            Ink.ink.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 12) {
                CelText(text: "TALK TO AN AI HOST?", size: 22, fill: Ink.butter)
                Text("\(h.host.name) can be played by an AI. If you say yes, what you type at this table goes through our server to a third-party AI model, which writes the replies. Your name and contacts are not sent, and we don't keep your chats. Please don't type anything private.")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.cream)
                    .fixedSize(horizontal: false, vertical: true)
                Button { consent(true) } label: {
                    Pill(fill: Ink.mint, radius: 16) { CelText(text: "YES, USE THE AI", size: 18) }
                }
                .buttonStyle(.plain)
                Button { consent(false) } label: {
                    Pill(fill: Ink.sky, radius: 16) { CelText(text: "NO, KEEP IT ON MY PHONE", size: 15) }
                }
                .buttonStyle(.plain)
                Text("With no, \(h.host.name) sticks to simpler replies. You can change this at the top of this screen.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Ink.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Ink.violet))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Ink.ink, lineWidth: 3))
            .padding(20)
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
            CelText(text: "a night = one game with bonus tickets · credit buys prizes", size: 11)
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
            ForEach(Array(h.lines.enumerated()).dropFirst(host.greeting ? 1 : 0), id: \.offset) { _, line in bubble(line) }
            if host.thinking {
                Text("\(h.host.name) is thinking…").font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.cream.opacity(0.8))
            }
        }
        .padding(10)
        // minHeight 0: without it the bubbles' fixed height sets a floor, and
        // a long chat pushes DEAL off the bottom of the outer display.
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .bottom)
        .clipped()
        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.ink.opacity(0.35)))
        .contentShape(Rectangle())
        .onTapGesture { writing = false }
    }

    func bubble(_ line: HaggleLine) -> some View {
        let mine = line.speaker == .player
        return HStack {
            if mine { Spacer(minLength: 40) }
            Text(line.text)
                .font(.system(size: 15, weight: line.speaker == .stage ? .heavy : .bold, design: .rounded))
                .italic(line.speaker == .stage)
                // Short of room, lose the oldest line off the top, not the
                // end of the sentence being answered.
                .fixedSize(horizontal: false, vertical: true)
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
            if !typing {
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
            }
            HStack(spacing: 6) {
                TextField("Make your case…", text: $draft)
                    .onChange(of: draft) { _, text in
                        if text.count > HostGuard.maxLine { draft = String(text.prefix(HostGuard.maxLine)) }
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Ink.cream))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.ink, lineWidth: 2))
                    .submitLabel(.send)
                    .focused($writing)
                    .onSubmit(send)
                Button(action: send) { Pill(fill: Ink.sky, radius: 12) { CelText(text: "SAY", size: 16) } }
                    .buttonStyle(.plain)
                if typing {
                    Button(action: deal) { Pill(fill: Ink.mint, radius: 12) { CelText(text: "DEAL", size: 16) } }
                        .buttonStyle(.plain)
                }
            }
            .disabled(host.thinking)
            if !typing {
                Button(action: deal) {
                    Pill(fill: Ink.mint, radius: 18) { CelText(text: "DEAL", size: 24) }
                }
                .buttonStyle(.plain)
                .disabled(host.thinking)
            }
        }
    }

    /// Sending puts the keyboard away, so the reply and DEAL are both there.
    func send() {
        let t = draft
        draft = ""
        writing = false
        say(t)
    }

    var ending: some View {
        VStack(spacing: 8) {
            CelText(text: h.status == .signed ? "DEAL!" : "\(h.host.name.uppercased()) LEFT", size: 26,
                    fill: h.status == .signed ? Ink.mint : Ink.mult)
            let f = h.final
            let terms = "\(f.nights) night\(f.nights == 1 ? "" : "s") · +\(f.tickets) tix · \(f.credit) credit"
            CelText(text: h.visit == .arrival ? "you start with \(terms)" : "\(h.room.name) is yours · \(terms)", size: 14)
            Button(action: close) {
                Pill(fill: Ink.mint, radius: 18) { CelText(text: h.visit == .arrival ? "LEARN TO PLAY" : "CHECK IN", size: 24) }
            }
            .buttonStyle(.plain)
        }
    }
}

private extension View {
    /// Calls back with the keyboard's top edge in screen points as it moves,
    /// and how long the move takes.
    @ViewBuilder func onKeyboard(_ moved: @escaping (CGFloat, Double) -> Void) -> some View {
        #if canImport(UIKit)
        onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            moved(end.minY, note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25)
        }
        // Gone is gone, wherever the last frame said it was: a stale height
        // here would leave the screen stuck in its typing layout.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            moved(.greatestFiniteMagnitude, note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25)
        }
        #else
        self
        #endif
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
