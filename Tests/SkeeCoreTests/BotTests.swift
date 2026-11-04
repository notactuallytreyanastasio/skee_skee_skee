import Testing
@testable import SkeeCore

@Suite("Aim book and bots")
struct BotTests {
    @Test func aimBookFindsAWindowForEveryHole() {
        let book = AimBook(table: .standard, powerSteps: 120)
        for hole in Hole.allCases where hole != .gutter {
            let w = book.best[hole]
            #expect(w != nil, "no window for \(hole)")
            if let w {
                #expect(simulateShot(w.launch, on: .standard).hole == hole)
            }
        }
    }

    @Test func perfectBotHitsWhatItAimsAt() {
        let book = AimBook(table: .standard, powerSteps: 160, aims: [0])
        var rng = SplitMix64(seed: 1)
        let l = Skill.perfect.perturb(book.best[.ring50]!.launch, rng: &rng)
        #expect(simulateShot(l, on: .standard).hole == .ring50)
    }

    @Test func botRunIsDeterministic() {
        let a = playBotRun(seed: 4, skill: .regular)
        let b = playBotRun(seed: 4, skill: .regular)
        #expect(a.final == b.final)
        #expect(a.actions == b.actions)
    }

    @Test func skillMatters() {
        // On the comet: the base game is tuned so a shaky hand wins often,
        // which is the point, so skill shows where it is meant to.
        let seeds: [UInt64] = [1, 2, 3, 4, 5, 6]
        var books: [Table: AimBook] = [:]
        let novice = seeds.map { playBotRun(seed: $0, skill: .novice, ball: .comet, books: &books).final.stats.roundsCleared }.reduce(0, +)
        books = [:]
        let expert = seeds.map { playBotRun(seed: $0, skill: .expert, ball: .comet, books: &books).final.stats.roundsCleared }.reduce(0, +)
        #expect(expert > novice)
    }
}
