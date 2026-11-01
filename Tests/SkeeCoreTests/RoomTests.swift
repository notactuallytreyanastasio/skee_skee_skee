import Testing
@testable import SkeeCore

@Suite("Rooms")
struct RoomTests {
    @Test func everyRoomCanReachEveryHole() {
        for room in Room.allCases {
            let book = AimBook(table: room.table)
            for hole in BoardSetup.reelHoles { #expect(book.best[hole] != nil, "\(room) can't reach \(hole)") }
        }
    }

    @Test func roomsAreDifferentMachines() {
        let boards = Set(Room.allCases.map(\.table))
        let strips = Set(Room.allCases.map(\.strips))
        #expect(boards.count == Room.allCases.count)
        #expect(strips.count == Room.allCases.count)
        for room in Room.allCases { #expect(room.strips.map(\.count) == Pull.strips.map(\.count)) }
    }

    @Test func aRunIsPlayedOnItsRoomsBoardAndMachine() throws {
        let s = newRun(seed: 5, room: .penthouse)
        #expect(s.setup == Room.penthouse.setup)
        #expect(table(for: s).board.tilt == Room.penthouse.table.board.tilt)
        let pulled = try apply(.pull(.one), to: s).get().state
        #expect(pulled.round.pull?.room == .penthouse)
    }

    @Test func aCompedNightStartsWithItsTickets() {
        #expect(newRun(seed: 5, extraTickets: 2).tickets == RunConfig.standard.startTickets + 2)
        #expect(practiceRun(room: .highRoller).room == .highRoller)
    }

    @Test func thresholdsClimb() {
        let t = Room.allCases.map(\.compThreshold)
        #expect(t == t.sorted() && Set(t).count == t.count)
    }
}

@Suite("Comps")
struct CompTests {
    @Test func theHostIsReadyOnceWinningsPassTheNextRoomsThreshold() {
        var w = Wallet()
        #expect(w.compDue == nil)
        w.credit(Room.neonLounge.compThreshold)
        #expect(w.compDue == .neonLounge)
        w.rooms.insert(.neonLounge)
        #expect(w.compDue == nil)
        w.credit(Room.highRoller.compThreshold)
        #expect(w.compDue == .highRoller)
    }

    @Test func aSignedDealBanksNightsAndPaysCredit() {
        var h = Haggle(room: .neonLounge, seed: 1)
        h.say("two nights?")
        h.hear(HostReply(say: "Fine.", offer: .init(nights: 2, tickets: 1, credit: 100), mood: 1))
        h.accept()
        var w = Wallet()
        w.close(h)
        #expect(w.rooms.contains(.neonLounge) && w.room == .neonLounge)
        #expect(w.balance == 100)
        #expect(w.checkIn() == 1)
        #expect(w.checkIn() == 1)
        #expect(w.checkIn() == 0)
        #expect(w.comps[.neonLounge] == nil)
    }

    @Test func aHostWhoWalksLeavesTheRoomOnOpeningTerms() {
        var h = Haggle(room: .highRoller, seed: 1)
        h.say("two nights")
        h.hear(HostReply(say: "Two.", offer: .init(nights: 2, tickets: 0, credit: 0)))
        h.say("MORE")
        h.hear(HostReply(say: "Goodbye.", offer: .init(nights: 2, tickets: 0, credit: 0), walk: true))
        var w = Wallet()
        w.close(h)
        #expect(h.status == .walked)
        #expect(w.rooms.contains(.highRoller))
        #expect(w.comps[.highRoller] == .opening(.highRoller))
    }

    @Test func anOpenHaggleChangesNothing() {
        var w = Wallet()
        w.close(Haggle(room: .neonLounge, seed: 1))
        #expect(w == Wallet())
    }
}

@Suite("Haggle")
struct HaggleTests {
    func push(_ h: inout Haggle, _ terms: HostReply.Terms, mood: Int = 0) {
        h.say("more")
        h.hear(HostReply(say: "...", offer: terms, mood: mood))
    }

    @Test func theHostOpensWithOneNight() {
        let h = Haggle(room: .neonLounge, seed: 3)
        #expect(h.offer == .opening(.neonLounge))
        #expect(h.lines.count == 1 && h.lines[0].speaker == .host)
        #expect((3...4).contains(h.patience))
        #expect(h.budget > Comp.opening(.neonLounge).value && h.budget < Comp.ceiling(.neonLounge).value)
    }

    @Test func noReplyCanBreakTheBudgetOrTheCeiling() {
        var h = Haggle(room: .penthouse, seed: 9)
        push(&h, .init(nights: 99, tickets: 99, credit: 99_999), mood: 1)
        #expect(h.offer.value <= h.budget)
        let top = Comp.ceiling(.penthouse)
        #expect(h.offer.nights <= top.nights && h.offer.tickets <= top.tickets && h.offer.credit <= top.credit)
    }

    @Test func offersNeverShrink() {
        var h = Haggle(room: .neonLounge, seed: 2)
        push(&h, .init(nights: 2, tickets: 1, credit: 0), mood: 1)
        let before = h.offer
        push(&h, .init(nights: 1, tickets: 0, credit: 0), mood: 1)
        #expect(h.offer == before)
    }

    @Test func everyPushCostsPatienceUnlessItCharms() {
        var h = Haggle(room: .neonLounge, seed: 2)
        let p = h.patience
        push(&h, .init(nights: 1, tickets: 0, credit: 0), mood: 1)
        #expect(h.patience == p)
        push(&h, .init(nights: 1, tickets: 0, credit: 0))
        #expect(h.patience == p - 1)
        push(&h, .init(nights: 1, tickets: 0, credit: 0), mood: -5)
        #expect(h.patience == p - 3 || h.status == .walked)
    }

    @Test func runningOutOfPatienceEndsItAndSaysSo() {
        var h = Haggle(room: .neonLounge, seed: 2)
        while h.status == .open { push(&h, .init(nights: 1, tickets: 0, credit: 0), mood: -1) }
        #expect(h.status == .walked)
        #expect(h.lines.last?.speaker == .stage)
        #expect(h.final == .opening(.neonLounge))
        let n = h.lines.count
        h.say("wait!")
        #expect(h.lines.count == n)
    }

    @Test func theModelSeesTheRulesAndItsOwnRepliesAsJSON() {
        var h = Haggle(room: .highRoller, seed: 4)
        push(&h, .init(nights: 2, tickets: 0, credit: 0))
        let m = h.messages
        #expect(m[0].role == .system && m[0].content.contains("\(h.budget)"))
        #expect(m[1].role == .assistant && m[1].content.hasPrefix("{\"say\""))
        #expect(m[2] == ChatMessage(.user, "more"))
        #expect(m.last?.content.contains("\"nights\": 2") == true)
    }
}
