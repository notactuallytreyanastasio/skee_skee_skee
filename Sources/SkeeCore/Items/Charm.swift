/// Passive, permanent modifiers — the Jokers of this game. Held in a row of
/// slots; applied left to right after the payline.
public enum Charm: String, Hashable, Sendable, Codable, CaseIterable {
    case luckyPenny, hotStreak, heavyHand, gutterRat, evenSteven, ladder,
         cornerOffice, nearMiss, multBall, glassCannon, ticketMuncher,
         hingeWhisperer, bellRinger, sevenSeas, extraBall

    public var name: String {
        switch self {
        case .luckyPenny: "Lucky Penny"
        case .hotStreak: "Hot Streak"
        case .heavyHand: "Heavy Hand"
        case .gutterRat: "Gutter Rat"
        case .evenSteven: "Even Steven"
        case .ladder: "Ladder"
        case .cornerOffice: "Corner Office"
        case .nearMiss: "Near Miss"
        case .multBall: "Mult Ball"
        case .glassCannon: "Glass Cannon"
        case .ticketMuncher: "Ticket Muncher"
        case .hingeWhisperer: "Hinge Whisperer"
        case .bellRinger: "Bell Ringer"
        case .sevenSeas: "Seven Seas"
        case .extraBall: "Extra Ball"
        }
    }

    public var blurb: String {
        switch self {
        case .luckyPenny: "+2 mult for each cherry in the frame"
        case .hotStreak: "+1 mult for each scoring ball in a row this round"
        case .heavyHand: "+40 chips for each 50"
        case .gutterRat: "Gutter balls are worth 25 chips"
        case .evenSteven: "x2 mult if all three balls hit the same hole"
        case .ladder: "x3 mult for three rings in a row, like 30-40-50"
        case .cornerOffice: "x1.5 mult for each 100 pocket"
        case .nearMiss: "+15 chips for every lip rattle"
        case .multBall: "+4 mult"
        case .glassCannon: "x3 mult. A gutter ball shatters the frame to 0"
        case .ticketMuncher: "+1 ticket for each 50 or 100"
        case .hingeWhisperer: "+3 mult for each ball thrown with the hinge half folded"
        case .bellRinger: "+3 mult if the frame has a bell"
        case .sevenSeas: "+1 mult per 7 in the frame, x2 on a pair or better of 7s"
        case .extraBall: "+1 frame (3 balls) every round"
        }
    }

    /// Price in tickets at the prize counter. Sells for half, rounded down.
    public var cost: Int {
        switch self {
        case .luckyPenny, .gutterRat: 3
        case .heavyHand, .nearMiss, .multBall, .bellRinger: 4
        case .hotStreak, .ticketMuncher, .hingeWhisperer, .sevenSeas: 5
        case .evenSteven, .ladder, .cornerOffice: 6
        case .glassCannon: 7
        case .extraBall: 8
        }
    }

    public func effects(on f: FrameView) -> [ScoreStep.Effect] {
        switch self {
        case .luckyPenny:
            let n = f.count { $0.symbol == .cherry }
            return n > 0 ? [.mult(Double(2 * n))] : []
        case .hotStreak:
            return f.streakAfter > 0 ? [.mult(Double(f.streakAfter))] : []
        case .heavyHand:
            let n = f.count { $0.hole == .ring50 }
            return n > 0 ? [.chips(40 * n)] : []
        case .gutterRat:
            let n = f.count { $0.hole == .gutter && !$0.foul }
            return n > 0 ? [.chips(25 * n)] : []
        case .evenSteven:
            return Set(f.balls.map(\.hole)).count == 1 && f.balls.count == 3 ? [.timesMult(2)] : []
        case .ladder:
            let rings: [Hole] = [.ring10, .ring20, .ring30, .ring40, .ring50]
            let idx = f.balls.compactMap { rings.firstIndex(of: $0.hole) }.sorted()
            let isRun = idx.count == 3 && idx[1] == idx[0] + 1 && idx[2] == idx[1] + 1
            return isRun ? [.timesMult(3)] : []
        case .cornerOffice:
            return f.balls.filter { $0.hole.isPocket }.map { _ in .timesMult(1.5) }
        case .nearMiss:
            let n = f.balls.reduce(0) { $0 + $1.rattles }
            return n > 0 ? [.chips(15 * n)] : []
        case .multBall:
            return [.mult(4)]
        case .glassCannon:
            return f.balls.contains { !$0.scored } ? [.timesMult(0), .note("shattered")] : [.timesMult(3)]
        case .ticketMuncher:
            let n = f.count { $0.hole == .ring50 || $0.hole.isPocket }
            return n > 0 ? [.tickets(n)] : []
        case .hingeWhisperer:
            let n = f.count { $0.fold >= 0.5 }
            return n > 0 ? [.mult(Double(3 * n))] : []
        case .bellRinger:
            return f.balls.contains { $0.symbol == .bell } ? [.mult(3)] : []
        case .sevenSeas:
            let n = f.count { $0.symbol == .seven }
            var e: [ScoreStep.Effect] = n > 0 ? [.mult(Double(n))] : []
            if f.payline == .pair(.seven) || f.payline == .triple(.seven) { e.append(.timesMult(2)) }
            return e
        case .extraBall:
            return []
        }
    }
}
