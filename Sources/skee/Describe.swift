import Foundation
import SkeeCore

// Text renderings of core values. Shared by every command.

func f2(_ x: Double) -> String { String(format: "%.2f", x) }

func holeGlyph(_ h: Hole) -> Character {
    switch h {
    case .gutter: "."
    case .ring10: "1"
    case .ring20: "2"
    case .ring30: "3"
    case .ring40: "4"
    case .ring50: "5"
    case .pocketLeft: "L"
    case .pocketRight: "R"
    }
}

func describe(_ e: ShotEvent) -> String {
    switch e {
    case .dud: "stalled before the hinge"
    case .rail: "rail"
    case .launched: "over the hinge"
    case .landed: "landed"
    case .lip(let r): "rattled on the \(["40", "30", "20", "10"][r]) lip"
    case .backwall: "backwall"
    case .hop: "hopped"
    case .dropped(let h): "dropped into \(h.faceValue)"
    case .settled(let h): "settled in \(h.faceValue)"
    case .gutter: "gutter"
    }
}

func describe(_ r: ShotResult) -> String {
    var events: [String] = []
    for e in r.events.map(describe) where events.last != e { events.append(e) }
    let speed = r.hingeSpeed.map { "hinge \(f2($0)) m/s" } ?? "dud"
    let land = r.firstLanding.map { "first contact (\(f2($0.x)), \(f2($0.y)))" } ?? ""
    return "\(r.hole.faceValue) [\(r.hole.rawValue)]  \(speed)  peak \(f2(r.peakHeight)) m  \(land)\n  " +
        events.joined(separator: " -> ")
}

func describe(_ f: FrameScore) -> String {
    let holes = f.balls.map { "\($0.hole.faceValue)/\($0.symbol.rawValue)" }.joined(separator: "  ")
    var line = "frame: \(holes)  ->  \(f.chips) chips x \(f2(f.mult)) mult = \(f.total)"
    switch f.payline {
    case .none: break
    case .pair(let s): line += "   pair of \(s.rawValue)"
    case .triple(let s): line += "   THREE \(s.rawValue.uppercased())" + (f.isJackpot ? "  JACKPOT" : "")
    }
    let charmNotes = f.steps.compactMap { step -> String? in
        guard case .charm(let c) = step.source else { return nil }
        switch step.effect {
        case .chips(let n): return "\(c.name) +\(n) chips"
        case .mult(let m): return "\(c.name) +\(f2(m)) mult"
        case .timesMult(let x): return "\(c.name) x\(f2(x)) mult"
        case .tickets(let t): return "\(c.name) +\(t) tickets"
        case .note(let n): return "\(c.name): \(n)"
        case .base: return nil
        }
    }
    if !charmNotes.isEmpty { line += "\n    " + charmNotes.joined(separator: ", ") }
    if f.steps.contains(where: { $0.source == .fever }) { line += "\n    FEVER x2" }
    return line
}

func describe(_ e: GameEvent) -> String? {
    switch e {
    case .shot(let r, let b): "ball: \(describe(r))\n  -> \(b.chips) chips, \(b.symbol.rawValue)"
    case .fouled: "FOUL: thumb past the crease. Ball spent."
    case .pulled(let p): describe(p)
    case .freeGamesWon(let n): "BONUS x3: \(n) FREE GAMES, every one scores x2."
    case .jackpot(let t): "*** \(t.title) JACKPOT *** paid to winnings."
    case .frameScored(let f): describe(f)
    case .feverLit: "The jackpot meter is full: next frame plays at FEVER (x2)."
    case .roundCleared(let s, let t, let p):
        "ROUND CLEARED \(s)/\(t). Tickets +\(p.total) (base \(p.base), overkill \(p.overkill), interest \(p.interest))"
    case .roundFailed(let s, let t): "ROUND FAILED \(s)/\(t). Run over."
    case .counterOpened: "The prize counter opens."
    case .bought(let o): "bought \(describe(o))"
    case .sold(let c): "sold \(c.name)"
    case .rerolled: "rerolled the counter"
    case .armed(let p): "armed \(p.name)"
    case .ballChosen(let k): "picked the \(k.name)"
    case .roundStarted(let k, let t): "\(k.title): reach \(t)"
    case .anteStarted(let a, let b): "=== ANTE \(a) === boss: \(b.name) — \(b.blurb)"
    case .runWon: "YOU BEAT THE ARCADE."
    }
}

func describe(_ p: Pull) -> String {
    var out = [p.free ? "FREE GAME pull:" : "pull, \(p.bet.lines) line\(p.bet.lines > 1 ? "s" : "") (\(p.bet.cost)t):"]
    for row in p.grid { out.append("  | " + row.map { $0.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0) }.joined(separator: " | ") + " |") }
    for w in p.lineWins { out.append("  line \(w.line + 1): three \(w.symbol.rawValue)\(w.multiplier > 1 ? " x\(w.multiplier)" : "") -> +\(w.chips) chips this frame") }
    out.append("  targets: " + p.targets.map(\.rawValue).joined(separator: " "))
    return out.joined(separator: "\n")
}

func describe(_ o: Offer) -> String {
    switch o {
    case .charm(let c): "\(c.name) (charm, \(c.cost)t): \(c.blurb)"
    case .stamp(let s): "\(s.rawValue) stamp (\(o.cost)t): put a \(s.rawValue) on a hole"
    case .gild: "Gild (\(o.cost)t): +\(Offer.gildAmount) chips on a hole"
    case .purge: "Purge (\(o.cost)t): remove the showing symbol from a hole's reel"
    case .powerUp(let p): "\(p.name) (\(p.cost)t): \(p.blurb)"
    }
}

func describe(_ s: RunState) -> String {
    var out: [String] = []
    out.append("Ante \(s.ante)/\(s.config.antes)  \(s.round.kind.title)  boss this ante: \(s.boss.name) — \(s.boss.blurb)")
    out.append("Score \(s.round.score) / \(s.round.target)   frame \(min(s.round.frames.count + 1, s.round.framesTotal))/\(s.round.framesTotal)   balls left \(s.round.ballsLeft)")
    out.append("Tickets \(s.tickets)   heat \(s.heat)/\(s.config.feverHeat)\(s.fever ? "  FEVER NEXT FRAME" : "")")
    if !s.round.currentBalls.isEmpty {
        out.append("This frame: " + s.round.currentBalls.map { "\($0.hole.faceValue)/\($0.symbol.rawValue)" }.joined(separator: " "))
    }
    out.append("Charms: " + (s.charms.isEmpty ? "none" : s.charms.enumerated().map { "[\($0)] \($1.name)" }.joined(separator: ", ")))
    out.append("Specialty balls: " + (s.powerUps.isEmpty ? "none" : s.powerUps.enumerated().map { "[\($0)] \($1.name)" }.joined(separator: ", ")) + (s.round.armed.map { "  armed: \($0.name)" } ?? ""))
    let board = Hole.allCases.filter { $0 != .gutter }.map { h in
        "\(h.faceValue)\(h.isPocket ? (h == .pocketLeft ? "L" : "R") : "")=\(s.showing(h).rawValue)\(s.setup.reel(h).count > 1 ? "(" + s.setup.reel(h).map { String($0.rawValue.prefix(2)) }.joined(separator: ",") + ")" : "")\(s.setup.gild[h].map { "+\($0)" } ?? "")"
    }
    out.append("Board: " + board.joined(separator: " "))
    switch s.phase {
    case .throwing where s.round.pull == nil: out.append("Phase: PULL THE LEVER (skee play <save> pull 1|3|5)")
    case .throwing: out.append("Phase: throwing   targets: " + s.topSlot.symbols.map(\.rawValue).joined(separator: " ") + (s.round.freeLeft > 0 ? "   free games left \(s.round.freeLeft)" : ""))
    case .lost: out.append("Phase: LOST")
    case .won: out.append("Phase: WON")
    case .prizeCounter(let c):
        out.append("Phase: PRIZE COUNTER (reroll \(c.rerollCost)t)")
        for (i, o) in c.offers.enumerated() {
            out.append("  [\(i)] " + (o.map(describe) ?? "sold"))
        }
    }
    return out.joined(separator: "\n")
}
