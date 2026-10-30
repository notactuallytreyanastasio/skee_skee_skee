/// Simulate one ball from release to rest. Pure: the same `Launch` on the same
/// `Table` always returns the same `ShotResult`, bit for bit.
///
/// Three phases share one fixed-step clock:
/// 1. **Lane** — rolls up an incline with rolling friction; side rails
///    reflect. If it stalls before the hinge it is a dud and rolls back.
/// 2. **Air** — leaves the ridge at the hinge's launch angle. Ballistic in
///    board coordinates, with the backwall and side walls reflecting. Coming
///    down onto a ring wall's top is a lip hit: it bounces up and gets shoved
///    to whichever side of the wall its centre was on. That is the rattle,
///    and the main source of "edge".
/// 3. **Board** — rolls on the tilted face. Ring walls block it while it is
///    lower than the lip. It drops into the 50 hole or a pocket if it passes
///    over one, rolls off the bottom into the gutter, or settles against a
///    ring wall and scores that ring.
public func simulateShot(_ launch: Launch, on table: Table) -> ShotResult {
    var sim = ShotSim(launch: launch, table: table)
    return sim.run()
}

private struct ShotSim {
    let launch: Launch
    let table: Table
    var lane: LaneSpec { table.lane }
    var board: BoardSpec { table.board }
    var r: Double { board.ballRadius }

    var t = 0.0
    var step = 0
    var events: [ShotEvent] = []
    var path: [PathSample] = []
    var hingeSpeed: Double?
    var firstLanding: Vec2?
    var peak = 0.0
    var touchedWall = false

    init(launch: Launch, table: Table) {
        self.launch = launch
        self.table = table
    }

    /// Record at 60 Hz (every 4th 240 Hz step); plenty for animation.
    mutating func record(_ phase: PathPhase, _ x: Double, _ along: Double, _ h: Double, force: Bool = false) {
        if force || step % 4 == 0 {
            path.append(PathSample(t: t, phase: phase, x: x, along: along, height: h))
        }
    }

    mutating func finish(_ hole: Hole) -> ShotResult {
        ShotResult(launch: launch, hole: hole, events: events, path: path,
                   hingeSpeed: hingeSpeed, firstLanding: firstLanding,
                   peakHeight: peak, duration: t)
    }

    mutating func run() -> ShotResult {
        let g = table.gravity, dt = table.dt
        let halfLane = lane.width / 2 - r
        let v0 = lane.releaseSpeed(power: launch.power) * (1 - lane.skidLoss * launch.skid)
        let hook = launch.spin * lane.hook
        let angle = launch.aim * lane.maxAimAngle
        var x = launch.start * halfLane, s = 0.0
        var vx = v0 * _sin(angle), vs = v0 * _cos(angle)
        let slopePull = -g * _sin(lane.incline)
        let friction = lane.rollingFriction * g * _cos(lane.incline)

        // Phase 1: lane.
        while s < lane.length {
            record(.lane, x, s, 0)
            let speed = (vx * vx + vs * vs).squareRoot()
            let f = speed > 0 ? friction / speed : 0
            vs += (slopePull - f * vs) * dt
            vx += (-f * vx + hook) * dt
            x += vx * dt
            s += vs * dt
            if abs(x) > halfLane {
                x = x > 0 ? halfLane : -halfLane
                vx = -vx * lane.railRestitution
                events.append(.rail)
            }
            t += dt; step += 1
            if vs <= 0 && !events.contains(.dud) { events.append(.dud) }
            if events.contains(.dud) && (s <= 0 || t >= table.maxDuration) {
                record(.lane, x, max(s, 0), 0, force: true)
                events.append(.gutter)
                return finish(.gutter)
            }
        }

        // Phase 2 + 3: over the hinge, onto the board.
        hingeSpeed = vs
        events.append(.launched)
        let beta = table.hinge.launchAngle(fold: launch.fold)
        let carried = vs * table.hinge.carry
        var p = Vec2(x, 0)
        var v = Vec2(vx, carried * _cos(beta))
        var z = 0.0
        var vz = carried * _sin(beta)
        var airborne = true
        var resting = 0.0
        var nudges = 0
        let gIn = Vec2(0, -g * _sin(board.tilt)) + board.wind
        let gN = g * _cos(board.tilt)
        let halfBoard = board.width / 2 - r
        let back = board.height - r

        while t < table.maxDuration {
            record(airborne ? .air : .board, p.x, lane.length + p.y, z)

            if airborne {
                v = v + gIn * dt
                vz -= gN * dt
                let prevZ = z
                p = p + v * dt
                z += vz * dt
                peak = max(peak, z)

                if prevZ >= board.lipHeight && z < board.lipHeight && -vz >= board.lipMinFall,
                   let (ring, outward) = lipUnder(p) {
                    let fall = -vz
                    z = board.lipHeight
                    vz = fall * board.lipBounce
                    v = v + outward * (board.lipKick * fall)
                    events.append(.lip(ring: ring))
                }

                if z <= 0 {
                    z = 0
                    if firstLanding == nil {
                        firstLanding = p
                        events.append(.landed)
                    }
                    vz = -vz * board.bounce
                    v = v * board.landingGrip
                    if vz < 0.15 { vz = 0; airborne = false }
                }
            } else {
                let speed = v.length
                var a = gIn
                if speed > 0 { a = a - v * (board.rollingFriction * gN / speed) }
                v = v + a * dt
                p = p + v * dt
            }

            if z < board.lipHeight { (p, v) = collideRingWalls(p, v) }
            if abs(p.x) > halfBoard {
                p.x = p.x > 0 ? halfBoard : -halfBoard
                v.x = -v.x * board.wallRestitution
                touchedWall = true
            }
            if p.y > back {
                p.y = back
                v.y = -abs(v.y) * board.backwallRestitution
                touchedWall = true
                events.append(.backwall)
            }
            t += dt; step += 1

            if z < r * 0.5, v.length <= board.captureSpeed, let hole = holeUnder(p, cleanFlight: firstLanding == nil && !touchedWall) {
                if firstLanding == nil { firstLanding = p }
                record(.board, p.x, lane.length + p.y, 0, force: true)
                events.append(.dropped(hole))
                return finish(hole)
            }
            if p.y < -r {
                record(.board, p.x, lane.length + p.y, z, force: true)
                events.append(.gutter)
                return finish(.gutter)
            }
            if !airborne && v.length < 0.05 {
                resting += dt
                if resting > 0.2 {
                    // A ring is a cup: nothing rests on it except in its
                    // hole. A ball balanced on top of an inner wall (dead
                    // centre, nothing to tip it) is nudged around the wall
                    // toward the bottom, on the side it is already on.
                    let zone = board.zone(at: p)
                    guard zone != .gutter, nudges < 6 else { break }
                    let rel = p - board.ringCenter
                    let side = rel.x >= 0 ? 1.0 : -1.0
                    let tangent = Vec2(-rel.y, rel.x).normalized * (rel.y > 0 ? side : -side)
                    v = (tangent + Vec2(0, -0.3)).normalized * 0.35
                    nudges += 1
                    resting = 0
                }
            } else {
                resting = 0
            }
        }

        record(.board, p.x, lane.length + p.y, z, force: true)
        let hole = board.zone(at: p)
        events.append(hole == .gutter ? .gutter : .settled(hole))
        return finish(hole)
    }

    /// The ring wall whose top the ball is coming down on, with the unit
    /// vector pointing to the side of the wall the ball's centre is on.
    func lipUnder(_ p: Vec2) -> (Int, Vec2)? {
        let rel = p - board.ringCenter
        let d = rel.length
        for (i, wall) in board.ringWalls.enumerated() where abs(d - wall) < r * board.lipBand {
            let radial = d == 0 ? Vec2(0, 1) : rel * (1 / d)
            return (i, d >= wall ? radial : -radial)
        }
        return nil
    }

    /// Push the ball out of any ring wall face it overlaps and reflect the
    /// velocity component into the wall.
    func collideRingWalls(_ p0: Vec2, _ v0: Vec2) -> (Vec2, Vec2) {
        var p = p0, v = v0
        let rel = p - board.ringCenter
        let d = rel.length
        guard d > 0 else { return (p, v) }
        let radial = rel * (1 / d)
        for wall in board.ringWalls where abs(d - wall) < r {
            let side = d >= wall ? 1.0 : -1.0
            let n = radial * side
            p = board.ringCenter + radial * (wall + side * r)
            let vn = v.dot(n)
            if vn < 0 { v = v - n * ((1 + board.wallRestitution) * vn) }
            break
        }
        return (p, v)
    }

    func holeUnder(_ p: Vec2, cleanFlight: Bool) -> Hole? {
        if (p - board.centerHole).length < board.centerHoleRadius { return .ring50 }
        let zone = board.zone(at: p)
        if zone != .gutter && (p - board.holeCenter(zone)).length < board.ringHoleRadius { return zone }
        for pocket in board.pockets where (p - pocket.center).length < pocket.radius && (!board.pocketsNeedFlight || cleanFlight) {
            return pocket.hole
        }
        return nil
    }
}
