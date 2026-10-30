import Foundation
import SkeeCore

// `skee` — the headless shell. Everything here is I/O around SkeeCore:
// parsing arguments, reading/writing save files, printing. No rules live here.

let usage = """
skee — play and measure Skee Skee Skee from the terminal

  skee shot <power> <aim> [--start s] [--fold f] [--ante n] [--boss name] [--trace]
      Throw one ball and describe what happened.
  skee map [--ante n] [--boss name] [--fold f] [--steps n]
      Power x aim map of where balls end up. 1-5 = 10..50 rings, L/R = 100 pockets, . = gutter.
  skee windows [--ante n] [--boss name] [--fold f]
      Widest power window per hole: the forgiveness of each target.
  skee play <save.json> <command...>
      Persistent run. Commands: new [seed] | show | throw <power> <aim> [start] [fold]
      | arm <i> | buy <i> [hole] | reroll | sell <i> | leave
  skee balance [--runs n] [--skill expert|regular|novice|perfect|all] [--seed s]
      Monte Carlo bot runs with fun metrics.
  skee bot <seed> [--skill name]
      Narrate one bot run round by round.
"""

let argv = Array(CommandLine.arguments.dropFirst())
guard let command = argv.first else { print(usage); exit(0) }
nonisolated(unsafe) let args = Array(argv.dropFirst())

func flag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func has(_ name: String) -> Bool { args.contains("--\(name)") }
func positional() -> [String] {
    var out: [String] = []
    var i = 0
    while i < args.count {
        if args[i].hasPrefix("--") { i += (args[i] == "--trace" ? 1 : 2); continue }
        out.append(args[i]); i += 1
    }
    return out
}
func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("skee: \(msg)\n".utf8)); exit(2)
}

func tableFromFlags() -> Table {
    var t = difficultyTable(ante: Int(flag("ante") ?? "1") ?? 1)
    if let b = flag("boss") {
        guard let boss = Boss.allCases.first(where: { $0.rawValue.lowercased() == b.lowercased() })
        else { fail("unknown boss \(b); one of \(Boss.allCases.map(\.rawValue))") }
        t = boss.modify(t)
    }
    return t
}

switch command {
case "shot": shotCommand()
case "map": mapCommand()
case "windows": windowsCommand()
case "play": playCommand()
case "balance": balanceCommand()
case "bot": botCommand()
default: print(usage); exit(1)
}
