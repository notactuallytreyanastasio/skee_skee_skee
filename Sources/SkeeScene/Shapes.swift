import SceneKit
import simd

/// Custom meshes the stock primitives don't cover.
public enum Shapes {
    /// A rounded rail swept around a circle of radius `ring`, with a gap
    /// centred at `gapAt` (radians, 0 = +x, -pi/2 = straight down the board).
    /// Tube cross-section of radius `tube`, sitting with its top at
    /// `height`. Smooth normals all round, so the ink hull draws clean.
    public static func lipArc(ring: Float, tube: Float, height: Float, gapAt: Float, gapHalf: Float,
                              segments: Int = 120, sides: Int = 12) -> SCNGeometry {
        var pos: [SIMD3<Float>] = [], nor: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        let a0 = gapAt + gapHalf, a1 = gapAt + 2 * .pi - gapHalf
        let zc = height - tube
        for i in 0...segments {
            let u = a0 + (a1 - a0) * Float(i) / Float(segments)
            for j in 0...sides {
                let v = 2 * Float.pi * Float(j) / Float(sides)
                let r = ring + tube * cos(v)
                pos.append(SIMD3(r * cos(u), r * sin(u), zc + tube * sin(v)))
                nor.append(SIMD3(cos(v) * cos(u), cos(v) * sin(u), sin(v)))
            }
        }
        let row = UInt32(sides + 1)
        for i in 0..<UInt32(segments) {
            for j in 0..<UInt32(sides) {
                let a = i * row + j, b = a + row
                idx += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        let src = [SCNGeometrySource(vertices: pos.map { SCNVector3($0) }),
                   SCNGeometrySource(normals: nor.map { SCNVector3($0) })]
        return SCNGeometry(sources: src, elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }
}

import SkeeCore

extension BoardSpec {
    /// Drawn radius of a ring hole: a touch bigger than the ball, so it
    /// visibly fits. The capture radius in the physics is separate.
    public var ringHoleVisual: Double { 0.033 }
}
