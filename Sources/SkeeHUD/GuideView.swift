import SkeeCore
import SwiftUI

/// The Guide: pick a topic, read it a page at a time. Pages rather than a
/// scroll, so the type can be big and there's always a NEXT to tap.
struct GuideView: View {
    let topics: [GuideTopic]
    let start: Int?
    let replay: () -> Void
    let close: () -> Void
    @State private var topic: Int?
    @State private var page = 0

    init(topics: [GuideTopic], start: Int? = nil, replay: @escaping () -> Void, close: @escaping () -> Void) {
        self.topics = topics; self.start = start; self.replay = replay; self.close = close
        _topic = State(initialValue: start)
    }

    var body: some View {
        ZStack {
            Ink.violet.ignoresSafeArea()
            StripeBackdrop().ignoresSafeArea()
            if let t = topic { reader(topics[t]) } else { contents }
        }
    }

    var contents: some View {
        VStack(spacing: 10) {
            CelText(text: "THE GUIDE", size: 34, fill: Ink.butter)
            CelText(text: topics.count < Guide.all.count ? "more appears here as you play" : "everything you've met so far", size: 15)
            let rows = stride(from: 0, to: topics.count, by: 2).map { $0 }
            VStack(spacing: 6) {
                ForEach(rows, id: \.self) { i in
                    HStack(spacing: 6) {
                        topicButton(i)
                        if i + 1 < topics.count { topicButton(i + 1) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 44) }
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: replay) {
                Pill(fill: Ink.sky, radius: 16) { CelText(text: "PLAY THE FIRST LOADOUT AGAIN", size: 16) }
            }
            .buttonStyle(.plain)
            Button(action: close) {
                Pill(fill: Ink.mint, radius: 18) { CelText(text: "DONE", size: 24) }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.top, 30).padding(.bottom, 20)
    }

    func topicButton(_ i: Int) -> some View {
        Button { topic = i; page = 0 } label: {
            Text(topics[i].title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Ink.cream)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Ink.ink.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    func reader(_ t: GuideTopic) -> some View {
        VStack(spacing: 14) {
            CelText(text: t.title.uppercased(), size: 28, fill: Ink.butter)
                .multilineTextAlignment(.center)
            Text(t.pages[page])
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.cream)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Ink.ink.opacity(0.45)))
            if t.pages.count > 1 {
                CelText(text: "PAGE \(page + 1) OF \(t.pages.count)", size: 14)
            }
            HStack(spacing: 10) {
                Button { if page > 0 { page -= 1 } else { topic = nil } } label: {
                    Pill(fill: Ink.sky, radius: 18) { CelText(text: "BACK", size: 22) }
                }
                .buttonStyle(.plain)
                Button { if page + 1 < t.pages.count { page += 1 } else { topic = nil } } label: {
                    Pill(fill: Ink.mint, radius: 18) { CelText(text: page + 1 < t.pages.count ? "NEXT" : "DONE", size: 22) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.top, 30).padding(.bottom, 20)
    }
}

/// The door of the casino: Sal, one line at a time, at the reader's pace.
struct ArrivalView: View {
    let beat: Int
    let next: () -> Void

    var body: some View {
        ZStack {
            Ink.violet.ignoresSafeArea()
            StripeBackdrop().ignoresSafeArea()
            VStack(spacing: 18) {
                VStack(spacing: -8) {
                    CelText(text: "WELCOME TO", size: 26, fill: Ink.cream)
                    CelText(text: "SKEE SKEE SKEE", size: 42, fill: Ink.butter)
                }
                .rotationEffect(.degrees(-3))
                .padding(.top, 60)
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    CelText(text: "SAL", size: 26, fill: Ink.butter)
                    Text(Arrival.beats[beat])
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Ink.cream)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 18).fill(Ink.lilac))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Ink.ink, lineWidth: 3))
                .id(beat)
                .transition(.opacity)
                Spacer()
                Button(action: next) {
                    Pill(fill: Ink.mint, radius: 22) {
                        CelText(text: beat + 1 < Arrival.beats.count ? "GO ON" : "LET'S TALK", size: 28)
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 18)
            .animation(.easeInOut(duration: 0.45), value: beat)
        }
    }
}
