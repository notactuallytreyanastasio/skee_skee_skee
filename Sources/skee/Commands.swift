import Foundation
import SkeeCore

func shotCommand() {
    let p = positional()
    guard p.count >= 2, let power = Double(p[0]), let aim = Double(p[1]) else { fail("shot <power> <aim>") }
    let l = Launch(power: power, aim: aim, start: Double(flag("start") ?? "0") ?? 0,
                   fold: Double(flag("fold") ?? "0") ?? 0)
    let r = simulateShot(l, on: tableFromFlags())
    print(describe(r))
    if has("trace") {
        for s in r.path {
            print("  t=\(f2(s.t)) \(s.phase.rawValue) x=\(f2(s.x)) along=\(f2(s.along)) h=\(f2(s.height))")
        }
    }
}

func mapCommand() {
    let t = tableFromFlags()
    let steps = Int(flag("steps") ?? "60") ?? 60
    let fold = Double(flag("fold") ?? "0") ?? 0
    let aims = stride(from: -1.0, through: 1.0, by: 0.05).map { $0 }
    print("power \\ aim  -1 " + String(repeating: " ", count: aims.count - 6) + "+1")
    for i in stride(from: steps, through: 0, by: -1) {
        let power = Double(i) / Double(steps)
        let row = aims.map { holeGlyph(simulateShot(Launch(power: power, aim: $0, fold: fold), on: t).hole) }
        print("  \(f2(power))      \(String(row))")
    }
}

func windowsCommand() {
    let book = AimBook(table: tableFromFlags(), fold: Double(flag("fold") ?? "0") ?? 0)
    for hole in Hole.allCases.sorted() {
        guard let w = book.best[hole] else { print("\(hole.rawValue): unreachable"); continue }
        print("\(hole.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) width \(f2(w.width * 100))% of power at power \(f2(w.launch.power)) aim \(f2(w.launch.aim))")
    }
}

// MARK: - play

struct SaveFile: Codable {
    var seed: UInt64
    var actions: [Action]
}

func playCommand() {
    let p = positional()
    guard p.count >= 2 else { fail("play <save.json> <command...>") }
    let url = URL(fileURLWithPath: p[0])
    let cmd = p[1]
    let rest = Array(p.dropFirst(2))

    if cmd == "new" {
        let seed = rest.first.flatMap(UInt64.init) ?? UInt64(Date().timeIntervalSince1970)
        save(SaveFile(seed: seed, actions: []), to: url)
        let s = newRun(seed: seed)
        print("New run, seed \(seed).")
        print(describe(s))
        return
    }
    guard let data = try? Data(contentsOf: url),
          var file = try? JSONDecoder().decode(SaveFile.self, from: data)
    else { fail("no save at \(url.path); start with: skee play \(p[0]) new [seed]") }

    var state = newRun(seed: file.seed)
    for a in file.actions {
        guard case .success(let step) = apply(a, to: state) else { fail("save file does not replay") }
        state = step.state
    }

    func num(_ i: Int) -> Double? { i < rest.count ? Double(rest[i]) : nil }
    let action: Action?
    switch cmd {
    case "show": action = nil
    case "throw":
        guard let power = num(0), let aim = num(1) else { fail("throw <power> <aim> [start] [fold]") }
        var launch = Launch(power: power, aim: aim, start: num(2) ?? 0, fold: num(3) ?? 0)
        if let hand = flag("hand"), let skill = Skill.all.first(where: { $0.name == hand }) {
            // A thumb is not a keyboard: wobble the throw like a player of
            // this skill would. Seeded by position in the run, and the
            // wobbled launch is what gets saved, so replays stay exact.
            var rng = SplitMix64(seed: file.seed &+ UInt64(file.actions.count) &* 7919)
            launch = skill.perturb(launch, rng: &rng)
            print("hand (\(hand)): power \(f2(launch.power)) aim \(f2(launch.aim))")
        }
        action = .throwBall(launch)
    case "arm": action = .arm(Int(rest.first ?? "") ?? -1)
    case "buy":
        let hole = rest.count > 1 ? parseHole(rest[1]) : nil
        action = .buy(Int(rest.first ?? "") ?? -1, target: hole)
    case "reroll": action = .reroll
    case "sell": action = .sell(Int(rest.first ?? "") ?? -1)
    case "leave": action = .leaveCounter
    default: fail("unknown play command \(cmd)")
    }

    if let action {
        switch apply(action, to: state) {
        case .failure(let e):
            print("Rejected: \(e)")
        case .success(let step):
            state = step.state
            file.actions.append(action)
            save(file, to: url)
            for e in step.events { if let d = describe(e) { print(d) } }
            print("")
        }
    }
    print(describe(state))
}

func parseHole(_ s: String) -> Hole? {
    switch s.lowercased() {
    case "10": .ring10
    case "20": .ring20
    case "30": .ring30
    case "40": .ring40
    case "50": .ring50
    case "100l", "l", "left": .pocketLeft
    case "100r", "r", "right": .pocketRight
    default: Hole(rawValue: s)
    }
}

func save(_ f: SaveFile, to url: URL) {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try! enc.encode(f).write(to: url)
}

// MARK: - bots

func skillsFromFlag() -> [Skill] {
    let name = flag("skill") ?? "all"
    if name == "all" { return [.expert, .regular, .novice] }
    guard let s = Skill.all.first(where: { $0.name == name }) else { fail("unknown skill \(name)") }
    return [s]
}

func botCommand() {
    guard let seed = positional().first.flatMap(UInt64.init) else { fail("bot <seed>") }
    let skill = skillsFromFlag().first!
    let run = playBotRun(seed: seed, skill: skill)
    for e in run.events {
        switch e {
        case .shot: continue
        default: if let d = describe(e) { print(d) }
        }
    }
    print("\n" + describe(run.final))
}

func balanceCommand() {
    let runs = Int(flag("runs") ?? "50") ?? 50
    let seed0 = UInt64(flag("seed") ?? "1000") ?? 1000
    var books: [Table: AimBook] = [:]
    for skill in skillsFromFlag() {
        var reached = [Int](repeating: 0, count: 10)
        var wins = 0, balls = 0, rattles = 0, jackpots = 0, frames = 0, pairs = 0, triples = 0
        var holes: [Hole: Int] = [:]
        var margins: [Double] = []
        var anteMargins: [Int: [Double]] = [:]
        var failedAt: [String: Int] = [:]
        var feverFrames = 0
        var ticketsEarned = 0, purchases = 0
        for k in 0..<runs {
            let run = playBotRun(seed: seed0 + UInt64(k), skill: skill, books: &books)
            let s = run.final
            reached[min(s.ante, 9)] += 1
            if s.phase == .won { wins += 1 }
            balls += s.stats.balls; rattles += s.stats.rattles; jackpots += s.stats.jackpots
            for (h, n) in s.stats.holes { holes[h, default: 0] += n }
            for e in run.events {
                switch e {
                case .frameScored(let f):
                    frames += 1
                    if case .pair = f.payline { pairs += 1 }
                    if case .triple = f.payline { triples += 1 }
                    if f.steps.contains(where: { $0.source == .fever }) { feverFrames += 1 }
                    ticketsEarned += f.tickets
                case .roundCleared(let sc, let t, let p):
                    margins.append(Double(sc) / Double(t)); ticketsEarned += p.total
                    anteMargins[anteOf(t), default: []].append(Double(sc) / Double(t))
                case .roundFailed(let sc, let t):
                    margins.append(Double(sc) / Double(t))
                    anteMargins[anteOf(t), default: []].append(Double(sc) / Double(t))
                case .bought: purchases += 1
                default: break
                }
            }
            if s.phase == .lost {
                let where_ = s.round.kind == .boss ? "boss \(s.boss.rawValue)" : s.round.kind.rawValue
                failedAt["ante \(s.ante) \(where_)", default: 0] += 1
            }
        }
        let n = Double(runs)
        print("== \(skill.name) (power sd \(skill.powerSigma), aim sd \(skill.aimSigma)) — \(runs) runs ==")
        print("win rate \(f2(Double(wins) / n * 100))%")
        print("final ante reached: " + (1...8).map { "\($0):\(reached[$0])" }.joined(separator: " "))
        print("deaths: " + failedAt.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
        let tot = Double(max(balls, 1))
        print("holes: " + Hole.allCases.sorted().map { "\($0.faceValue)\($0.isPocket ? ($0 == .pocketLeft ? "L" : "R") : ""):\(f2(Double(holes[$0] ?? 0) / tot * 100))%" }.joined(separator: " "))
        print("rattles/ball \(f2(Double(rattles) / tot))   pairs \(f2(Double(pairs) / Double(max(frames, 1)) * 100))% of frames   triples \(f2(Double(triples) / Double(max(frames, 1)) * 100))%   jackpots/run \(f2(Double(jackpots) / n))   fever frames/run \(f2(Double(feverFrames) / n))")
        let close = margins.filter { $0 >= 0.85 && $0 < 1.15 }.count
        print("round margins: nail-biters (within 15% of target) \(f2(Double(close) / Double(max(margins.count, 1)) * 100))%   median score/target \(f2(margins.sorted()[margins.count / 2]))")
        print("score/target p10/p50/p90 by ante:\n  " + anteMargins.keys.sorted().map { a in
            let m = anteMargins[a]!.sorted()
            return "\(a): \(f2(m[m.count / 10]))/\(f2(m[m.count / 2]))/\(f2(m[m.count * 9 / 10])) n=\(m.count)"
        }.joined(separator: "\n  "))
        print("tickets earned/run \(f2(Double(ticketsEarned) / n))   purchases/run \(f2(Double(purchases) / n))\n")
    }
}

/// Which ante a target belongs to (targets are unique per ante and kind).
func anteOf(_ target: Int) -> Int {
    let c = RunConfig.standard
    for a in 1...c.antes { for k in RoundKind.allCases where c.target(ante: a, kind: k) == target { return a } }
    return 0
}

func settleProbe() {
    let b = BoardSpec.standard
    var n = 0
    for aim in [-0.4, 0, 0.3] { for i in 0...200 {
        let r = simulateShot(Launch(power: Double(i)/200, aim: aim), on: .standard)
        guard r.hole != .gutter, r.events.last != .dropped(r.hole), let last = r.path.last else { continue }
        n += 1
        if n <= 8 {
            let p = Vec2(last.x, last.along - 2.4)
            let h = b.holeCenter(r.hole)
            print(r.hole, "rest", f2(p.x), f2(p.y), "hole", f2(h.x), f2(h.y), "d", String(format: "%.3f", (p - h).length), "t", f2(r.duration), r.events.suffix(2))
        }
    }}
    print("settled:", n)
}
