/// Where a ball ends up. Every shot resolves to exactly one hole; a ball that
/// never reaches the board, rolls off it, or rests outside the rings is
/// `.gutter`.
public enum Hole: String, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case gutter, ring10, ring20, ring30, ring40, ring50, pocketLeft, pocketRight

    /// Printed face value, as on a real cabinet.
    public var faceValue: Int {
        switch self {
        case .gutter: 0
        case .ring10: 10
        case .ring20: 20
        case .ring30: 30
        case .ring40: 40
        case .ring50: 50
        case .pocketLeft, .pocketRight: 100
        }
    }

    /// The hole hit by the left-right mirror image of a shot.
    public var mirrored: Hole {
        switch self {
        case .pocketLeft: .pocketRight
        case .pocketRight: .pocketLeft
        default: self
        }
    }

    public var isPocket: Bool { self == .pocketLeft || self == .pocketRight }

    public static func < (a: Hole, b: Hole) -> Bool {
        (a.faceValue, a.rawValue) < (b.faceValue, b.rawValue)
    }

    /// Ring holes from the outside in, matching `BoardSpec.ringWalls` order
    /// reversed: index 0 is the 40 cup (inside the smallest wall).
    static let byWallIndex: [Hole] = [.ring40, .ring30, .ring20, .ring10]
}

extension Hole {
    /// Where a Hot Spot can land. Never the 10: double nothing much is no treat.
    public static let hotSpots: [Hole] = [.ring20, .ring30, .ring40, .ring50, .pocketLeft, .pocketRight]
}
