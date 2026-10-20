import AppKit
import CleanScopeCore
import SceneKit

/// The storage terrarium: a glass dome over five soil layers sized from real storage categories,
/// leaf litter (safe caches) on top, a sprout, and the Sprout Lens parked beside it.
///
/// The scene only holds state and plays motion it is asked for; `TerrariumView` decides when
/// motion is allowed (`MotionPolicy`, visibility) and pauses the view otherwise.
@MainActor
final class TerrariumScene {
  private typealias B = TerrariumBuilders

  let scene = SCNScene()
  let cameraNode = TerrariumBuilders.camera()

  /// Pointer tilt about the vertical axis (±0.3 rad), applied over the idle spin.
  private let tilt = SCNNode()
  /// Everything on the plinth; turns slowly while ambient motion is on.
  private let world = SCNNode()
  private var layerNodes: [TerrariumLayer.Kind: SCNNode] = [:]
  private let litter = SCNNode()
  /// The 170 leaves as separate nodes; shown only while composting animates them one by one.
  private let looseLeaves = SCNNode()
  /// The same leaves merged into one node, drawn the rest of the time (5 draw calls, not 170).
  private var mergedLeaves = SCNNode()
  private var leaves: [TerrariumBuilders.Leaf] = []
  private let sprout = SCNNode()
  private var sproutLeaves: [SCNNode] = []
  /// Turns about the dome's axis while scanning; the lens rides on it.
  private let lensRig = SCNNode()
  private let lens = TerrariumBuilders.lens()

  private(set) var layers: [TerrariumLayer] = []
  private(set) var growthStage = 1
  private(set) var isScanning = false
  private var ambient = false
  /// False while the view is paused or Reduce Motion is on: every change then lands at once,
  /// because a paused view never advances an animation.
  var allowsAnimation = true
  private var litterComposted = false

  private static let environment = IconGeometry.studioEnvironment()

  init() {
    scene.background.contents = NSColor.clear
    scene.lightingEnvironment.contents = Self.environment
    scene.lightingEnvironment.intensity = 1.0
    scene.rootNode.addChildNode(cameraNode)
    scene.rootNode.addChildNode(B.keyLight())

    scene.rootNode.addChildNode(tilt)
    tilt.addChildNode(world)
    world.addChildNode(B.plinth())
    world.addChildNode(B.rim())
    for kind in TerrariumLayer.Kind.allCases {
      let node = B.layer(kind)
      layerNodes[kind] = node
      world.addChildNode(node)
    }
    world.addChildNode(litter)
    litter.addChildNode(looseLeaves)
    leaves = B.litter(in: looseLeaves)
    mergedLeaves = looseLeaves.flattenedClone()
    litter.addChildNode(mergedLeaves)
    looseLeaves.isHidden = true
    world.addChildNode(sprout)
    sproutLeaves = B.sprout(in: sprout)
    world.addChildNode(B.dome())

    scene.rootNode.addChildNode(lensRig)
    lensRig.addChildNode(lens)
    lens.position = B.parkedLens

    let empty = TerrariumLayer.Kind.allCases.map {
      TerrariumLayer(kind: $0, bytes: 0, height: 0.066)
    }
    apply(layers: empty, growthStage: 1, animated: false)
  }

  // MARK: - State

  /// Stacks the layers bottom to top from the plinth, moves litter and sprout onto the top
  /// layer and sets the sprout's stage (1: two leaves, 2: three leaves, 3: three larger leaves).
  /// The litter shows whenever there is something safe to reclaim.
  func apply(layers: [TerrariumLayer], growthStage: Int, animated: Bool) {
    apply(layers: layers, growthStage: growthStage, duration: animated ? 0.6 : 0)
  }

  /// `seconds` while animation is allowed, otherwise 0.
  private func timed(_ seconds: Double) -> Double {
    allowsAnimation ? seconds : 0
  }

  private func apply(layers newLayers: [TerrariumLayer], growthStage stage: Int, duration: Double) {
    let safeBytes = newLayers.first { $0.kind == .safe }?.bytes ?? 0
    // A composted terrarium grows litter again only when a later scan finds more caches.
    if litterComposted && safeBytes > (layers.first { $0.kind == .safe }?.bytes ?? 0) {
      restoreLitter()
    }
    layers = newLayers
    growthStage = min(max(stage, 1), 3)

    SCNTransaction.begin()
    SCNTransaction.animationDuration = timed(duration)
    SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    var y = B.base
    for layer in newLayers {
      guard let node = layerNodes[layer.kind] else { continue }
      let height = max(layer.height, 0.001)
      node.scale = SCNVector3(1, height, 1)
      node.position = SCNVector3(0, y + height / 2, 0)
      y += height
    }
    litter.position = SCNVector3(0, y + 0.02, 0)
    litter.opacity = safeBytes > 0 || litterComposted ? 1 : 0
    sprout.position = SCNVector3(0, y, 0)
    let scale = [1.0, 1.18, 1.32][growthStage - 1]
    sprout.scale = SCNVector3(scale, scale, scale)
    sproutLeaves.last?.opacity = growthStage >= 2 ? 1 : 0
    SCNTransaction.commit()
  }

  /// Scanning sends the lens round the dome once every three seconds and makes the layer of the
  /// latest streamed category glow faintly (emission 0.35).
  func setScanning(_ on: Bool, glowing: TerrariumLayer.Kind?) {
    SCNTransaction.begin()
    SCNTransaction.animationDuration = timed(0.3)
    for (kind, node) in layerNodes {
      node.geometry?.firstMaterial?.emission.intensity = on && kind == glowing ? 0.35 : 0
    }
    SCNTransaction.commit()

    guard on != isScanning else { return }
    isScanning = on
    lens.removeAction(forKey: "bob")
    if on {
      SCNTransaction.begin()
      SCNTransaction.animationDuration = timed(0.6)
      lens.position = SCNVector3(-B.orbitRadius, -0.2, 0)
      SCNTransaction.commit()
      lensRig.runAction(
        .repeatForever(.rotateBy(x: 0, y: -2 * .pi, z: 0, duration: 3)), forKey: "orbit")
      lens.runAction(Self.bob(height: 0.3, period: 3), forKey: "bob")
    } else {
      lensRig.removeAction(forKey: "orbit")
      lensRig.eulerAngles = lensRig.presentation.eulerAngles
      SCNTransaction.begin()
      SCNTransaction.animationDuration = timed(0.8)
      lensRig.eulerAngles = SCNVector3(0, 0, 0)
      lens.position = B.parkedLens
      SCNTransaction.commit()
      if ambient { lens.runAction(Self.bob(height: 0.06, period: 4.8), forKey: "bob") }
    }
  }

  /// After a confirmed cleanup: the litter shrinks and sinks 0.08 (each leaf after its own short
  /// delay), the layers settle on `target` (by default the safe layer thins to nothing) and the
  /// sprout grows to `targetStage` (by default one stage). A zero duration jumps to the end.
  func compost(
    duration: TimeInterval, to target: [TerrariumLayer]? = nil, growthStage targetStage: Int? = nil
  ) {
    let next =
      target
      ?? layers.map { layer in
        layer.kind == .safe ? TerrariumLayer(kind: .safe, bytes: 0, height: 0.066) : layer
      }
    let duration = timed(duration)
    let unit = duration / 1.6
    looseLeaves.isHidden = false
    mergedLeaves.isHidden = true
    for leaf in leaves {
      leaf.node.removeAllActions()
      guard duration > 0 else {
        leaf.node.scale = SCNVector3(0.0001, 0.0001, 0.0001)
        continue
      }
      let shrink = SCNAction.group([
        .scale(to: 0.0001, duration: 0.7 * unit),
        .moveBy(x: 0, y: -0.08, z: 0, duration: 0.7 * unit),
      ])
      shrink.timingMode = .easeOut
      leaf.node.runAction(.sequence([.wait(duration: leaf.delay * unit), shrink]))
    }
    apply(layers: next, growthStage: targetStage ?? growthStage + 1, duration: duration)
    litterComposted = true
  }

  /// Puts the litter back (a new scan found caches again after a compost).
  private func restoreLitter() {
    litterComposted = false
    for leaf in leaves {
      leaf.node.removeAllActions()
      let position = leaf.node.position
      leaf.node.position = SCNVector3(position.x, 0, position.z)
      leaf.node.scale = SCNVector3(leaf.scale, leaf.scale, leaf.scale)
    }
    looseLeaves.isHidden = true
    mergedLeaves.isHidden = false
  }

  // MARK: - Ambient motion

  /// Idle spin (0.12 rad/s), sprout sway and a slow lens bob. Off leaves everything where it is.
  func setAmbientMotion(_ on: Bool) {
    guard on != ambient else { return }
    ambient = on
    if on {
      world.runAction(
        .repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 2 * .pi / 0.12)),
        forKey: "spin")
      let sway = SCNAction.sequence([
        .rotateTo(x: 0, y: 0, z: 0.04, duration: 2.2, usesShortestUnitArc: true),
        .rotateTo(x: 0, y: 0, z: -0.04, duration: 2.2, usesShortestUnitArc: true),
      ])
      sway.timingMode = .easeInEaseOut
      sprout.runAction(.repeatForever(sway), forKey: "sway")
      if !isScanning { lens.runAction(Self.bob(height: 0.06, period: 4.8), forKey: "bob") }
    } else {
      world.removeAction(forKey: "spin")
      sprout.removeAction(forKey: "sway")
      if !isScanning { lens.removeAction(forKey: "bob") }
      setPointer(0)
    }
  }

  /// Pointer position across the view, −0.5 (left edge) … 0.5 (right edge); tilts ±0.3 rad.
  func setPointer(_ x: Double) {
    let target = ambient ? min(max(x, -0.5), 0.5) * 0.6 : 0
    guard abs(Double(tilt.eulerAngles.y) - target) > 0.001 else { return }
    SCNTransaction.begin()
    SCNTransaction.animationDuration = timed(0.35)
    tilt.eulerAngles.y = target
    SCNTransaction.commit()
  }

  private static func bob(height: Double, period: Double) -> SCNAction {
    let up = SCNAction.moveBy(x: 0, y: height / 2, z: 0, duration: period / 2)
    up.timingMode = .easeInEaseOut
    let down = SCNAction.moveBy(x: 0, y: -height / 2, z: 0, duration: period / 2)
    down.timingMode = .easeInEaseOut
    return .repeatForever(.sequence([up, down]))
  }

  // MARK: - Snapshot

  /// A still of the terrarium for the menu bar popover, rendered offscreen at 2× into an image of
  /// `size` points with a transparent background.
  static func snapshot(
    layers: [TerrariumLayer], growthStage: Int, size: CGSize = CGSize(width: 120, height: 80)
  ) -> NSImage? {
    let terrarium = TerrariumScene()
    terrarium.apply(layers: layers, growthStage: growthStage, animated: false)
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = terrarium.scene
    renderer.pointOfView = terrarium.cameraNode
    let pixels = CGSize(width: size.width * 2, height: size.height * 2)
    let image = renderer.snapshot(atTime: 0, with: pixels, antialiasingMode: .multisampling4X)
    image.size = size
    return image
  }
}
