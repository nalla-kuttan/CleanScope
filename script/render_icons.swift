// Renders the 3D module icon family into Sources/CleanScopeApp/Resources/Icons.
//
// Build and run from the repository root (the SceneKit builders live in the app's
// IconGeometry.swift, which the terrarium shares):
//
//     swiftc -O Sources/CleanScopeApp/Brand/IconGeometry.swift script/render_icons.swift -o .build/render_icons && .build/render_icons
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

/// Hover intensity (the board's `h`) at time `t` of the hover frames. The board eases `h` toward 1
/// as `1 − 0.02^t`; this is the same curve over the 0.6 s of frames, normalised so frame 00 has
/// h = 0 (identical to the still, which uses t = 0, h = 0) and frame 17 has h = 1. The app plays
/// the frames once and rests on frame 17 while hovered.
private func hoverIntensity(at t: Double) -> Double {
  (1 - pow(0.02, t / hoverDuration)) / (1 - 0.02)
}

// MARK: - Icons

private struct IconModel {
  let root: SCNNode
  /// The board's `update(t, h)`: `t` in seconds, `h` the hover intensity 0…1.
  let update: (Double, Double) -> Void
}

private typealias G = IconGeometry
private typealias C = IconGeometry.Palette
private let pi = Double.pi

/// Inside this extension the builders call `IconGeometry`'s helpers unqualified.
extension IconGeometry {
  fileprivate static let iconBuilders: [String: () -> IconModel] = [
    "scan": {
      let g = SCNNode()
      let c = (-0.12, 0.14, 0.0)
      lens(
        g, center: c, ring: 0.6, tube: 0.13, segments: (36, 96), disc: 0.55, discDepth: 0.04,
        handle: (0.14, 0.5, (0.5, -0.48, 0)))
      let sp = group(g, (c.0, c.1 - 0.3, 0.06))
      sprout(
        sp, stem: (0.04, 0.3, 0.17),
        leafGeometry: extrusion(leafShape(0.3, 0.15), depth: 0.04, bevel: 0.016),
        leaves: [(0.3, 0.3, 0.5), (0.3, 0.36, pi - 0.45)])
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
      sprout(
        sp, stem: (0.045, 0.32, 0.16),
        leafGeometry: extrusion(leafShape(0.34, 0.17), depth: 0.045, bevel: 0.016),
        leaves: [(0.34, 0.3, 0.45), (0.34, 0.38, pi - 0.5)])
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
      s.addCurve(
        to: point(-0.71, 0.05), control1: point(-0.34, -0.76), control2: point(-0.66, -0.46))
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
}

/// Keys in `ModuleIconKey` order.
private let iconKeys = [
  "scan", "cleanup", "map", "large", "dev", "downloads", "leftovers", "maintenance", "memory",
  "login", "protection", "privacy",
]

// MARK: - Studio

/// The board's `shadowTexture()`: a 128 px radial gradient from rgba(50, 35, 20) to clear. The
/// centre opacity is 0.42 rather than 0.5, tuned to match the board's rendered shadow strength.
private func contactShadowImage() -> CGImage {
  let context = G.bitmapContext(128, 128)
  let colors =
    [
      CGColor(colorSpace: G.sRGB, components: [50 / 255, 35 / 255, 20 / 255, 0.42])!,
      CGColor(colorSpace: G.sRGB, components: [50 / 255, 35 / 255, 20 / 255, 0])!,
    ] as CFArray
  let gradient = CGGradient(colorsSpace: G.sRGB, colors: colors, locations: [0, 1])!
  context.drawRadialGradient(
    gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
    endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
  return context.makeImage()!
}

private let environmentImage = G.studioEnvironment()
private let shadowImage = contactShadowImage()

private func makeScene(holding model: IconModel) -> (SCNScene, SCNNode) {
  let scene = SCNScene()
  scene.background.contents = NSColor.clear
  scene.lightingEnvironment.contents = environmentImage
  scene.lightingEnvironment.intensity = 1.0

  let key = SCNNode()
  key.light = SCNLight()
  key.light?.type = .directional
  key.light?.color = G.color(0xFFF3E0)
  key.light?.intensity = 1700
  key.position = G.vec(-2.5, 4, 3.5)
  key.look(at: G.vec(0, 0, 0))
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
  shadow.position = G.vec(0, -1.08, 0)
  shadow.scale = G.vec(1, 0.45, 1)
  shadow.renderingOrder = -1
  scene.rootNode.addChildNode(shadow)

  let camera = SCNNode()
  camera.camera = SCNCamera()
  camera.camera?.fieldOfView = 26
  camera.camera?.projectionDirection = .vertical
  camera.camera?.zNear = 0.1
  camera.camera?.zFar = 50
  camera.position = G.vec(0, 0.55, 5.7)
  camera.look(at: G.vec(0, -0.05, 0))
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
  let context = G.bitmapContext(pixels, pixels)
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

@main
struct RenderIcons {
  static func main() throws {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    for key in iconKeys {
      guard let build = IconGeometry.iconBuilders[key] else { fatalError("no model for \(key)") }
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
        model.update(t, hoverIntensity(at: t))
        writePNG(
          render(renderer, pixels: hoverPixels),
          named: String(format: "%@-hover-%02d.png", key, frame))
      }
      print("rendered \(key)")
    }
  }
}
