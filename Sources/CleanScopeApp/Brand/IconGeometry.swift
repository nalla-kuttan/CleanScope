import AppKit
import SceneKit

/// SceneKit builders shared by the app (the storage terrarium) and `script/render_icons.swift`
/// (the 3D module icons): the board palette and clay material, three.js-equivalent primitives,
/// bevelled extrusions, and the leaf, gear and polygon shapes. The script compiles this file
/// alongside itself, so it may import only AppKit and SceneKit and must stay deterministic.
enum IconGeometry {
  // MARK: - Palette and material

  enum Palette {
    static let forest: UInt32 = 0x2F6B57
    static let sage: UInt32 = 0x86AE8C
    static let leaf: UInt32 = 0x6CC48A
    static let mint: UInt32 = 0xDFF2E8
    static let cream: UInt32 = 0xF1E9DC
    static let bark: UInt32 = 0x6B5140
    static let amber: UInt32 = 0xE6B35A
    static let terra: UInt32 = 0xD9806A
    static let blue: UInt32 = 0x6E93BD
    static let gold: UInt32 = 0xDDB45E
    static let card: UInt32 = 0xC99F72
    static let chip: UInt32 = 0x2F4A3E
    static let tray: UInt32 = 0xD8CBB7
    static let flap: UInt32 = 0xB98D60
  }

  static func color(_ hex: UInt32, mixWhite amount: CGFloat = 0) -> NSColor {
    func channel(_ shift: UInt32) -> CGFloat {
      let value = CGFloat((hex >> shift) & 0xFF) / 255
      return value + (1 - value) * amount
    }
    return NSColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: 1)
  }

  /// The board's `clay()` material: physically based, roughness 0.42, clear coat 0.55 / 0.3.
  static func clay(_ hex: UInt32) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.diffuse.contents = color(hex)
    material.roughness.contents = NSNumber(value: 0.42)
    material.metalness.contents = NSNumber(value: 0.0)
    material.clearCoat.contents = NSNumber(value: 0.55)
    material.clearCoatRoughness.contents = NSNumber(value: 0.3)
    return material
  }

  /// Stand-in for the board's transmissive `glass()` lens disc: an opaque, glossy pale mint so the
  /// lens reads the same on light and dark backgrounds.
  static func lensGlass(_ hex: UInt32) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.diffuse.contents = color(hex, mixWhite: 0.35)
    material.roughness.contents = NSNumber(value: 0.07)
    material.metalness.contents = NSNumber(value: 0.0)
    material.clearCoat.contents = NSNumber(value: 1.0)
    material.clearCoatRoughness.contents = NSNumber(value: 0.05)
    return material
  }

  // MARK: - Geometry helpers (three.js equivalents)

  static func vec(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
    SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z))
  }

  /// Draw-order counter for `body()`; every body gets the next value. Main thread only.
  static var bodyCount = 0

  /// `B()`: adds a clay body with a three.js-style position and XYZ Euler rotation. SceneKit's
  /// `eulerAngles` compose in the same order (R = Rx·Ry·Rz). Extrusions are centred on their
  /// bounds, like `ExtrudeGeometry.center()`.
  @discardableResult
  static func body(
    _ parent: SCNNode, _ geometry: SCNGeometry, _ hex: UInt32,
    _ p: (Double, Double, Double) = (0, 0, 0), _ r: (Double, Double, Double) = (0, 0, 0)
  ) -> SCNNode {
    let node = SCNNode(geometry: geometry.copy() as? SCNGeometry ?? geometry)
    node.geometry?.materials = [clay(hex)]
    if geometry is SCNShape {
      let (minimum, maximum) = geometry.boundingBox
      node.pivot = SCNMatrix4MakeTranslation(
        (minimum.x + maximum.x) / 2, (minimum.y + maximum.y) / 2, (minimum.z + maximum.z) / 2)
    } else if geometry is SCNTorus {
      // SCNTorus lies in the XZ plane; three.js's TorusGeometry lies in XY.
      node.pivot = SCNMatrix4MakeRotation(-.pi / 2, 1, 0, 0)
    }
    node.position = vec(p.0, p.1, p.2)
    node.eulerAngles = vec(r.0, r.1, r.2)
    // A fixed draw order keeps intersecting bodies from resolving depth ties differently per run.
    bodyCount += 1
    node.renderingOrder = bodyCount
    parent.addChildNode(node)
    return node
  }

  static func group(_ parent: SCNNode, _ p: (Double, Double, Double) = (0, 0, 0)) -> SCNNode {
    let node = SCNNode()
    node.position = vec(p.0, p.1, p.2)
    parent.addChildNode(node)
    return node
  }

  /// `RoundedBoxGeometry(w, h, d, 4, r)`.
  static func roundedBox(_ w: Double, _ h: Double, _ d: Double, _ r: Double) -> SCNGeometry {
    let box = SCNBox(
      width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: CGFloat(r))
    box.chamferSegmentCount = 6
    return box
  }

  /// `CapsuleGeometry(r, length)`: the three.js length excludes the caps.
  static func capsule(_ radius: Double, _ length: Double) -> SCNGeometry {
    let capsule = SCNCapsule(capRadius: CGFloat(radius), height: CGFloat(length + 2 * radius))
    capsule.radialSegmentCount = 48
    capsule.capSegmentCount = 24
    return capsule
  }

  /// `CylinderGeometry(rTop, rBottom, h)`.
  static func cylinder(_ top: Double, _ bottom: Double, _ height: Double) -> SCNGeometry {
    if top == bottom {
      let cylinder = SCNCylinder(radius: CGFloat(top), height: CGFloat(height))
      cylinder.radialSegmentCount = 72
      return cylinder
    }
    let cone = SCNCone(
      topRadius: CGFloat(top), bottomRadius: CGFloat(bottom), height: CGFloat(height))
    cone.radialSegmentCount = 72
    return cone
  }

  /// `ConeGeometry(r, h)`.
  static func cone(_ radius: Double, _ height: Double) -> SCNGeometry {
    let cone = SCNCone(topRadius: 0, bottomRadius: CGFloat(radius), height: CGFloat(height))
    cone.radialSegmentCount = 72
    return cone
  }

  /// `TorusGeometry(R, tube, radial, tubular)`; `body()` turns it into three.js's XY plane.
  static func torus(
    _ ringRadius: Double, _ tube: Double, radial: Int, tubular: Int
  ) -> SCNGeometry {
    let torus = SCNTorus(ringRadius: CGFloat(ringRadius), pipeRadius: CGFloat(tube))
    torus.ringSegmentCount = tubular
    torus.pipeSegmentCount = radial
    return torus
  }

  /// `TorusGeometry(R, tube, radial, tubular, arc)` for a partial ring (the padlock shackle), built
  /// vertex for vertex like three.js in the XY plane, from angle 0 to `arc`.
  static func arcTorus(
    _ ringRadius: Double, _ tube: Double, radial: Int, tubular: Int, arc: Double
  ) -> SCNGeometry {
    var vertices: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var indices: [UInt32] = []
    for j in 0...radial {
      for i in 0...tubular {
        let u = Double(i) / Double(tubular) * arc
        let v = Double(j) / Double(radial) * 2 * Double.pi
        let x = (ringRadius + tube * cos(v)) * cos(u)
        let y = (ringRadius + tube * cos(v)) * sin(u)
        let z = tube * sin(v)
        vertices.append(vec(x, y, z))
        normals.append(
          vec((x - ringRadius * cos(u)) / tube, (y - ringRadius * sin(u)) / tube, z / tube))
      }
    }
    let row = UInt32(tubular + 1)
    for j in 1...UInt32(radial) {
      for i in 1...UInt32(tubular) {
        let a = row * j + i - 1
        let b = row * (j - 1) + i - 1
        let c = row * (j - 1) + i
        let d = row * j + i
        indices += [a, b, d, b, c, d]
      }
    }
    return SCNGeometry(
      sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
      elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
  }

  /// A rounded (quarter-circle) chamfer, closer to three.js's curved bevel than SceneKit's straight
  /// default.
  static let roundedChamferProfile: NSBezierPath = {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 0, y: 1))
    path.curve(
      to: NSPoint(x: 1, y: 0), controlPoint1: NSPoint(x: 0.5523, y: 1),
      controlPoint2: NSPoint(x: 1, y: 0.5523))
    return path
  }()

  /// Flattens a path into closed contours the way three.js's `Shape.extractPoints` does
  /// (`curveSegments` points per curve), dropping repeated points.
  static func contours(of path: CGPath, curveSegments: Int = 36) -> [[CGPoint]] {
    var result: [[CGPoint]] = []
    var current: [CGPoint] = []
    func finish() {
      var points: [CGPoint] = []
      for p in current where points.last.map({ hypot($0.x - p.x, $0.y - p.y) > 1e-9 }) ?? true {
        points.append(p)
      }
      if let first = points.first, let last = points.last, points.count > 1,
        hypot(first.x - last.x, first.y - last.y) <= 1e-9
      {
        points.removeLast()
      }
      if points.count > 2 { result.append(points) }
      current = []
    }
    path.applyWithBlock { pointer in
      let element = pointer.pointee
      switch element.type {
      case .moveToPoint:
        finish()
        current = [element.points[0]]
      case .addLineToPoint:
        current.append(element.points[0])
      case .addQuadCurveToPoint:
        let p0 = current.last ?? .zero
        let c = element.points[0]
        let p1 = element.points[1]
        for step in 1...curveSegments {
          let t = CGFloat(step) / CGFloat(curveSegments)
          let u = 1 - t
          current.append(
            CGPoint(
              x: u * u * p0.x + 2 * u * t * c.x + t * t * p1.x,
              y: u * u * p0.y + 2 * u * t * c.y + t * t * p1.y))
        }
      case .addCurveToPoint:
        let p0 = current.last ?? .zero
        let c1 = element.points[0]
        let c2 = element.points[1]
        let p1 = element.points[2]
        for step in 1...curveSegments {
          let t = CGFloat(step) / CGFloat(curveSegments)
          let u = 1 - t
          let a = u * u * u
          let b = 3 * u * u * t
          let c = 3 * u * t * t
          let d = t * t * t
          current.append(
            CGPoint(
              x: a * p0.x + b * c1.x + c * c2.x + d * p1.x,
              y: a * p0.y + b * c1.y + c * c2.y + d * p1.y))
        }
      case .closeSubpath:
        finish()
      @unknown default:
        break
      }
    }
    finish()
    return result
  }

  static func signedArea(_ points: [CGPoint]) -> CGFloat {
    var area: CGFloat = 0
    for i in points.indices {
      let p = points[i]
      let q = points[(i + 1) % points.count]
      area += p.x * q.y - q.x * p.y
    }
    return area / 2
  }

  /// Moves every vertex outward from the solid by `distance` along its mitred bevel vector, like
  /// three.js's `getBevelVec`. Outer contours must wind counter-clockwise and holes clockwise, so
  /// the same edge normal grows the outline and shrinks the holes.
  static func offset(_ points: [CGPoint], by distance: CGFloat) -> [CGPoint] {
    func normal(_ a: CGPoint, _ b: CGPoint) -> CGVector {
      let dx = b.x - a.x
      let dy = b.y - a.y
      let length = hypot(dx, dy)
      return CGVector(dx: dy / length, dy: -dx / length)
    }
    let count = points.count
    return points.indices.map { i in
      let previous = points[(i + count - 1) % count]
      let current = points[i]
      let next = points[(i + 1) % count]
      let n1 = normal(previous, current)
      let n2 = normal(current, next)
      var bisector = CGVector(dx: n1.dx + n2.dx, dy: n1.dy + n2.dy)
      let length = hypot(bisector.dx, bisector.dy)
      bisector = length < 1e-9 ? n1 : CGVector(dx: bisector.dx / length, dy: bisector.dy / length)
      let cosine = max(bisector.dx * n1.dx + bisector.dy * n1.dy, 0.4)
      let shift = distance / cosine
      return CGPoint(x: current.x + bisector.dx * shift, y: current.y + bisector.dy * shift)
    }
  }

  /// `ext(shape, depth, bevel)`: three.js extrudes `depth` and adds a bevel of thickness `bevel`
  /// on each face that grows the outline by `0.8 × bevel`. SceneKit's chamfer stays inside the
  /// path, so the flattened outline is grown first and the chamfer then rounds it back to the face.
  static func extrusion(_ shape: CGPath, depth: Double, bevel: Double) -> SCNShape {
    let loops = contours(of: shape)
    let outerIndex = loops.indices.max { abs(signedArea(loops[$0])) < abs(signedArea(loops[$1])) }
    let path = NSBezierPath()
    path.windingRule = .nonZero
    for (index, loop) in loops.enumerated() {
      let counterClockwise = signedArea(loop) > 0
      let oriented = (index == outerIndex) == counterClockwise ? loop : loop.reversed()
      let grown = offset(oriented, by: CGFloat(bevel * 0.8))
      path.move(to: grown[0])
      for p in grown.dropFirst() { path.line(to: p) }
      path.close()
    }
    let geometry = SCNShape(path: path, extrusionDepth: CGFloat(depth + 2 * bevel))
    geometry.chamferMode = .both
    geometry.chamferRadius = CGFloat(bevel)
    geometry.chamferProfile = roundedChamferProfile
    return geometry
  }

  static func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

  static func polygon(_ points: [(Double, Double)]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points.map { point($0.0, $0.1) })
    path.closeSubpath()
    return path
  }

  /// `leafShape(w, h)`.
  static func leafShape(_ w: Double, _ h: Double) -> CGPath {
    let path = CGMutablePath()
    path.move(to: point(0, 0))
    path.addCurve(
      to: point(w, 0), control1: point(w * 0.25, h), control2: point(w * 0.75, h * 0.9))
    path.addCurve(
      to: point(0, 0), control1: point(w * 0.75, -h * 0.9), control2: point(w * 0.25, -h))
    path.closeSubpath()
    return path
  }

  /// `leaf()`: a leaf whose base sits at (x, y), pointing along `angle`.
  @discardableResult
  static func leaf(
    _ parent: SCNNode, _ geometry: SCNGeometry, _ w: Double, _ x: Double, _ y: Double,
    _ angle: Double, _ hex: UInt32, z: Double = 0
  ) -> SCNNode {
    body(parent, geometry, hex, (x + cos(angle) * w / 2, y + sin(angle) * w / 2, z), (0, 0, angle))
  }

  /// `gearShape(teeth, r1, r2, hole)`; the hole winds clockwise so it is cut out under the
  /// non-zero rule, as three.js does with `absarc(..., true)`.
  static func gearShape(_ teeth: Int, _ r1: Double, _ r2: Double, _ hole: Double) -> CGPath {
    let path = CGMutablePath()
    let n = teeth * 4
    for i in 0...n {
      let a = Double(i) / Double(n) * 2 * Double.pi
      let r = i % 4 < 2 ? r2 : r1
      let p = point(cos(a) * r, sin(a) * r)
      if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    let k = 0.5523 * hole
    path.move(to: point(hole, 0))
    path.addCurve(to: point(0, -hole), control1: point(hole, -k), control2: point(k, -hole))
    path.addCurve(to: point(-hole, 0), control1: point(-k, -hole), control2: point(-hole, -k))
    path.addCurve(to: point(0, hole), control1: point(-hole, k), control2: point(-k, hole))
    path.addCurve(to: point(hole, 0), control1: point(k, hole), control2: point(hole, k))
    path.closeSubpath()
    return path
  }

  // MARK: - Shared models

  /// The Sprout Lens in the XY plane: a forest ring centred at `center`, a glossy pale disc in the
  /// ring and a handle at `handle.at`, angled 45°. The scan icon and the terrarium both use it.
  static func lens(
    _ parent: SCNNode, center c: (Double, Double, Double) = (0, 0, 0), ring: Double,
    tube: Double, segments: (radial: Int, tubular: Int), disc: Double, discDepth: Double,
    handle: (radius: Double, length: Double, at: (Double, Double, Double))
  ) {
    body(
      parent, torus(ring, tube, radial: segments.radial, tubular: segments.tubular),
      Palette.forest, c)
    let glass = SCNNode(geometry: cylinder(disc, disc, discDepth))
    glass.geometry?.materials = [lensGlass(Palette.mint)]
    glass.eulerAngles = vec(Double.pi / 2, 0, 0)
    glass.position = vec(c.0, c.1, c.2)
    bodyCount += 1
    glass.renderingOrder = bodyCount
    parent.addChildNode(glass)
    body(
      parent, capsule(handle.radius, handle.length), Palette.forest, handle.at,
      (0, 0, Double.pi / 4))
  }

  /// A sprout: a leaf-green stem capsule centred at `stem.y`, then one `leafGeometry` leaf per
  /// entry, its base on the stem axis at height `y`, pointing along `angle`. Returns the leaves.
  @discardableResult
  static func sprout(
    _ parent: SCNNode, stem: (radius: Double, length: Double, y: Double),
    leafGeometry: SCNGeometry, leaves: [(width: Double, y: Double, angle: Double)]
  ) -> [SCNNode] {
    body(parent, capsule(stem.radius, stem.length), Palette.leaf, (0, stem.y, 0))
    return leaves.map { leaf(parent, leafGeometry, $0.width, 0, $0.y, $0.angle, Palette.leaf) }
  }

  // MARK: - Studio lighting

  static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  static func bitmapContext(_ width: Int, _ height: Int) -> CGContext {
    CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  }

  /// A soft studio environment as an equirectangular image: a bright, faintly warm ceiling falling
  /// to a dim floor, with one broad softbox band above the horizon. It depends on elevation only.
  static func studioEnvironment() -> CGImage {
    let width = 512
    let height = 256
    let context = bitmapContext(width, height)
    let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
    func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
      let t = max(0, min(1, (x - e0) / (e1 - e0)))
      return t * t * (3 - 2 * t)
    }
    for row in 0..<height {
      // Elevation from +90° (top row) to −90° (bottom row).
      let elevation = (0.5 - (Double(row) + 0.5) / Double(height)) * Double.pi
      let up = smooth(-0.5, 1.1, elevation)
      let band = exp(-pow((elevation - 0.6) / 0.25, 2)) * 0.2
      let level = 0.16 + up * 0.72 + band
      let warm = (min(1, level), min(1, level * 0.99), min(1, level * 0.97))
      for column in 0..<width {
        // Row 0 of the context's memory is the top row of the image.
        let index = (row * width + column) * 4
        pixels[index] = UInt8((warm.0 * 255).rounded())
        pixels[index + 1] = UInt8((warm.1 * 255).rounded())
        pixels[index + 2] = UInt8((warm.2 * 255).rounded())
        pixels[index + 3] = 255
      }
    }
    return context.makeImage()!
  }
}
