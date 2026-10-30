import SceneKit
#if canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
#else
import AppKit
public typealias PlatformColor = NSColor
#endif

// Cel-shading kit, ported from whats_going_through_your_mind/engine/render/toon.js
// (three.js) to SceneKit shader modifiers:
//
//   toonRamp()        3-band gradient [150, 205, 255]   -> lighting-model modifier
//   HemisphereLight   sky fff4fb / ground d9c8ff, 1.6   -> fragment modifier
//   RIM               smoothstep(0.62, 0.68, rim) * .28 -> fragment modifier
//   uDesat / uTint    per-material grey-out and tint    -> fragment arguments
//   outlineMaterial   inverted hull, back faces, grown
//                     with distance for steady width    -> geometry modifier
//   ToonKit.part      shared unit primitives, scaled    -> ToonKit.part
//
// three.js lights are not multiplied by pi; its Lambert BRDF divides by pi.
// The constants below fold that in so the same light intensities (sun 2.2,
// hemisphere 1.6) give the same brightness.

/// SceneKit vectors are CGFloat on macOS and Float on iOS; build them from
/// Float everywhere through simd.
public func v3(_ x: Float, _ y: Float, _ z: Float) -> SCNVector3 { SCNVector3(SIMD3<Float>(x, y, z)) }
public func v4(_ x: Float, _ y: Float, _ z: Float, _ w: Float) -> SCNVector4 { SCNVector4(SIMD4<Float>(x, y, z, w)) }

public func hex(_ v: UInt32, alpha: CGFloat = 1) -> PlatformColor {
    PlatformColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}

public enum Toon {
    /// Ink colour for every outline.
    public static let ink: UInt32 = 0x3A2346
    public static let sky: UInt32 = 0xFFF4FB
    public static let ground: UInt32 = 0xD9C8FF
    public static let sunIntensity: Float = 2.2
    public static let hemiIntensity: Float = 1.6

    /// Per light: the toon ramp. Bright shadow bands keep pastels pastel; a
    /// dark ramp turns them muddy. `_light.intensity` already carries
    /// SceneKit's shadow term, as three.js multiplies shadow into the light
    /// colour before the ramp.
    static let lighting = """
    #pragma arguments
    float uSun;
    #pragma body
    float dotNL = dot(_surface.normal, _light.direction);
    float u = dotNL * 0.5 + 0.5;
    float band = u < (1.0 / 3.0) ? (150.0 / 255.0) : (u < (2.0 / 3.0) ? (205.0 / 255.0) : 1.0);
    _lightingContribution.diffuse += band * _light.intensity.rgb * uSun * 0.31831;
    """

    /// After lighting: hemisphere fill, the hard rim band, desaturate, tint.
    static let fragment = """
    #pragma arguments
    float uHemi;
    float3 uSky;
    float3 uGround;
    float uDesat;
    float4 uTint;
    #pragma body
    float3 nView = normalize(_surface.normal);
    float3 nWorld = normalize((scn_frame.inverseViewTransform * float4(nView, 0.0)).xyz);
    float3 hemi = mix(uGround, uSky, nWorld.y * 0.5 + 0.5);
    float3 outgoing = _output.color.rgb + _surface.diffuse.rgb * hemi * uHemi * 0.31831;
    float3 viewDir = normalize(-_surface.position);
    float rimF = 1.0 - max(dot(viewDir, nView), 0.0);
    outgoing += float3(1.0, 0.96, 1.0) * smoothstep(0.62, 0.68, rimF) * 0.28;
    float lum = dot(outgoing, float3(0.299, 0.587, 0.114));
    outgoing = mix(outgoing, float3(lum) * float3(0.92, 0.9, 0.95), uDesat);
    outgoing = mix(outgoing, uTint.rgb * (0.35 + lum * 0.8), uTint.a);
    _output.color.rgb = outgoing;
    """

    /// Inverted hull: push back faces out along the view-space normal, more
    /// with distance, so the line holds a steady screen width.
    static let outlineGeometry = """
    #pragma arguments
    float uThick;
    #pragma body
    float4 mv = scn_node.modelViewTransform * _geometry.position;
    float3 n = normalize((scn_node.normalTransform * float4(_geometry.normal, 0.0)).xyz);
    mv.xyz += n * uThick * (-mv.z / 20.0);
    _geometry.position = scn_node.inverseModelViewTransform * mv;
    """

    static func vec(_ c: UInt32) -> SCNVector3 {
        v3(Float((c >> 16) & 0xFF) / 255, Float((c >> 8) & 0xFF) / 255, Float(c & 0xFF) / 255)
    }

    /// A toon material. `color` may also be an image (a texture).
    public static func material(_ color: Any, emission: PlatformColor? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = color
        m.ambient.contents = PlatformColor.black
        if let emission { m.emission.contents = emission }
        m.shaderModifiers = [.lightingModel: lighting, .fragment: fragment]
        m.setValue(NSNumber(value: sunIntensity), forKey: "uSun")
        m.setValue(NSNumber(value: hemiIntensity), forKey: "uHemi")
        m.setValue(NSValue(scnVector3: vec(sky)), forKey: "uSky")
        m.setValue(NSValue(scnVector3: vec(ground)), forKey: "uGround")
        m.setValue(NSNumber(value: 0), forKey: "uDesat")
        m.setValue(NSValue(scnVector4: v4(1, 0, 0, 0)), forKey: "uTint")
        return m
    }

    public static func setDesat(_ m: SCNMaterial, _ v: Float) { m.setValue(NSNumber(value: v), forKey: "uDesat") }
    public static func setTint(_ m: SCNMaterial, _ c: UInt32, _ amount: Float) {
        let v = SIMD3<Float>(vec(c))
        m.setValue(NSValue(scnVector4: v4(v.x, v.y, v.z, amount)), forKey: "uTint")
    }

    nonisolated(unsafe) private static var outlineCache: [String: SCNMaterial] = [:]

    public static func outlineMaterial(thick: Float = 0.035, color: UInt32 = ink) -> SCNMaterial {
        let key = "\(thick):\(color)"
        if let m = outlineCache[key] { return m }
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = hex(color)
        m.cullMode = .front
        m.shaderModifiers = [.geometry: outlineGeometry]
        m.setValue(NSNumber(value: thick), forKey: "uThick")
        outlineCache[key] = m
        return m
    }

    /// Add an ink outline child that shares the mesh's geometry.
    @discardableResult
    public static func outline(_ node: SCNNode, thick: Float = 0.035) -> SCNNode {
        guard let g = node.geometry else { return node }
        let shell = g.copy() as! SCNGeometry
        shell.materials = [outlineMaterial(thick: thick)]
        let o = SCNNode(geometry: shell)
        o.name = "outline"
        o.castsShadow = false
        node.addChildNode(o)
        return node
    }
}

/// Shared unit geometries; parts are scaled instances of these. Rounded box
/// so the inverted hull has smooth normals at the corners (sharp boxes crack).
public enum Geo {
    nonisolated(unsafe) static var cache: [String: SCNGeometry] = [:]
    static func shared(_ k: String, _ make: () -> SCNGeometry) -> SCNGeometry {
        if let g = cache[k] { return g }
        let g = make(); cache[k] = g; return g
    }
    public static var sphere: SCNGeometry { shared("sphere") { let s = SCNSphere(radius: 0.5); s.segmentCount = 32; return s } }
    public static var box: SCNGeometry { shared("box") { SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.12) } }
    public static var cylinder: SCNGeometry { shared("cylinder") { let c = SCNCylinder(radius: 0.5, height: 1); c.radialSegmentCount = 48; return c } }
    public static var capsule: SCNGeometry { shared("capsule") { SCNCapsule(capRadius: 0.5, height: 2) } }
    public static var cone: SCNGeometry { shared("cone") { SCNCone(topRadius: 0, bottomRadius: 0.5, height: 1) } }
    public static var torus: SCNGeometry { shared("torus") { let t = SCNTorus(ringRadius: 0.5, pipeRadius: 0.18); t.ringSegmentCount = 64; return t } }
}

/// Owns the materials of one model, so it can be tinted without tinting
/// every other model that shares its colours.
public final class ToonKit {
    var mats: [String: SCNMaterial] = [:]
    public private(set) var list: [SCNMaterial] = []

    public init() {}

    public func mat(_ color: UInt32) -> SCNMaterial {
        let k = String(color, radix: 16)
        if let m = mats[k] { return m }
        let m = Toon.material(hex(color))
        mats[k] = m; list.append(m)
        return m
    }

    /// part(.box, 0xffaacc, scale:, position:, euler:, parent:, outline:)
    @discardableResult
    public func part(_ geometry: SCNGeometry, _ color: UInt32, scale: SCNVector3 = v3(1, 1, 1),
                     position: SCNVector3 = v3(0, 0, 0), euler: SCNVector3 = v3(0, 0, 0),
                     parent: SCNNode? = nil, outline: Float? = 0.035, shadow: Bool = true, name: String? = nil) -> SCNNode {
        let g = geometry.copy() as! SCNGeometry
        g.materials = [mat(color)]
        let n = SCNNode(geometry: g)
        n.scale = scale; n.position = position; n.eulerAngles = euler
        n.castsShadow = shadow
        if let outline { Toon.outline(n, thick: outline) }
        n.name = name
        parent?.addChildNode(n)
        return n
    }

    public func tint(_ amount: Float, _ color: UInt32 = 0xFF0000) { for m in list { Toon.setTint(m, color, amount) } }
    public func desat(_ v: Float) { for m in list { Toon.setDesat(m, v) } }
}

/// three.js makeLights: hemisphere + a shadow-casting sun from (-0.45, 1, 0.25).
/// The hemisphere lives in the materials; this adds the sun.
public func makeSun(in scene: SCNScene, target: SCNVector3, span: Float = 4) -> SCNNode {
    let sun = SCNLight()
    sun.type = .directional
    sun.intensity = 1000
    sun.color = PlatformColor.white
    sun.castsShadow = true
    sun.shadowMode = .forward
    sun.shadowSampleCount = 8
    sun.shadowRadius = 1.5
    sun.shadowMapSize = CGSize(width: 2048, height: 2048)
    sun.orthographicScale = CGFloat(span)
    sun.automaticallyAdjustsShadowProjection = false
    sun.shadowBias = 0.02
    sun.shadowColor = PlatformColor(white: 0, alpha: 1)
    let node = SCNNode()
    node.light = sun
    let dir = simd_normalize(SIMD3<Float>(-0.45, 1, 0.25))
    let t = SIMD3<Float>(target)
    node.simdPosition = t + dir * 10
    node.simdLook(at: t)
    sun.zNear = 1; sun.zFar = 30
    scene.rootNode.addChildNode(node)
    return node
}
