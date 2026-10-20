#!/usr/bin/env swift
// Renders the 3D module icon family into Sources/CleanScopeApp/Resources/Icons.
//
// Run from the repository root:
//
//     swift script/render_icons.swift
//
// The models, palette and hover actions are a port of the `ICONS` object in the living-interface
// concept board (three.js). Each icon is written as `<key>@1x.png` (64 px), `<key>@2x.png`
// (128 px), `<key>@3x.png` (192 px) and 18 hover frames `<key>-hover-00…17.png` (128 px).
// The script takes no time-dependent or random input, so the same source renders the same bytes.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SceneKit
import UniformTypeIdentifiers

// MARK: - Output

private let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  .appendingPathComponent("Sources/CleanScopeApp/Resources/Icons", isDirectory: true)
private let stillSizes: [(scale: Int, pixels: Int)] = [(1, 64), (2, 128), (3, 192)]
private let hoverPixels = 128
private let hoverFrameCount = 18
/// Hover frame n samples the action at t = n · 0.6 s / 17, from 0 s to 0.6 s inclusive.
private let hoverDuration = 0.6
/// Hover intensity used for the hover frames (the board's `h`). The stills use t = 0, h = 0.
private let hoverIntensity = 1.0

// MARK: - Palette and material

private enum Palette {
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

private func color(_ hex: UInt32, mixWhite amount: CGFloat = 0) -> NSColor {
  func channel(_ shift: UInt32) -> CGFloat {
    let value = CGFloat((hex >> shift) & 0xFF) / 255
    return value + (1 - value) * amount
  }
  return NSColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: 1)
}

/// The board's `clay()` material: physically based, roughness 0.42, clear coat 0.55 / 0.3.
private func clay(_ hex: UInt32) -> SCNMaterial {
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
private func lensGlass(_ hex: UInt32) -> SCNMaterial {
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

private func vec(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
  SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z))
}

private var bodyCount = 0

/// `B()`: adds a clay body with a three.js-style position and XYZ Euler rotation. SceneKit's
/// `eulerAngles` compose in the same order (R = Rx·Ry·Rz). Extrusions are centred on their
/// bounds, like `ExtrudeGeometry.center()`.
@discardableResult
private func body(
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

private func group(_ parent: SCNNode, _ p: (Double, Double, Double) = (0, 0, 0)) -> SCNNode {
  let node = SCNNode()
  node.position = vec(p.0, p.1, p.2)
  parent.addChildNode(node)
  return node
}

/// `RoundedBoxGeometry(w, h, d, 4, r)`.
private func roundedBox(_ w: Double, _ h: Double, _ d: Double, _ r: Double) -> SCNGeometry {
  let box = SCNBox(
    width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: CGFloat(r))
  box.chamferSegmentCount = 6
  return box
}

/// `CapsuleGeometry(r, length)`: the three.js length excludes the caps.
private func capsule(_ radius: Double, _ length: Double) -> SCNGeometry {
  let capsule = SCNCapsule(capRadius: CGFloat(radius), height: CGFloat(length + 2 * radius))
  capsule.radialSegmentCount = 48
  capsule.capSegmentCount = 24
  return capsule
}

/// `CylinderGeometry(rTop, rBottom, h)`.
private func cylinder(_ top: Double, _ bottom: Double, _ height: Double) -> SCNGeometry {
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
private func cone(_ radius: Double, _ height: Double) -> SCNGeometry {
  let cone = SCNCone(topRadius: 0, bottomRadius: CGFloat(radius), height: CGFloat(height))
  cone.radialSegmentCount = 72
  return cone
}

/// `TorusGeometry(R, tube, radial, tubular)`; `body()` turns it into three.js's XY plane.
private func torus(_ ringRadius: Double, _ tube: Double, radial: Int, tubular: Int) -> SCNGeometry {
  let torus = SCNTorus(ringRadius: CGFloat(ringRadius), pipeRadius: CGFloat(tube))
  torus.ringSegmentCount = tubular
  torus.pipeSegmentCount = radial
  return torus
}

/// `TorusGeometry(R, tube, radial, tubular, arc)` for a partial ring (the padlock shackle), built
/// vertex for vertex like three.js in the XY plane, from angle 0 to `arc`.
private func arcTorus(
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
private let roundedChamferProfile: NSBezierPath = {
  let path = NSBezierPath()
  path.move(to: NSPoint(x: 0, y: 1))
  path.curve(
    to: NSPoint(x: 1, y: 0), controlPoint1: NSPoint(x: 0.5523, y: 1),
    controlPoint2: NSPoint(x: 1, y: 0.5523))
  return path
}()

/// Flattens a path into closed contours the way three.js's `Shape.extractPoints` does
/// (`curveSegments` points per curve), dropping repeated points.
private func contours(of path: CGPath, curveSegments: Int = 36) -> [[CGPoint]] {
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

private func signedArea(_ points: [CGPoint]) -> CGFloat {
  var area: CGFloat = 0
  for i in points.indices {
    let p = points[i]
    let q = points[(i + 1) % points.count]
    area += p.x * q.y - q.x * p.y
  }
  return area / 2
}

/// Moves every vertex outward from the solid by `distance` along its mitred bevel vector, like
/// three.js's `getBevelVec`. Outer contours must wind counter-clockwise and holes clockwise, so the
/// same edge normal grows the outline and shrinks the holes.
private func offset(_ points: [CGPoint], by distance: CGFloat) -> [CGPoint] {
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

/// `ext(shape, depth, bevel)`: three.js extrudes `depth` and adds a bevel of thickness `bevel` on
/// each face that grows the outline by `0.8 × bevel`. SceneKit's chamfer stays inside the path, so
/// the flattened outline is grown first and the chamfer then rounds it back to the face.
private func extrusion(_ shape: CGPath, depth: Double, bevel: Double) -> SCNShape {
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

private func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

private func polygon(_ points: [(Double, Double)]) -> CGPath {
  let path = CGMutablePath()
  path.addLines(between: points.map { point($0.0, $0.1) })
  path.closeSubpath()
  return path
}

/// `leafShape(w, h)`.
private func leafShape(_ w: Double, _ h: Double) -> CGPath {
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
private func leaf(
  _ parent: SCNNode, _ geometry: SCNGeometry, _ w: Double, _ x: Double, _ y: Double,
  _ angle: Double, _ hex: UInt32, z: Double = 0
) -> SCNNode {
  body(parent, geometry, hex, (x + cos(angle) * w / 2, y + sin(angle) * w / 2, z), (0, 0, angle))
}

/// `gearShape(teeth, r1, r2, hole)`; the hole winds clockwise so it is cut out under the
/// non-zero rule, as three.js does with `absarc(..., true)`.
private func gearShape(_ teeth: Int, _ r1: Double, _ r2: Double, _ hole: Double) -> CGPath {
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

// MARK: - Icons

private struct IconModel {
  let root: SCNNode
  /// The board's `update(t, h)`: `t` in seconds, `h` the hover intensity 0…1.
  let update: (Double, Double) -> Void
}

private typealias C = Palette
private let pi = Double.pi

private let iconBuilders: [String: () -> IconModel] = [
  "scan": {
    let g = SCNNode()
    let c = (-0.12, 0.14, 0.0)
    body(g, torus(0.6, 0.13, radial: 36, tubular: 96), C.forest, c)
    let disc = SCNNode(geometry: cylinder(0.55, 0.55, 0.04))
    disc.geometry?.materials = [lensGlass(C.mint)]
    disc.eulerAngles = vec(pi / 2, 0, 0)
    disc.position = vec(c.0, c.1, c.2)
    bodyCount += 1
    disc.renderingOrder = bodyCount
    g.addChildNode(disc)
    body(g, capsule(0.14, 0.5), C.forest, (0.5, -0.48, 0), (0, 0, pi / 4))
    let sp = group(g, (c.0, c.1 - 0.3, 0.06))
    body(sp, capsule(0.04, 0.3), C.leaf, (0, 0.17, 0))
    let lg = extrusion(leafShape(0.3, 0.15), depth: 0.04, bevel: 0.016)
    leaf(sp, lg, 0.3, 0, 0.3, 0.5, C.leaf)
    leaf(sp, lg, 0.3, 0, 0.36, pi - 0.45, C.leaf)
    return IconModel(root: g) { t, h in sp.eulerAngles.z = CGFloat(sin(t * 3) * 0.14 * h) }
  },
  "cleanup": {
    let g = SCNNode()
    body(g, cylinder(0.55, 0.43, 1.05), C.cream, (0, -0.3, 0))
    body(g, torus(0.555, 0.05, radial: 16, tubular: 64), C.sage, (0, 0.22, 0), (pi / 2, 0, 0))
    for i in 0..<5 {
      let a = -0.9 + Double(i) * 0.45
      body(
        g, roundedBox(0.06, 0.78, 0.06, 0.03), C.sage, (sin(a) * 0.5, -0.32, cos(a) * 0.5),
        (0, a, 0))
    }
    let lid = group(g, (-0.5, 0.3, 0))
    body(lid, cylinder(0.6, 0.6, 0.09), C.sage, (0.5, 0, 0))
    body(lid, roundedBox(0.22, 0.08, 0.12, 0.03), C.forest, (0.5, 0.08, 0))
    lid.eulerAngles.z = 0.35
    let sp = group(g, (0.12, 0.28, 0))
    body(sp, capsule(0.045, 0.32), C.leaf, (0, 0.16, 0))
    let lg = extrusion(leafShape(0.34, 0.17), depth: 0.045, bevel: 0.016)
    leaf(sp, lg, 0.34, 0, 0.3, 0.45, C.leaf)
    leaf(sp, lg, 0.34, 0, 0.38, pi - 0.5, C.leaf)
    return IconModel(root: g) { _, h in
      lid.eulerAngles.z = CGFloat(0.35 + h * 0.2)
      let s = CGFloat(1 + h * 0.18)
      sp.scale = SCNVector3(s, s, s)
    }
  },
  "map": {
    let g = SCNNode()
    let inner = group(g)
    inner.eulerAngles = vec(0.55, -0.62, 0)
    body(inner, roundedBox(1.85, 0.16, 1.42, 0.07), C.cream, (0, -0.38, 0))
    let blocks: [(Double, Double, Double, Double, Double, UInt32)] = [
      (-0.48, -0.32, 0.74, 0.56, 0.62, C.sage), (0.43, -0.32, 0.9, 0.56, 0.34, C.amber),
      (-0.62, 0.33, 0.5, 0.62, 0.3, C.blue), (0.0, 0.33, 0.5, 0.62, 0.86, C.terra),
      (0.55, 0.33, 0.5, 0.62, 0.48, C.leaf),
    ]
    let ms = blocks.map { x, z, w, d, height, hex in
      (body(inner, roundedBox(w - 0.05, 1, d - 0.05, 0.05), hex, (x, 0, z)), height)
    }
    return IconModel(root: g) { t, h in
      for (i, (m, height)) in ms.enumerated() {
        let hh = height * (1 + sin(t * 3 + Double(i) * 1.3) * 0.22 * h)
        m.scale.y = CGFloat(hh)
        m.position.y = CGFloat(-0.3 + hh / 2)
      }
    }
  },
  "large": {
    let g = SCNNode()
    let inner = group(g)
    inner.eulerAngles = vec(0.35, -0.6, 0)
    body(inner, roundedBox(1.35, 0.55, 0.95, 0.09), C.amber, (0, -0.5, 0))
    body(inner, roundedBox(0.36, 0.12, 0.02, 0.01), C.cream, (0, -0.48, 0.48))
    body(inner, roundedBox(1.02, 0.44, 0.78, 0.08), C.cream, (0.06, -0.01, 0), (0, 0.14, 0))
    let top = body(
      inner, roundedBox(0.72, 0.36, 0.58, 0.07), C.sage, (-0.04, 0.4, 0), (0, -0.12, 0))
    return IconModel(root: g) { t, h in
      top.position.y = CGFloat(0.4 + abs(sin(t * 3)) * 0.14 * h)
      top.eulerAngles.y = CGFloat(-0.12 + h * 0.3)
    }
  },
  "dev": {
    let g = SCNNode()
    let inner = group(g)
    inner.eulerAngles = vec(0.15, -0.3, 0)
    let lt = polygon([
      (0.3, 0.48), (-0.22, 0), (0.3, -0.48), (0.48, -0.33), (0.12, 0), (0.48, 0.33),
    ])
    let gt = polygon([
      (-0.3, 0.48), (0.22, 0), (-0.3, -0.48), (-0.48, -0.33), (-0.12, 0), (-0.48, 0.33),
    ])
    let sl = polygon([(0.06, 0.58), (0.24, 0.58), (-0.06, -0.58), (-0.24, -0.58)])
    let a = body(inner, extrusion(lt, depth: 0.24, bevel: 0.05), C.blue, (-0.56, 0, 0))
    let b = body(inner, extrusion(gt, depth: 0.24, bevel: 0.05), C.blue, (0.56, 0, 0))
    body(inner, extrusion(sl, depth: 0.24, bevel: 0.05), C.leaf)
    return IconModel(root: g) { t, h in
      let o = sin(t * 4) * 0.08 * h
      a.position.x = CGFloat(-0.56 - o - 0.04 * h)
      b.position.x = CGFloat(0.56 + o + 0.04 * h)
    }
  },
  "downloads": {
    let g = SCNNode()
    let inner = group(g)
    inner.eulerAngles = vec(0.42, -0.3, 0)
    body(inner, roundedBox(1.6, 0.22, 1.05, 0.09), C.cream, (0, -0.62, 0))
    body(inner, roundedBox(1.22, 0.06, 0.7, 0.03), C.tray, (0, -0.5, 0))
    let arrow = group(inner)
    body(arrow, capsule(0.13, 0.42), C.sage, (0, 0.32, 0))
    body(arrow, cone(0.33, 0.38), C.sage, (0, -0.08, 0), (pi, 0, 0))
    return IconModel(root: g) { t, h in
      arrow.position.y = CGFloat(-abs(sin(t * 4)) * 0.16 * h)
    }
  },
  "leftovers": {
    let g = SCNNode()
    let inner = group(g)
    inner.eulerAngles = vec(0.42, -0.62, 0)
    body(inner, roundedBox(1.1, 0.06, 0.9, 0.02), C.card, (0, -0.62, 0))
    body(inner, roundedBox(1.1, 0.62, 0.06, 0.02), C.card, (0, -0.32, 0.42))
    body(inner, roundedBox(1.1, 0.62, 0.06, 0.02), C.card, (0, -0.32, -0.42))
    body(inner, roundedBox(0.06, 0.62, 0.9, 0.02), C.card, (-0.53, -0.32, 0))
    body(inner, roundedBox(0.06, 0.62, 0.9, 0.02), C.card, (0.53, -0.32, 0))
    body(inner, roundedBox(1.1, 0.05, 0.42, 0.02), C.flap, (0, 0.06, 0.6), (0.95, 0, 0))
    body(inner, roundedBox(1.1, 0.05, 0.42, 0.02), C.flap, (0, 0.06, -0.6), (-0.95, 0, 0))
    let c1 = body(
      inner, roundedBox(0.32, 0.32, 0.32, 0.08), C.blue, (-0.12, 0.32, 0), (0.4, 0.5, 0))
    let c2 = body(
      inner, roundedBox(0.24, 0.24, 0.24, 0.06), C.leaf, (0.26, 0.62, 0.04), (0.2, 0.9, 0.3))
    return IconModel(root: g) { t, h in
      c1.position.y = CGFloat(0.32 + sin(t * 3) * 0.12 * h)
      c2.position.y = CGFloat(0.62 + sin(t * 3 + 1.4) * 0.14 * h)
      c1.eulerAngles.y = CGFloat(0.5 + t * 0.8 * h)
    }
  },
  "maintenance": {
    let g = SCNNode()
    let big = body(
      g, extrusion(gearShape(10, 0.58, 0.78, 0.24), depth: 0.24, bevel: 0.05), C.blue,
      (-0.18, 0.12, 0))
    let small = body(
      g, extrusion(gearShape(8, 0.3, 0.43, 0.12), depth: 0.22, bevel: 0.04), C.amber,
      (0.66, -0.52, 0.06))
    small.eulerAngles.z = 0.2
    // The board adds 0.012·h rad per animation frame; at 60 fps that is 0.72·h rad/s.
    return IconModel(root: g) { t, h in
      big.eulerAngles.z = CGFloat(0.72 * t * h)
      small.eulerAngles.z = CGFloat(0.2 - 0.72 * 1.8 * t * h)
    }
  },
  "memory": {
    let g = SCNNode()
    let inner = group(g)
    inner.eulerAngles = vec(0.75, 0.45, 0)
    body(inner, roundedBox(1.15, 0.2, 1.15, 0.08), C.chip)
    let core = body(inner, roundedBox(0.62, 0.07, 0.62, 0.04), C.sage, (0, 0.12, 0))
    core.geometry?.firstMaterial?.emission.contents = color(C.leaf)
    core.geometry?.firstMaterial?.emission.intensity = 0
    for i in -2...2 {
      for s in [-1.0, 1.0] {
        body(inner, roundedBox(0.08, 0.06, 0.2, 0.02), C.gold, (Double(i) * 0.2, -0.02, s * 0.66))
        body(inner, roundedBox(0.2, 0.06, 0.08, 0.02), C.gold, (s * 0.66, -0.02, Double(i) * 0.2))
      }
    }
    return IconModel(root: g) { t, h in
      core.geometry?.firstMaterial?.emission.intensity = CGFloat(h * (0.5 + sin(t * 5) * 0.3))
    }
  },
  "login": {
    let g = SCNNode()
    let inner = group(g)
    inner.eulerAngles.z = -0.55
    body(inner, torus(0.3, 0.12, radial: 24, tubular: 64), C.gold, (-0.55, 0, 0))
    body(inner, roundedBox(1.0, 0.17, 0.17, 0.06), C.gold, (0.18, 0, 0))
    body(inner, roundedBox(0.12, 0.26, 0.15, 0.04), C.gold, (0.5, -0.17, 0))
    body(inner, roundedBox(0.12, 0.2, 0.15, 0.04), C.gold, (0.68, -0.14, 0))
    let lg = extrusion(leafShape(0.28, 0.14), depth: 0.04, bevel: 0.015)
    leaf(inner, lg, 0.28, -0.55, 0.3, 1.9, C.leaf, z: 0.02)
    return IconModel(root: g) { t, h in inner.eulerAngles.x = CGFloat(sin(t * 3) * 0.6 * h) }
  },
  "protection": {
    let g = SCNNode()
    let s = CGMutablePath()
    s.move(to: point(0, 0.86))
    s.addCurve(to: point(0.74, 0.66), control1: point(0.32, 0.76), control2: point(0.58, 0.72))
    s.addLine(to: point(0.71, 0.05))
    s.addCurve(to: point(0, -0.95), control1: point(0.66, -0.46), control2: point(0.34, -0.76))
    s.addCurve(to: point(-0.71, 0.05), control1: point(-0.34, -0.76), control2: point(-0.66, -0.46))
    s.addLine(to: point(-0.74, 0.66))
    s.addCurve(to: point(0, 0.86), control1: point(-0.58, 0.72), control2: point(-0.32, 0.76))
    s.closeSubpath()
    body(g, extrusion(s, depth: 0.26, bevel: 0.07), C.sage)
    let f = group(g, (0, -0.12, 0.22))
    body(f, capsule(0.05, 0.42), C.cream)
    let lg = extrusion(leafShape(0.44, 0.22), depth: 0.05, bevel: 0.018)
    leaf(f, lg, 0.44, 0, 0.06, 0.55, C.leaf)
    leaf(f, lg, 0.44, 0, 0.16, pi - 0.5, C.leaf)
    return IconModel(root: g) { t, h in
      let k = CGFloat(1 + h * 0.12 + sin(t * 4) * 0.03 * h)
      f.scale = SCNVector3(k, k, k)
      g.eulerAngles.y = CGFloat(sin(t * 2) * 0.12 * h)
    }
  },
  "privacy": {
    let g = SCNNode()
    body(g, roundedBox(1.0, 0.82, 0.42, 0.13), C.blue, (0, -0.3, 0))
    let sh = group(g)
    body(sh, arcTorus(0.3, 0.085, radial: 20, tubular: 48, arc: pi), C.cream, (0, 0.14, 0))
    body(sh, cylinder(0.085, 0.085, 0.26), C.cream, (-0.3, 0.02, 0))
    body(sh, cylinder(0.085, 0.085, 0.26), C.cream, (0.3, 0.02, 0))
    body(g, cylinder(0.09, 0.09, 0.06), C.chip, (0, -0.22, 0.22), (pi / 2, 0, 0))
    body(g, roundedBox(0.07, 0.2, 0.06, 0.02), C.chip, (0, -0.35, 0.22))
    return IconModel(root: g) { _, h in
      sh.position.y = CGFloat(h * 0.16)
      sh.eulerAngles.y = CGFloat(h * 0.5)
    }
  },
]

/// Keys in `ModuleIconKey` order.
private let iconKeys = [
  "scan", "cleanup", "map", "large", "dev", "downloads", "leftovers", "maintenance", "memory",
  "login", "protection", "privacy",
]

// MARK: - Studio

private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

private func bitmapContext(_ width: Int, _ height: Int) -> CGContext {
  CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// A soft studio environment as an equirectangular image: a bright, faintly warm ceiling falling
/// to a dim floor, with one broad softbox band above the horizon. It depends on elevation only.
private func studioEnvironment() -> CGImage {
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
      let offset = (row * width + column) * 4
      pixels[offset] = UInt8((warm.0 * 255).rounded())
      pixels[offset + 1] = UInt8((warm.1 * 255).rounded())
      pixels[offset + 2] = UInt8((warm.2 * 255).rounded())
      pixels[offset + 3] = 255
    }
  }
  return context.makeImage()!
}

/// The board's `shadowTexture()`: a 128 px radial gradient from rgba(50, 35, 20) to clear. The
/// centre opacity is 0.42 rather than 0.5, tuned to match the board's rendered shadow strength.
private func contactShadowImage() -> CGImage {
  let context = bitmapContext(128, 128)
  let colors =
    [
      CGColor(colorSpace: sRGB, components: [50 / 255, 35 / 255, 20 / 255, 0.42])!,
      CGColor(colorSpace: sRGB, components: [50 / 255, 35 / 255, 20 / 255, 0])!,
    ] as CFArray
  let gradient = CGGradient(colorsSpace: sRGB, colors: colors, locations: [0, 1])!
  context.drawRadialGradient(
    gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
    endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
  return context.makeImage()!
}

private let environmentImage = studioEnvironment()
private let shadowImage = contactShadowImage()

private func makeScene(holding model: IconModel) -> (SCNScene, SCNNode) {
  let scene = SCNScene()
  scene.background.contents = NSColor.clear
  scene.lightingEnvironment.contents = environmentImage
  scene.lightingEnvironment.intensity = 1.0

  let key = SCNNode()
  key.light = SCNLight()
  key.light?.type = .directional
  key.light?.color = color(0xFFF3E0)
  key.light?.intensity = 1700
  key.position = vec(-2.5, 4, 3.5)
  key.look(at: vec(0, 0, 0))
  scene.rootNode.addChildNode(key)

  let holder = SCNNode()
  holder.addChildNode(model.root)
  scene.rootNode.addChildNode(holder)

  let shadowMaterial = SCNMaterial()
  shadowMaterial.lightingModel = .constant
  shadowMaterial.diffuse.contents = shadowImage
  shadowMaterial.writesToDepthBuffer = false
  shadowMaterial.blendMode = .alpha
  let plane = SCNPlane(width: 2.1, height: 2.1)
  plane.materials = [shadowMaterial]
  let shadow = SCNNode(geometry: plane)
  shadow.eulerAngles.x = -.pi / 2
  shadow.position = vec(0, -1.08, 0)
  shadow.scale = vec(1, 0.45, 1)
  shadow.renderingOrder = -1
  scene.rootNode.addChildNode(shadow)

  let camera = SCNNode()
  camera.camera = SCNCamera()
  camera.camera?.fieldOfView = 26
  camera.camera?.projectionDirection = .vertical
  camera.camera?.zNear = 0.1
  camera.camera?.zFar = 50
  camera.position = vec(0, 0.55, 5.7)
  camera.look(at: vec(0, -0.05, 0))
  scene.rootNode.addChildNode(camera)
  return (scene, camera)
}

// MARK: - Rendering

private let device = MTLCreateSystemDefaultDevice()

private func render(_ renderer: SCNRenderer, pixels: Int) -> CGImage {
  let snapshot = renderer.snapshot(
    atTime: 0, with: CGSize(width: pixels, height: pixels), antialiasingMode: .multisampling4X)
  var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
  let source = snapshot.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
  // Normalise size, colour space and alpha layout so the encoded bytes depend only on the scene.
  let context = bitmapContext(pixels, pixels)
  context.interpolationQuality = .high
  context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
  context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
  return context.makeImage()!
}

private func writePNG(_ image: CGImage, named name: String) {
  let url = outputDirectory.appendingPathComponent(name)
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { fatalError("cannot write \(url.path)") }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("cannot encode \(name)") }
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for key in iconKeys {
  guard let build = iconBuilders[key] else { fatalError("no model for \(key)") }
  let model = build()
  let (scene, camera) = makeScene(holding: model)
  let renderer = SCNRenderer(device: device, options: nil)
  renderer.scene = scene
  renderer.pointOfView = camera

  model.update(0, 0)
  for still in stillSizes {
    writePNG(render(renderer, pixels: still.pixels), named: "\(key)@\(still.scale)x.png")
  }
  for frame in 0..<hoverFrameCount {
    let t = Double(frame) * hoverDuration / Double(hoverFrameCount - 1)
    model.update(t, hoverIntensity)
    writePNG(
      render(renderer, pixels: hoverPixels),
      named: String(format: "%@-hover-%02d.png", key, frame))
  }
  print("rendered \(key)")
}
