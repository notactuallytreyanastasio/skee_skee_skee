import SceneKit
import SkeeCore

/// The whole alley, built from toon parts. Owns handles to everything the
/// presenter moves or retextures.
public struct RingReel {
    public let pivot: SCNNode
    public let decals: [SCNNode]
    public let radius: Float
    /// Angle of the first symbol at rest.
    public let phase: Float
    /// Bright band under the symbols that pulses when this ring is a good target.
    public let halo: SCNNode
    public var shown: Symbol?
}

public final class Cabinet: @unchecked Sendable {
    public let scene = SCNScene()
    public let world: World
    public let camera = SCNNode()
    public let ball: SCNNode
    public let board = SCNNode()
    /// Soft shadow that follows the ball on the lane and board.
    public let shadow: SCNNode
    /// Marquee bulbs around the target, for chases on big moments.
    public private(set) var bulbs: [SCNNode] = []
    /// Each hole's reel, drawn as symbols orbiting its ring (or hovering by
    /// the 50 and the pockets).
    public private(set) var reelsOnBoard: [Hole: RingReel] = [:]
    /// The three reel windows of the marquee slot machine.
    public private(set) var reels: [SCNNode] = []
    /// Balls waiting in the return trough, nearest first.
    public private(set) var waiting: [SCNNode] = []
    /// Top edge of the marquee, for camera fitting.
    public private(set) var marqueeTop: SIMD3<Float> = .zero
    let kit = ToonKit()

    // Palette: pastel arcade, ink outlines.
    static let backdrop: UInt32 = 0xFFE9F6
    static let rail: UInt32 = 0x9B83F2
    static let railDark: UInt32 = 0x6F55D6
    static let cabinet: UInt32 = 0xFF6FA5
    static let zones: [UInt32] = [0xFFD84D, 0x5FC8FF, 0xFF7FAE, 0x7EDC7A]   // 40 cup outward to 10
    static let lip: UInt32 = 0xFFFAF0
    static let hole: UInt32 = 0x2A1D33
    static let felt: UInt32 = 0x6C5BD8

    public init(table: Table = .standard) {
        world = World(table: table)
        let r = CGFloat(world.ballRadius)
        let ballGeo = SCNSphere(radius: r)
        ballGeo.segmentCount = 48
        ballGeo.materials = [Toon.material(Textures.ball)]
        ball = SCNNode(geometry: ballGeo)
        Toon.outline(ball, thick: 0.03)
        let blob = SCNPlane(width: CGFloat(world.ballRadius) * 2.6, height: CGFloat(world.ballRadius) * 2.6)
        let bm = SCNMaterial()
        bm.lightingModel = .constant
        bm.diffuse.contents = Textures.blob
        bm.writesToDepthBuffer = false
        bm.blendMode = .alpha
        blob.materials = [bm]
        shadow = SCNNode(geometry: blob)
        shadow.castsShadow = false
        shadow.renderingOrder = 5
        build()
    }

    func build() {
        scene.background.contents = hex(Self.backdrop)
        let root = scene.rootNode
        let w = world
        let laneW = Float(w.table.lane.width)

        // Floor and a back wall so the cabinet stands somewhere.
        let floor = SCNFloor(); floor.reflectivity = 0
        floor.materials = [Toon.material(hex(0xE7B8D9))]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = v3(0, -0.45, 0)
        root.addChildNode(floorNode)

        // Lane: one textured slab at the incline.
        let laneNode = SCNNode()
        laneNode.simdPosition = w.lane(x: 0, s: w.table.lane.length / 2) - w.laneNormal * 0.025
        laneNode.simdEulerAngles.x = w.incline
        let slab = SCNBox(width: CGFloat(laneW), height: 0.05, length: CGFloat(w.laneLength), chamferRadius: 0.012)
        let top = Toon.material(Textures.lane)
        // The box's top face runs its v from the far end; the texture is
        // drawn with the hinge at the top, so flip v about the centre.
        top.diffuse.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(1, -1, 1), SCNMatrix4MakeTranslation(0, 1, 0))
        let side = kit.mat(0xE7B57A)
        slab.materials = [side, side, side, side, top, side]   // front right back left top bottom
        laneNode.geometry = slab
        Toon.outline(laneNode, thick: 0.02)
        root.addChildNode(laneNode)

        // Rails along both sides, and the cabinet body underneath.
        for sx: Float in [-1, 1] {
            let rail = kit.part(Geo.box, Self.rail, scale: v3(0.07, 0.11, w.laneLength + 0.1), parent: laneNode, outline: 0.03)
            rail.position = v3(sx * (laneW / 2 + 0.035), 0.04, 0)
            let cap = kit.part(Geo.box, Self.railDark, scale: v3(0.08, 0.025, w.laneLength + 0.12), parent: laneNode, outline: 0.03)
            cap.position = v3(sx * (laneW / 2 + 0.035), 0.1, 0)
        }
        let body = kit.part(Geo.box, Self.cabinet, scale: v3(laneW + 0.2, 0.42, w.laneLength + 0.1), parent: laneNode, outline: 0.03)
        body.position = v3(0, -0.24, 0)

        // The hump: a rounded ridge across the lane at the hinge.
        let hump = kit.part(Geo.cylinder, 0xFFD27A, scale: v3(0.09, laneW, 0.09), parent: root, outline: 0.03)
        hump.simdPosition = w.lane(x: 0, s: w.table.lane.length) + w.laneNormal * (w.humpHeight - 0.045)
        hump.eulerAngles = v3(0, 0, Float.pi / 2)

        buildBoard()
        // The slot reels live in the HUD: in portrait there is no room for a
        // marquee above a readable target with the hump on the crease.
        buildTrough()

        // Lights and camera.
        _ = makeSun(in: scene, target: v3(0, 0.3, -1.6), span: 3.2)
        let cam = SCNCamera()
        cam.fieldOfView = 58
        cam.projectionDirection = .vertical
        cam.zNear = 0.05; cam.zFar = 30
        cam.wantsHDR = false
        camera.camera = cam
        camera.position = v3(0, 0.95, 0.42)
        camera.look(at: v3(0, 0.12, -1.05))
        root.addChildNode(camera)

        ball.simdPosition = w.lane(x: 0, s: 0.15) + w.laneNormal * w.ballRadius
        root.addChildNode(shadow)
        root.addChildNode(ball)
        buildBulbs()
    }

    func buildBoard() {
        let w = world, b = w.table.board
        board.simdPosition = w.boardOrigin
        board.simdEulerAngles.x = w.boardTilt - .pi / 2   // local +y up the board, +z out of it
        board.simdScale = SIMD3(repeating: w.boardScale)
        scene.rootNode.addChildNode(board)
        let bw = Float(b.width), bh = Float(b.height)

        // Backing panel.
        let panel = kit.part(Geo.box, Self.felt, scale: v3(bw + 0.02, bh + 0.02, 0.05), parent: board, outline: 0.03)
        panel.position = v3(0, bh / 2, -0.026)

        // Concentric ring zones, painted, outermost first; then raised lips.
        let c = b.ringCenter
        for (i, wall) in b.ringWalls.enumerated().reversed() {
            let disc = SCNCylinder(radius: CGFloat(wall), height: 0.002)
            disc.radialSegmentCount = 96
            disc.materials = [kit.mat(Self.zones[i])]
            let n = SCNNode(geometry: disc)
            n.simdEulerAngles.x = .pi / 2
            n.position = v3(Float(c.x), Float(c.y), 0.001 + Float(3 - i) * 0.0004)
            n.castsShadow = false
            board.addChildNode(n)
        }
        // Ring lips: rounded rails, cut at the bottom where the holes sit,
        // so the column of holes reads as a channel through the rings.
        for wall in b.ringWalls {
            let gapHalf = asin(min(0.95, Float(b.ringHoleVisual + 0.006) / Float(wall)))
            let g = Shapes.lipArc(ring: Float(wall), tube: 0.0085, height: Float(b.lipHeight),
                                  gapAt: -.pi / 2, gapHalf: gapHalf)
            g.materials = [kit.mat(Self.lip)]
            let n = SCNNode(geometry: g)
            n.position = v3(Float(c.x), Float(c.y), 0)
            Toon.outline(n, thick: 0.022)
            board.addChildNode(n)
        }

        // A hole in every ring, plus the 50 and the two pockets.
        for hole in Hole.allCases where hole != .gutter {
            let p = b.holeCenter(hole)
            let special = hole.isPocket || hole == .ring50
            let radius: Float = hole.isPocket ? Float(b.pockets[0].radius) + 0.004
                : (hole == .ring50 ? Float(b.centerHoleRadius) + 0.004 : Float(b.ringHoleVisual))
            // The pit: a dark disc shaded darker toward the middle, reads as depth.
            let pit = SCNCylinder(radius: CGFloat(radius), height: 0.002)
            pit.radialSegmentCount = 48
            let pm = Toon.material(Textures.pit)
            pit.materials = [kit.mat(Self.hole), pm, kit.mat(Self.hole)]
            let pn = SCNNode(geometry: pit)
            pn.simdEulerAngles.x = .pi / 2
            pn.position = v3(Float(p.x), Float(p.y), 0.004)
            pn.castsShadow = false
            board.addChildNode(pn)
            // The rim: a bright ring around the pit.
            let rim = SCNTorus(ringRadius: CGFloat(radius + 0.003), pipeRadius: 0.0055)
            rim.ringSegmentCount = 64; rim.pipeSegmentCount = 10
            rim.materials = [kit.mat(special ? 0xFFC94D : 0xFFF8EC)]
            let rn = SCNNode(geometry: rim)
            rn.simdEulerAngles.x = .pi / 2
            rn.position = v3(Float(p.x), Float(p.y), 0.006)
            Toon.outline(rn, thick: 0.02)
            board.addChildNode(rn)

            // Number badge on one side, symbol plate on the other.
            let side: Float = hole == .pocketRight ? 1 : -1
            let badge = SCNBox(width: 0.062, height: 0.034, length: 0.01, chamferRadius: 0.012)
            let bm = Toon.material(Textures.badge("\(hole.faceValue)", special: special))
            let edge = kit.mat(special ? 0xFFC94D : 0xFFF8EC)
            badge.materials = [bm, edge, edge, edge, edge, edge]
            let bn = SCNNode(geometry: badge)
            bn.position = v3(Float(p.x) + side * (radius + 0.042), Float(p.y), 0.008)
            Toon.outline(bn, thick: 0.016)
            board.addChildNode(bn)

        }

        buildRingReels()

        // Side walls and backwall.
        for sx: Float in [-1, 1] {
            let wall = kit.part(Geo.box, Self.rail, scale: v3(0.04, bh + 0.04, 0.16), parent: board, outline: 0.03)
            wall.position = v3(sx * (bw / 2 + 0.02), bh / 2, 0.06)
        }
        let back = kit.part(Geo.box, Self.railDark, scale: v3(bw + 0.08, 0.05, 0.18), parent: board, outline: 0.03)
        back.position = v3(0, bh + 0.02, 0.07)
    }

    func buildMarquee() {
        let w = world
        let top = w.board(Vec2(0, w.table.board.height + 0.02), z: 0.1)
        let marquee = SCNNode()
        marquee.simdPosition = top + SIMD3(0, 0.15, 0)
        marquee.simdEulerAngles.x = -0.2
        scene.rootNode.addChildNode(marquee)
        kit.part(Geo.box, Self.cabinet, scale: v3(0.86, 0.36, 0.08), parent: marquee, outline: 0.03)
        marqueeTop = marquee.simdPosition + SIMD3(0, 0.18, 0)
        let title = SCNPlane(width: 0.74, height: 0.18)
        let tm = Toon.material(Textures.marqueeTitle()); tm.transparencyMode = .aOne
        title.materials = [tm]
        let tn = SCNNode(geometry: title)
        tn.position = v3(0, 0.1, 0.042)
        marquee.addChildNode(tn)
        for i in 0..<3 {
            let reel = SCNBox(width: 0.13, height: 0.11, length: 0.03, chamferRadius: 0.012)
            let face = Toon.material(Textures.plate(.blank))
            let edge = kit.mat(0xFFF8EC)
            reel.materials = [face, edge, edge, edge, edge, edge]
            let n = SCNNode(geometry: reel)
            n.position = v3(Float(i - 1) * 0.15, -0.06, 0.045)
            Toon.outline(n, thick: 0.02)
            marquee.addChildNode(n)
            reels.append(n)
        }
    }

    /// Ball return: a channel beside the near end of the lane where the
    /// balls you have left wait in a row.
    func buildTrough() {
        let w = world
        let laneW = Float(w.table.lane.width)
        // Return channel across the cabinet front, below the release line.
        let trough = kit.part(Geo.box, Self.railDark, scale: v3(laneW + 0.12, 0.035, 0.09), parent: scene.rootNode, outline: 0.03)
        trough.simdPosition = w.lane(x: 0, s: -0.2) + SIMD3(0, -0.06, 0.02)
        for i in 0..<12 {
            let g = SCNSphere(radius: CGFloat(w.ballRadius)); g.segmentCount = 32
            g.materials = [Toon.material(Textures.ball)]
            let n = SCNNode(geometry: g)
            Toon.outline(n, thick: 0.03)
            n.simdPosition = trough.simdPosition + SIMD3(laneW / 2 + 0.02 - Float(i) * 0.062, 0.045, 0)
            n.eulerAngles = v3(Float(i) * 0.7, Float(i) * 1.3, 0)
            scene.rootNode.addChildNode(n)
            waiting.append(n)
        }
    }

    /// A row of bulbs over the target and down both side walls.
    func buildBulbs() {
        let b = world.table.board
        let bw = Float(b.width), bh = Float(b.height)
        var spots: [SIMD3<Float>] = []
        for i in 0..<9 { spots.append(SIMD3(-bw / 2 + bw * Float(i) / 8, bh + 0.05, 0.14)) }
        for i in 0..<7 {
            let y = bh * Float(i) / 6
            spots.append(SIMD3(-bw / 2 - 0.02, y, 0.15)); spots.append(SIMD3(bw / 2 + 0.02, y, 0.15))
        }
        for (i, p) in spots.enumerated() {
            let g = SCNSphere(radius: 0.012); g.segmentCount = 16
            let m = Toon.material(hex(i % 2 == 0 ? 0xFFF1A8 : 0xFF9EC4), emission: hex(0x000000))
            g.materials = [m]
            let n = SCNNode(geometry: g)
            n.simdPosition = p
            Toon.outline(n, thick: 0.02)
            board.addChildNode(n)
            bulbs.append(n)
        }
    }

    /// Light bulbs in a chase: `phase` steps the pattern, `level` 0...1.
    public func lightBulbs(phase: Int, level: Float) {
        for (i, n) in bulbs.enumerated() {
            let on = (i + phase) % 3 == 0
            n.geometry?.firstMaterial?.emission.contents = on && level > 0
                ? PlatformColor(white: CGFloat(level), alpha: 1) : PlatformColor.black
        }
    }

    /// Symbols around each ring band: the ring is the reel. Big, repeated,
    /// upright, so they read from the far end of the alley.
    func buildRingReels() {
        let b = world.table.board, c = b.ringCenter, w = b.ringWalls
        func reel(_ hole: Hole, center: SIMD2<Float>, radius: Float, count: Int, size: Float,
                  phase: Float = .pi / 2, band: (Double, Double)) {
            let pivot = SCNNode()
            pivot.simdPosition = SIMD3(center.x, center.y, 0.006)
            board.addChildNode(pivot)
            let tube = SCNTube(innerRadius: CGFloat(band.0), outerRadius: CGFloat(band.1), height: 0.001)
            tube.radialSegmentCount = 96
            let hm = SCNMaterial()
            hm.lightingModel = .constant
            hm.diffuse.contents = hex(0xFFF6B0)
            hm.blendMode = .add
            hm.writesToDepthBuffer = false
            tube.materials = [hm]
            let halo = SCNNode(geometry: tube)
            halo.simdEulerAngles.x = .pi / 2
            // Pocket symbols hover above their pocket; the halo rings the pocket.
            halo.simdPosition = SIMD3(center.x, hole.isPocket ? center.y - 0.07 : center.y, 0.0035)
            halo.opacity = 0
            halo.renderingOrder = 4
            board.addChildNode(halo)
            var decals: [SCNNode] = []
            for _ in 0..<count {
                let g = SCNPlane(width: CGFloat(size), height: CGFloat(size))
                let m = Toon.material(Textures.symbol(.blank))
                m.transparencyMode = .aOne
                m.isDoubleSided = false
                g.materials = [m]
                let n = SCNNode(geometry: g)
                n.castsShadow = false
                pivot.addChildNode(n)
                decals.append(n)
            }
            reelsOnBoard[hole] = RingReel(pivot: pivot, decals: decals, radius: radius, phase: phase, halo: halo)
        }
        let cc = SIMD2(Float(c.x), Float(c.y))
        reel(.ring10, center: cc, radius: Float(w[2] + w[3]) / 2, count: 10, size: 0.058, band: (w[2] + 0.008, w[3] - 0.008))
        reel(.ring20, center: cc, radius: Float(w[1] + w[2]) / 2, count: 8, size: 0.054, band: (w[1] + 0.008, w[2] - 0.008))
        reel(.ring30, center: cc, radius: Float(w[0] + w[1]) / 2, count: 6, size: 0.052, band: (w[0] + 0.008, w[1] - 0.008))
        reel(.ring40, center: cc, radius: Float(w[0]) * 0.62, count: 2, size: 0.046, phase: 0, band: (0.0, w[0] - 0.008))
        let fifty = b.holeCenter(.ring50)
        reel(.ring50, center: SIMD2(Float(fifty.x), Float(fifty.y)), radius: 0, count: 1, size: 0.05,
             band: (b.centerHoleRadius + 0.008, b.centerHoleRadius + 0.02))
        for p in [Hole.pocketLeft, .pocketRight] {
            let pc = b.holeCenter(p)
            reel(p, center: SIMD2(Float(pc.x), Float(pc.y) + 0.07), radius: 0, count: 1, size: 0.06,
                 band: (b.pockets[0].radius + 0.008, b.pockets[0].radius + 0.022))
        }
    }

    /// Show `symbol` on a hole's reel. `turn` is how far the reel has
    /// spun (in symbols, fractional while spinning); `glow` 0...2 lights it
    /// (1 = would pair, 2 = would complete the line).
    public func setReel(_ hole: Hole, _ symbol: Symbol, turn: Double, glow: Float, pulse: Float) {
        guard let r = reelsOnBoard[hole] else { return }
        let n = r.decals.count
        let spin = Float(turn) * 2 * .pi / Float(max(n, 3))
        for (i, d) in r.decals.enumerated() {
            let a = Float(i) / Float(n) * 2 * .pi + r.phase + spin
            d.simdPosition = SIMD3(r.radius * cos(a), r.radius * sin(a), 0)
            // Hide the ones passing through the hole channel at the bottom.
            let bottom = abs(atan2(sin(a + .pi / 2), cos(a + .pi / 2))) < 0.75
            d.isHidden = r.radius > 0 && bottom
            if r.radius == 0 { d.simdPosition.y = 0; d.simdScale = SIMD3(repeating: 1 + 0.25 * glow * pulse) }
            else { d.simdScale = SIMD3(repeating: 1 + 0.18 * glow * pulse) }
            let m = d.geometry!.firstMaterial!
            if r.shown != symbol { m.diffuse.contents = Textures.symbol(symbol) }
            m.emission.contents = glow > 0
                ? PlatformColor(red: CGFloat(0.55 * pulse), green: CGFloat((glow > 1 ? 0.45 : 0.3) * pulse), blue: CGFloat(glow > 1 ? 0 : 0.25 * pulse), alpha: 1)
                : PlatformColor.black
        }
        r.halo.opacity = CGFloat(glow > 0 ? (glow > 1 ? 0.75 : 0.45) * pulse : 0)
        r.halo.geometry?.firstMaterial?.diffuse.contents = hex(glow > 1 ? 0xFFD84D : 0xFFF6B0)
        reelsOnBoard[hole]?.shown = symbol
    }

    public func setReel(_ i: Int, _ symbol: Symbol?) {
        guard reels.indices.contains(i) else { return }
        reels[i].geometry?.materials[0].diffuse.contents = Textures.plate(symbol ?? .blank, lit: symbol != nil)
    }

    public func setWaiting(_ n: Int) {
        for (i, b) in waiting.enumerated() { b.isHidden = i >= n }
    }
}
