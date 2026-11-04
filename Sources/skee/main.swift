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
      Persistent run. Commands: new [seed] | show | throw <power> <aim> [start] [fold] [--hand skill]
      | arm <i> | buy <i> [hole] | reroll | sell <i> | leave
  skee balance [--runs n] [--skill expert|regular|novice|perfect|all] [--seed s] [--room boardwalk|neonLounge|highRoller|penthouse]
      Monte Carlo bot runs with fun metrics.
  skee haggle [--room neonLounge|highRoller|penthouse] [--seed n] [--say "line|line|deal"] [--relay url]
      Negotiate a room comp with the host, live against DeepSeek (key from .env; scripts/secrets.sh).
  skee bot <seed> [--skill name]
      Narrate one bot run round by round.
  skee scene [--seed n] [--out f.png] [--size outer]
      Render the 3D cabinet as the app shows it, at the Duo inner display size.
  skee frame [--save run.json] [--t secs | --settle] [--title] [--select offer] [--size outer] [--out f.png]
      A full app frame, 3D scene plus HUD, at the phone's size.
  skee scenefilm [--save run.json] [--from secs] [--frames n] [--dt secs] [--cols n] [--scale k]
      Contact sheet of the last action's animation in 3D.
  skee moments [--runs n] [--room name] [--skill name]
      Scan bot runs for trailer moments, by seed and action index.
  skee film [--out dir] [--fps n] [--only 0,3]
      Render the trailer, 16:9 and 9:16, from real runs. Needs ffmpeg.
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
    let room = flag("room").flatMap(Room.init) ?? .boardwalk
    var t = difficultyTable(ante: Int(flag("ante") ?? "1") ?? 1, base: room.table)
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
case "settleprobe": settleProbe()
case "scene": MainActor.assumeIsolated { sceneCommand() }
case "scenefilm": MainActor.assumeIsolated { sceneFilmCommand() }
case "frame": MainActor.assumeIsolated { frameCommand() }
case "flickprobe": flickProbe()
case "haggle": haggleCommand()
case "moments": momentsCommand()
case "film": MainActor.assumeIsolated { filmCommand() }
case "icon": iconCommand()
default: print(usage); exit(1)
}
