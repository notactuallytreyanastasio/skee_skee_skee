import Testing
import Foundation
@testable import SkeeCore

@Suite("Prize shelf")
struct PrizeShelfTests {
    @Test func buyingTakesWinningsAndShelvesThePrize() throws {
        let w = Wallet(balance: 500)
        let after = try w.buy(.rubberDuck).get()
        #expect(after.balance == 500 - Prize.rubberDuck.price)
        #expect(after.owned == [.rubberDuck])
    }

    @Test func cantBuyWhatYouCantAfford() {
        #expect(Wallet(balance: 10).buy(.giantBear) == .failure(.cantAfford))
    }

    @Test func eachPrizeOnlyOnce() throws {
        let w = try Wallet(balance: 1000).buy(.sticker).get()
        #expect(w.buy(.sticker) == .failure(.alreadyOwned))
    }

    @Test func pricesClimb() {
        let prices = Prize.allCases.map(\.price)
        #expect(prices == prices.sorted())
        #expect(Set(Prize.allCases.map(\.name)).count == Prize.allCases.count)
    }

    @Test func winningsComeFromPointsRoundsAndTheWin() {
        var stats = RunStats()
        stats.points = 4000
        stats.roundsCleared = 3
        #expect(winnings(stats: stats, won: false) == 4000 / 20 + 3 * 20)
        #expect(winnings(stats: stats, won: true) == 4000 / 20 + 3 * 20 + 500)
    }

    @Test func creditingARunAddsToBalanceAndLifetime() {
        var w = Wallet(balance: 5)
        w.credit(120)
        #expect(w.balance == 125)
        #expect(w.lifetime == 120)
    }

    @Test func runsCountTheirPoints() throws {
        let (s, _) = try throwing(newRun(seed: 1), .ring30, times: 3)
        #expect(s.stats.points == s.round.score)
        #expect(s.stats.points > 0)
    }

    @Test func walletRoundTripsThroughJSON() throws {
        let w = try Wallet(balance: 900, lifetime: 2000).buy(.kazoo).get()
        let data = try JSONEncoder().encode(w)
        #expect(try JSONDecoder().decode(Wallet.self, from: data) == w)
    }
}
