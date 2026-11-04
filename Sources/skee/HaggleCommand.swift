import Foundation
import SkeeCore
import SkeeNet

/// skee haggle: negotiate a room comp with the host, for real, against
/// DeepSeek. Lines come from stdin, or from --say "a|b|c" to script a
/// conversation. "deal" accepts. Prints each reply and what the rules did
/// to it, so a model that overreaches is visible.
func haggleCommand() {
    let room = flag("room").flatMap(Room.init) ?? .neonLounge
    let seed = UInt64(flag("seed") ?? "1") ?? 1
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    guard let key = DeepSeek.key(envFile: root.appendingPathComponent(".env")) else {
        fail("no DeepSeek key: run scripts/secrets.sh or set DEEPSEEK_API_KEY")
    }
    let client = DeepSeek(key: key)
    var h = Haggle(room: room, seed: seed, returning: has("returning"))
    var script = flag("say").map { $0.split(separator: "|").map(String.init) }
    print("[\(room.name)] budget \(h.budget) (hidden from the player), patience \(h.patience)")
    print("\(h.host.name): \(h.lines[0].text)")
    printOffer(h)
    while h.status == .open {
        let line: String
        if script != nil {
            guard let next = script?.first else { break }
            script?.removeFirst()
            line = next
            print("> \(line)")
        } else {
            print("> ", terminator: "")
            guard let l = readLine() else { break }
            line = l
        }
        if line.lowercased() == "deal" { h.accept(); break }
        h.say(line)
        let started = Date()
        let now = h
        let result = blocking { try await client.reply(in: now) }
        switch result {
        case .failure(let e): fail("\(e)")
        case .success(let r):
            let asked = r.offer
            h.hear(r)
            print("\(h.host.name): \(r.say)")
            print(String(format: "  (%.1fs; mood %+d, asked for %d/%d/%d, rules allowed %d/%d/%d; patience %d)",
                         Date().timeIntervalSince(started), r.mood, asked.nights, asked.tickets, asked.credit,
                         h.offer.nights, h.offer.tickets, h.offer.credit, h.patience))
            printOffer(h)
        }
    }
    print("=> \(h.status.rawValue): \(h.offer.nights) night(s), +\(h.offer.tickets) tickets/night, \(h.offer.credit) credit (value \(h.offer.value) of budget \(h.budget))")
}

func printOffer(_ h: Haggle) {
    print("  OFFER: \(h.offer.nights) night(s) · +\(h.offer.tickets) tickets a night · \(h.offer.credit) credit")
}

final class ResultBox<T>: @unchecked Sendable { var value: Result<T, Error>?; init() {} }

/// Run an async throwing call to completion from synchronous CLI code.
func blocking<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) -> Result<T, Error> {
    let box = ResultBox<T>(), done = DispatchSemaphore(value: 0)
    Task {
        do { box.value = .success(try await body()) } catch { box.value = .failure(error) }
        done.signal()
    }
    done.wait()
    return box.value!
}
