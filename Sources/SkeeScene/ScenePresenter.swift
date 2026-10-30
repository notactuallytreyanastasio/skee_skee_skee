import SceneKit
import simd
import SkeeCore
import SkeeRender

/// Moves the cabinet to match a Presentation. The only state it keeps is
/// what rolling needs (the ball's orientation and last position) and caches
/// to avoid re-texturing unchanged plates. Everything else is read fresh
/// from the presentation each frame.
/// Runs on SceneKit's render thread (renderer(_:updateAtTime:)), so the
/// ball moves in step with the frames that draw it.
public final class ScenePresenter: @unchecked Sendable {
    public let cabinet: Cabinet
    public private(set) var rig: CameraRig
    var orientation = simd_quatf(angle: 0, axis: SIMD3(1, 0, 0))
    var lastCenter: SIMD3<Float>?
    var spinRate = SIMD3<Float>(repeating: 0)   // axis * radians/s, kept through flight
    var baseCamera: SIMD3<Float>
    /// Seconds since each hole last took a ball, for its flash.
    var flashAge: [Hole: Float] = [:]
    var lean: Float = 0

    public init(cabinet: Cabinet, aspect: Float) {
        self.cabinet = cabinet
        rig = Cabinet.fit(points: cabinet.framingPoints, aspect: aspect)
        cabinet.apply(rig)
        baseCamera = rig.position
    }

    public func refit(aspect: Float) {
        rig = Cabinet.fit(points: cabinet.framingPoints, aspect: aspect)
        cabinet.apply(rig)
        baseCamera = rig.position
    }

    var world: World { cabinet.world }

    /// - Parameters:
    ///   - held: lane point under the thumb while a stroke is in progress.
    public func update(_ p: Presentation, held: SIMD3<Float>?, dt: Double) {
        let s = p.shown
        let r = world.ballRadius

        // Ball.
        var center: SIMD3<Float>
        var scale: Float = 1
        var normal = world.laneNormal
        var airborne = false
        var visible = true
        if let sample = p.ball {
            center = world.ballCenter(sample)
            scale = world.ballScale(sample)
            normal = world.surfaceNormal(sample)
            airborne = sample.phase == .air && sample.height > 0.005
            if !p.isBusy || p.current.map(isRoll) == false, let rest = p.restingBall {
                // Just landed: drop through the hole.
                let age = Float(0.6 - (rest.until - p.clock))
                let sink = min(1, max(0, age / 0.35))
                center -= world.boardNormal * (sink * 2.2 * r * scale)
                scale *= 1 - 0.4 * sink
                if sample.along <= world.table.lane.length { visible = sink < 0.5 }   // gutter: gone
            }
        } else if case .throwing = s.phase, !p.isBusy {
            center = held ?? (world.lane(x: 0, s: 0.12) + world.laneNormal * r)
        } else {
            center = world.lane(x: 0, s: 0.12) + world.laneNormal * r
            visible = false
        }

        // Roll: rotate by distance travelled over radius, about the axis in
        // the surface perpendicular to the motion. In the air, keep spinning.
        if let last = lastCenter, visible {
            let d = center - last
            let dist = simd_length(d)
            if !airborne, dist > 1e-5, dist < 0.5 {
                let axis = simd_normalize(simd_cross(normal, d))
                let angle = dist / (r * scale)
                orientation = simd_quatf(angle: angle, axis: axis) * orientation
                // Smoothed, and only from real frame steps: a tiny dt made
                // the in-flight spin explode.
                if dt > 1.0 / 400 { spinRate = spinRate * 0.6 + axis * (angle / Float(dt)) * 0.4 }
            } else if airborne, simd_length(spinRate) > 0 {
                let rate = simd_length(spinRate)
                orientation = simd_quatf(angle: rate * Float(dt), axis: spinRate / rate) * orientation
            }
        }
        lastCenter = visible ? center : nil
        cabinet.ball.isHidden = !visible

        // Shadow on the surface under the ball: smaller and fainter the
        // higher the ball is.
        var ground = center - normal * (r * scale)
        var height: Float = 0
        if let sample = p.ball, sample.along > world.table.lane.length {
            ground = world.board(Vec2(sample.x, sample.along - world.table.lane.length), z: 0)
            height = Float(sample.height)
        }
        let sn = cabinet.shadow
        sn.isHidden = !visible
        sn.simdPosition = ground + normal * 0.004
        sn.simdOrientation = simd_quatf(from: SIMD3(0, 0, 1), to: normal)
        let fade = max(0.25, 1 - height * 3)
        sn.simdScale = SIMD3(repeating: scale * (0.7 + 0.3 * fade))
        sn.opacity = CGFloat(fade)

        // Bulbs: idle twinkle, a fast chase on fever, jackpots, banners and
        // while a jackpot-chance ball is in the air.
        let excited = p.flash > 0.05 || s.fever || p.banner != nil || p.anticipation > 0
        let rate = excited ? 14.0 : 2.0
        cabinet.lightBulbs(phase: Int(p.clock * rate), level: excited ? 0.9 : 0.35)
        cabinet.ball.simdPosition = center
        cabinet.ball.simdOrientation = orientation
        cabinet.ball.simdScale = SIMD3(repeating: scale)

        // Drops: stars burst from the hole and its ring flashes.
        for cue in p.cues {
            if case .drop(let hole) = cue { burst(at: hole, big: hole.faceValue >= 50); flashAge[hole] = 0 }
        }
        for k in flashAge.keys { flashAge[k]! += Float(dt) }

        // Ring reels: each ring shows the symbol its reel is on, orbiting
        // while it spins. Rings that would pair or finish the line glow.
        let have = (p.tallyProgress == nil && !p.isBusy) ? s.round.currentBalls.map(\.symbol) : []
        let lineNow = Payline.evaluate(have).addedMult
        let pulse = Float(0.6 + 0.4 * sin(p.clock * 7))
        for hole in BoardSetup.reelHoles {
            let reel = s.setup.reel(hole)
            let pos = p.reelPositions[hole] ?? 0
            let idx = ((Int(pos.rounded()) % reel.count) + reel.count) % reel.count
            let sym = reel[idx]
            var glow: Float = 0
            if !have.isEmpty && have.count < 3 && s.phase == .throwing {
                let gain = Payline.evaluate(have + [sym]).addedMult - lineNow
                if gain > 0 { glow = (have.count == 2) ? 2 : 1 }
            }
            if let age = flashAge[hole], age < 0.6 { glow = max(glow, 2); }
            cabinet.setReel(hole, sym, turn: pos, glow: glow,
                            pulse: flashAge[hole].map { $0 < 0.6 ? 1 - $0 / 0.6 + 0.3 : pulse } ?? pulse)
        }

        // Balls waiting in the tray.
        let inFlight = p.current.map(isRoll) == true
        let inHand = (held != nil || inFlight || (!p.isBusy && s.phase == .throwing)) ? 1 : 0
        cabinet.setWaiting(max(0, s.round.ballsLeft - inHand))

        // Camera: lean toward the target while a jackpot-chance ball flies,
        // and shake on big moments.
        let want = Float(p.anticipation)
        lean += (want - lean) * min(1, Float(dt) * (want > lean ? 5 : 2.5))
        let focus = world.board(Vec2(0, world.table.board.ringCenter.y))
        let k = Float(p.shake) * 0.012
        let t = Float(p.clock)
        let pos = baseCamera + (focus - baseCamera) * (0.2 * lean)
        cabinet.camera.simdPosition = pos + SIMD3(sin(t * 71) * k, cos(t * 53) * k, 0)
        cabinet.camera.simdLook(at: rig.target + (focus - rig.target) * (0.45 * lean))
    }

    func isRoll(_ b: Beat) -> Bool { if case .roll = b { true } else { false } }

    /// Stars out of a hole.
    func burst(at hole: Hole, big: Bool) {
        let ps = SCNParticleSystem()
        ps.particleImage = Textures.star
        ps.birthRate = big ? 900 : 450
        ps.emissionDuration = 0.06
        ps.loops = false
        ps.particleLifeSpan = 0.7
        ps.particleLifeSpanVariation = 0.25
        ps.particleVelocity = big ? 0.9 : 0.6
        ps.particleVelocityVariation = 0.35
        ps.spreadingAngle = 70
        ps.emittingDirection = SCNVector3(world.boardNormal)
        ps.particleSize = 0.022
        ps.particleSizeVariation = 0.01
        ps.particleAngularVelocity = 360
        ps.particleAngularVelocityVariation = 360
        ps.acceleration = SCNVector3(SIMD3<Float>(0, -2.2, 0))
        ps.particleColor = hex(0xFFE066)
        ps.particleColorVariation = SCNVector4(SIMD4<Float>(0.4, 0.2, 0.2, 0))
        ps.blendMode = .alpha
        ps.isLightingEnabled = false
        let at = world.board(world.table.board.holeCenter(hole), z: 0.02)
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(at, 1)
        cabinet.scene.addParticleSystem(ps, transform: SCNMatrix4(m))
    }

    // MARK: thumb

    /// The lane point under a screen position (fractions, y down), clamped
    /// to the near part of the lane below the crease.
    public func lanePoint(screen f: SIMD2<Float>, aspect: Float) -> SIMD3<Float>? {
        let (o, d) = rig.ray(f, aspect: aspect)
        let n = world.laneNormal
        let p0 = world.lane(x: 0, s: 0)
        let denom = simd_dot(d, n)
        guard abs(denom) > 1e-5 else { return nil }
        let t = simd_dot(p0 - o, n) / denom
        guard t > 0 else { return nil }
        var hit = o + d * t
        let half = Float(world.table.lane.width) / 2 - world.ballRadius
        hit.x = min(max(hit.x, -half), half)
        // Never past the hump, even while the thumb sinks into the crease.
        let along = simd_dot(hit - p0, world.laneForward)
        let maxAlong = world.laneLength - 0.03
        if along > maxAlong { hit -= world.laneForward * (along - maxAlong) }
        return hit + n * world.ballRadius
    }

    /// Where the crease and the lane are on screen, for flick analysis.
    public func flickGeometry(size: CGSize) -> FlickGeometry {
        let aspect = Float(size.width / size.height)
        let crease = Double(rig.project(world.lane(x: 0, s: world.table.lane.length), aspect: aspect).y) * Double(size.height)
        let l = rig.project(world.lane(x: -world.table.lane.width / 2, s: 0.2), aspect: aspect)
        let r = rig.project(world.lane(x: world.table.lane.width / 2, s: 0.2), aspect: aspect)
        return FlickGeometry(creaseY: crease, laneCenterX: Double(l.x + r.x) / 2 * Double(size.width),
                             laneHalfWidth: Double(r.x - l.x) / 2 * Double(size.width))
    }

    /// Physics lane coordinates (x across, s up the lane) of a scene point
    /// on the lane.
    public func laneCoordinates(_ p: SIMD3<Float>) -> (x: Double, s: Double) {
        let rel = p - world.lane(x: 0, s: 0)
        return (Double(rel.x), Double(simd_dot(rel, world.laneForward) / world.laneScale))
    }
}

extension CameraRig {
    /// Ray through a screen position (fractions, y down).
    public func ray(_ f: SIMD2<Float>, aspect: Float) -> (SIMD3<Float>, SIMD3<Float>) {
        let fwd = simd_normalize(target - position)
        let r = simd_normalize(simd_cross(fwd, SIMD3(0, 1, 0)))
        let u = simd_cross(r, fwd)
        let t = tan(fov * .pi / 360)
        let x = (f.x * 2 - 1) * t * aspect, y = (1 - f.y * 2) * t
        return (position, simd_normalize(fwd + r * x + u * y))
    }
}
