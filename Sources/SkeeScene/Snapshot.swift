import Metal
import SceneKit
import SkeeCore

/// Offscreen render of a cabinet, for the CLI and tests. Same scene, same
/// shaders as the app's SCNView.
@MainActor
public func snapshot(_ cab: Cabinet, size: CGSize, time: TimeInterval = 0) -> CGImage? {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    let r = SCNRenderer(device: device, options: nil)
    r.scene = cab.scene
    r.pointOfView = cab.camera
    r.isJitteringEnabled = false
    let img = r.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
    #if canImport(UIKit)
    return img.cgImage
    #else
    return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    #endif
}

/// A look-at camera as plain numbers, so framing can be solved without
/// touching SceneKit nodes.
public struct CameraRig: Hashable, Sendable {
    public var position: SIMD3<Float>
    public var target: SIMD3<Float>
    public var fov: Float   // vertical, degrees

    /// Where a world point lands on screen (0...1, y down).
    public func project(_ p: SIMD3<Float>, aspect: Float) -> SIMD2<Float> {
        let f = simd_normalize(target - position)
        let r = simd_normalize(simd_cross(f, SIMD3(0, 1, 0)))
        let u = simd_cross(r, f)
        let d = p - position
        let z = simd_dot(d, f)
        let t = tan(fov * .pi / 360)
        return SIMD2((simd_dot(d, r) / (z * t * aspect) + 1) / 2, (1 - simd_dot(d, u) / (z * t)) / 2)
    }
}

extension Cabinet {
    /// Near end of the lane, the hump, and the top of the target board.
    public var framingPoints: (near: SIMD3<Float>, hump: SIMD3<Float>, top: SIMD3<Float>) {
        (world.lane(x: 0, s: -0.05), world.lane(x: 0, s: world.table.lane.length), world.board(Vec2(0, world.table.board.height + 0.06)))
    }

    /// Solve for a camera that puts the near end of the lane, the hump and
    /// the top of the marquee at the given screen heights. The hump has to
    /// sit on the Duo's crease, so it is weighted most.
    public static func fit(points: (near: SIMD3<Float>, hump: SIMD3<Float>, top: SIMD3<Float>), aspect: Float,
                           near: Float = 0.84, hump: Float = 0.5, top: Float = 0.23) -> CameraRig {
        var best = (Float.infinity, CameraRig(position: .zero, target: .zero, fov: 60))
        for fov in stride(from: Float(22), through: 70, by: 2) {
            for h in stride(from: Float(0.55), through: 1.0, by: 0.025) {
                for z in stride(from: Float(-0.2), through: 3.0, by: 0.05) {
                    for look in stride(from: Float(-1.8), through: Float(-0.2), by: 0.05) {
                        let rig = CameraRig(position: SIMD3(0, h, z), target: SIMD3(0, points.hump.y, look), fov: fov)
                        let a = rig.project(points.near, aspect: aspect).y
                        let b = rig.project(points.hump, aspect: aspect).y
                        let c = rig.project(points.top, aspect: aspect).y
                        // Prefer narrower lenses: flatter perspective keeps
                        // the far target readable next to the near lane.
                        let err = (a - near) * (a - near) + 8 * (b - hump) * (b - hump) + (c - top) * (c - top) + fov * 0.00002
                        if err < best.0 { best = (err, rig) }
                    }
                }
            }
        }
        return best.1
    }

    public func apply(_ rig: CameraRig) {
        camera.camera!.fieldOfView = CGFloat(rig.fov)
        camera.simdPosition = rig.position
        camera.simdLook(at: rig.target)
    }

    public func fitCamera(size: CGSize) {
        apply(Self.fit(points: framingPoints, aspect: Float(size.width / size.height)))
    }
}
