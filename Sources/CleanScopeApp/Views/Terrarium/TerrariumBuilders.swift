import AppKit
import CleanScopeCore
import SceneKit

/// Geometry and materials for `TerrariumScene`, ported from the concept board's terrarium
/// (`/* A: Terrarium */`). Positions are in board units; the plinth top sits at `base`.
@MainActor
enum TerrariumBuilders {
  typealias G = IconGeometry

  /// Height of the plinth's top face (the board's `BASE`).
  static let base = -1.4
  static let layerRadius = 1.8
  static let leafCount = 170
  /// Where the lens rests beside the dome, and the radius of its scanning orbit.
  static let parkedLens = SCNVector3(-2.75, 0.35, 0.9)
  static let orbitRadius = 2.75

  static func color(for kind: TerrariumLayer.Kind) -> UInt32 {
    switch kind {
    case .system: return 0x4A3B30
    case .personal: return 0x6E5440
    case .appData: return 0x8E6B48
    case .review: return 0xB98B46
    case .safe: return 0x9DB86C
    }
  }

  static let leafPalette: [UInt32] = [0xD9894F, 0xE6B35A, 0x9DB86C, 0xC56B4A, 0xB8C46A]

  static func clay(
    _ hex: UInt32, roughness: Double, clearCoat: Double = 0.55
  ) -> SCNMaterial {
    let material = G.clay(hex)
    material.roughness.contents = NSNumber(value: roughness)
    material.clearCoat.contents = NSNumber(value: clearCoat)
    return material
  }

  // MARK: - Fixed parts

  static func camera() -> SCNNode {
    let node = SCNNode()
    let camera = SCNCamera()
    camera.fieldOfView = 30
    camera.projectionDirection = .vertical
    camera.zNear = 0.1
    camera.zFar = 100
    // The board renders through ACES tone mapping, which mutes the clay colours; HDR with a
    // softer white point and a little less saturation lands on the reference's tones.
    camera.wantsHDR = true
    camera.wantsExposureAdaptation = false
    camera.whitePoint = 2
    camera.exposureOffset = 0.2
    camera.saturation = 0.8
    node.camera = camera
    node.position = SCNVector3(0, 2.1, 10.4)
    node.look(at: SCNVector3(0, -0.55, 0))
    return node
  }

  static func keyLight() -> SCNNode {
    let node = SCNNode()
    let light = SCNLight()
    light.type = .directional
    light.color = G.color(0xFFF0D8)
    light.intensity = 1900
    node.light = light
    node.position = SCNVector3(-3, 5, 4)
    node.look(at: SCNVector3(0, 0, 0))
    return node
  }

  static func plinth() -> SCNNode {
    let geometry = SCNCone(topRadius: 2.36, bottomRadius: 2.5, height: 0.42)
    geometry.radialSegmentCount = 96
    geometry.materials = [clay(G.Palette.bark, roughness: 0.6)]
    let node = SCNNode(geometry: geometry)
    node.position = SCNVector3(0, base - 0.21, 0)
    return node
  }

  static func rim() -> SCNNode {
    let geometry = SCNTorus(ringRadius: 2.17, pipeRadius: 0.055)
    geometry.ringSegmentCount = 128
    geometry.pipeSegmentCount = 16
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.diffuse.contents = G.color(G.Palette.gold)
    material.metalness.contents = NSNumber(value: 0.9)
    material.roughness.contents = NSNumber(value: 0.25)
    geometry.materials = [material]
    let node = SCNNode(geometry: geometry)
    node.position = SCNVector3(0, base, 0)
    return node
  }

  /// The glass dome: an open hemisphere of radius 2.16 on the rim, physically based, drawn after
  /// the soil without writing depth.
  ///
  /// SceneKit draws a physically based material with a uniform `transparency` of 0.12 fully
  /// opaque, and a 12% white veil blended in linear space washes the soil out, so the glass is a
  /// shader instead: a black (non-diffuse) dielectric whose own reflections add light, a Fresnel
  /// rim (exponent 1.8) that is clear face-on and frosted at grazing angles, a thin darker
  /// silhouette, and three soft window glints standing in for the board's room reflections.
  static func dome() -> SCNNode {
    let geometry = hemisphere(radius: 2.16, segments: 96, rings: 48)
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    // Alpha just under 1 makes SceneKit blend the dome; the shader sets the real coverage.
    material.diffuse.contents = NSColor(white: 0, alpha: 0.99)
    material.roughness.contents = NSNumber(value: 0.05)
    material.metalness.contents = NSNumber(value: 0.0)
    material.fresnelExponent = domeFresnelExponent
    material.writesToDepthBuffer = false
    material.shaderModifiers = [.fragment: domeShader]
    material.setValue(NSNumber(value: Double(domeFresnelExponent)), forKey: "rimExponent")
    geometry.materials = [material]
    let node = SCNNode(geometry: geometry)
    node.position = SCNVector3(0, base, 0)
    node.renderingOrder = 100
    return node
  }

  static let domeFresnelExponent: CGFloat = 1.8

  /// Premultiplied output: the material's reflections plus a light Fresnel rim and glints, with
  /// coverage from the rim and glints only, so the dome is see-through face-on.
  private static let domeShader = """
    #pragma arguments
    float rimExponent;
    #pragma body
    float3 n = normalize(_surface.normal);
    float facing = abs(dot(n, _surface.view));
    float rim = pow(1.0 - facing, rimExponent);
    float edge = pow(1.0 - facing, 5.0);
    float glint = smoothstep(0.975, 0.995, dot(n, normalize(float3(-0.55, 0.40, 0.73))))
      + 0.7 * smoothstep(0.985, 0.998, dot(n, normalize(float3(0.50, 0.50, 0.71))))
      + 0.5 * smoothstep(0.994, 0.9995, dot(n, normalize(float3(-0.12, -0.08, 0.99))));
    float a = saturate(rim * 0.45 + edge * 0.35 + glint * 0.75);
    float3 color = _output.color.rgb + float3(0.82, 0.82, 0.80) * rim * 0.45 + glint * 0.75;
    color = mix(min(color, float3(4.0)), float3(0.12, 0.11, 0.10) * a, edge * 0.85);
    _output.color = float4(color, a);
    """

  /// The upper half of a UV sphere, open at the bottom, with outward normals.
  private static func hemisphere(radius: Double, segments: Int, rings: Int) -> SCNGeometry {
    var vertices: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var indices: [UInt32] = []
    for ring in 0...rings {
      let theta = Double(ring) / Double(rings) * Double.pi / 2
      for segment in 0...segments {
        let phi = Double(segment) / Double(segments) * 2 * Double.pi
        let normal = SCNVector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
        normals.append(normal)
        vertices.append(
          SCNVector3(normal.x * radius, normal.y * radius, normal.z * radius))
      }
    }
    let row = UInt32(segments + 1)
    for ring in 0..<UInt32(rings) {
      for segment in 0..<UInt32(segments) {
        let a = ring * row + segment
        let b = a + row
        indices += [a, a + 1, b, b, a + 1, b + 1]
      }
    }
    return SCNGeometry(
      sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
      elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
  }

  /// One soil layer: a unit-height cylinder scaled to the layer's height.
  static func layer(_ kind: TerrariumLayer.Kind) -> SCNNode {
    let geometry = SCNCylinder(radius: layerRadius, height: 1)
    geometry.radialSegmentCount = 96
    let material = clay(color(for: kind), roughness: 0.75, clearCoat: 0.1)
    material.emission.contents = G.color(color(for: kind))
    material.emission.intensity = 0
    geometry.materials = [material]
    return SCNNode(geometry: geometry)
  }

  // MARK: - Leaf litter

  struct Leaf {
    let node: SCNNode
    let scale: Double
    /// Seconds into the board's 1.6 s compost before this leaf starts to shrink.
    let delay: Double
  }

  /// 170 leaves on the top layer, placed by a fixed-seed generator so every terrarium (and every
  /// snapshot) looks the same. Five geometries, one per palette colour, share one extrusion.
  static func litter(in parent: SCNNode) -> [Leaf] {
    let shape = G.extrusion(G.leafShape(0.2, 0.1), depth: 0.025, bevel: 0.008)
    let (minimum, maximum) = shape.boundingBox
    let pivot = SCNMatrix4MakeTranslation(
      (minimum.x + maximum.x) / 2, (minimum.y + maximum.y) / 2, (minimum.z + maximum.z) / 2)
    let geometries = leafPalette.map { hex -> SCNGeometry in
      let copy = shape.copy() as? SCNGeometry ?? shape
      copy.materials = [clay(hex, roughness: 0.6)]
      return copy
    }
    var random = SeededRandom(seed: 0x7E77A)
    return (0..<leafCount).map { index in
      let r = random.next().squareRoot() * 1.68
      let a = random.next() * 2 * Double.pi
      let ry = random.next() * 6.28
      let rx = -Double.pi / 2 + (random.next() - 0.5) * 0.6
      let scale = 0.8 + random.next() * 0.6
      let delay = random.next() * 0.8
      let node = SCNNode(geometry: geometries[index % geometries.count])
      node.pivot = pivot
      node.position = SCNVector3(cos(a) * r, 0, sin(a) * r)
      node.eulerAngles = SCNVector3(rx, ry, 0)
      node.scale = SCNVector3(scale, scale, scale)
      parent.addChildNode(node)
      return Leaf(node: node, scale: scale, delay: delay)
    }
  }

  // MARK: - Sprout and lens

  /// The sprout's stem and three leaves (the third appears from growth stage 2).
  static func sprout(in parent: SCNNode) -> [SCNNode] {
    G.sprout(
      parent, stem: (0.045, 0.55, 0.3),
      leafGeometry: G.extrusion(G.leafShape(0.42, 0.2), depth: 0.04, bevel: 0.015),
      leaves: [(0.42, 0.36, 0.55), (0.42, 0.5, Double.pi - 0.5), (0.36, 0.62, 0.9)])
  }

  /// The Sprout Lens, facing the camera, tipped 0.25 rad like the board's parked lens.
  static func lens() -> SCNNode {
    let node = SCNNode()
    let face = SCNNode()
    face.eulerAngles.z = 0.25
    node.addChildNode(face)
    G.lens(
      face, ring: 0.42, tube: 0.075, segments: (24, 72), disc: 0.4, discDepth: 0.03,
      handle: (0.08, 0.34, (0.37, -0.37, 0)))
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = .all
    node.constraints = [billboard]
    return node
  }
}

/// SplitMix64: a tiny deterministic generator for the litter placement.
struct SeededRandom {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  /// A uniform value in 0..<1.
  mutating func next() -> Double {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Double(z >> 11) / Double(1 << 53)
  }
}
