/// The table tightens as the run goes on: smaller 50 hole and pockets, wider
/// lips, holes that only catch slower balls. Each knob moves linearly from
/// ante 1 to ante 8 and stops there. The ranges are chosen so the last ante
/// still leaves a real window for a 50 (see DifficultyTests).
public func difficultyTable(ante: Int, base: Table = .standard, antes: Int = 8) -> Table {
    let t = Double(clamp(ante, 1, antes) - 1) / Double(max(antes - 1, 1))
    var table = base
    table.board.lipBand = base.board.lipBand + 0.25 * t
    table.board.centerHoleRadius = base.board.centerHoleRadius - 0.008 * t
    table.board.captureSpeed = base.board.captureSpeed - 0.3 * t
    table.board.pockets = base.board.pockets.map { p in
        var q = p; q.radius = p.radius - 0.01 * t; return q
    }
    return table
}
