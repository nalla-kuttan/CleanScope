import AppKit
import CleanScopeCore
import SceneKit
import SwiftUI

/// Layers and sprout stage the terrarium shows at one moment.
struct TerrariumState: Equatable {
  var layers: [TerrariumLayer]
  var growthStage: Int
}

/// The live storage terrarium (Dashboard hero and Last Cleanup only).
///
/// Motion follows `MotionPolicy`: the view plays (`isPlaying`, `rendersContinuously`) only while
/// ambient motion is allowed and the view is on screen in a visible window; otherwise it renders
/// single frames of the current state. Reduce Motion never rotates.
struct TerrariumView: NSViewRepresentable {
  enum Mode { case dashboard, afterCleanup }

  var layers: [TerrariumLayer]
  var growthStage: Int
  var mode: Mode
  /// Dashboard: the lens orbits while scanning and this layer glows.
  var isScanning = false
  var glowing: TerrariumLayer.Kind?
  /// After cleanup: the confirmed cleanup to compost once, and the terrarium before it.
  var cleanupID: String?
  var before: TerrariumState?

  @EnvironmentObject private var motion: MotionPolicy

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> TerrariumSCNView {
    let view = TerrariumSCNView(
      frame: .zero,
      options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
    let coordinator = context.coordinator
    view.scene = coordinator.terrarium.scene
    view.pointOfView = coordinator.terrarium.cameraNode
    view.backgroundColor = .clear
    view.antialiasingMode = .multisampling4X
    view.isPlaying = false
    view.rendersContinuously = false
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.image)
    view.onPointer = { [weak coordinator] x in coordinator?.terrarium.setPointer(x) }
    view.onVisibilityChange = { [weak coordinator, weak view] in
      guard let coordinator, let view else { return }
      coordinator.updatePlayback(of: view)
    }
    return view
  }

  func updateNSView(_ view: TerrariumSCNView, context: Context) {
    view.setAccessibilityLabel(TerrariumLayout.accessibilityLabel(for: layers))
    context.coordinator.update(view, with: self, motion: motion.decision)
  }

  @MainActor
  final class Coordinator {
    let terrarium = TerrariumScene()
    private var shown: TerrariumState?
    private var motion = MotionDecision(
      reduceMotion: true, lowPower: false, windowVisible: true, appActive: true)
    /// Cleanups already composted in this run; revisiting Last Cleanup shows the result.
    private static var compostedCleanups: Set<String> = []

    func update(_ view: TerrariumSCNView, with config: TerrariumView, motion: MotionDecision) {
      self.motion = motion
      updatePlayback(of: view)
      let state = TerrariumState(layers: config.layers, growthStage: config.growthStage)
      let animates = terrarium.allowsAnimation

      if config.mode == .afterCleanup, let id = config.cleanupID, let before = config.before,
        !Self.compostedCleanups.contains(id)
      {
        Self.compostedCleanups.insert(id)
        terrarium.apply(layers: before.layers, growthStage: before.growthStage, animated: false)
        shown = state
        if motion.allowsTransitions {
          // A short beat on the old state so the change reads as a change. Whether it animates
          // is decided then: on the first update the view is not in a window yet.
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [terrarium] in
            terrarium.compost(
              duration: terrarium.allowsAnimation ? 1.6 : 0, to: state.layers,
              growthStage: state.growthStage)
          }
        } else {
          terrarium.compost(duration: 0, to: state.layers, growthStage: state.growthStage)
        }
      } else if state != shown {
        if config.mode == .afterCleanup, shown == nil, config.before != nil,
          let id = config.cleanupID, Self.compostedCleanups.contains(id)
        {
          // Composted on an earlier visit: show the settled result, litter gone.
          terrarium.compost(duration: 0, to: state.layers, growthStage: state.growthStage)
        } else {
          terrarium.apply(
            layers: state.layers, growthStage: state.growthStage,
            animated: shown != nil && animates)
        }
        shown = state
      }

      if config.mode == .dashboard {
        terrarium.setScanning(config.isScanning, glowing: config.glowing)
      }
      view.preferredFramesPerSecond = config.isScanning ? 60 : 30
      if !view.isPlaying { view.needsDisplay = true }
    }

    /// Plays only while ambient motion is allowed and the view can be seen; otherwise freezes on
    /// the current state and renders it once.
    func updatePlayback(of view: TerrariumSCNView) {
      let playing = motion.allowsAmbientMotion && view.isVisibleOnScreen
      terrarium.allowsAnimation = playing
      terrarium.setAmbientMotion(playing)
      if view.isPlaying != playing { view.isPlaying = playing }
      if view.rendersContinuously != playing { view.rendersContinuously = playing }
      if !playing { view.needsDisplay = true }
    }
  }
}

/// `SCNView` that reports pointer position and whether it can currently be seen: in a window
/// that is not occluded or minimised, not hidden, and not scrolled out of its scroll view.
final class TerrariumSCNView: SCNView {
  var onPointer: ((Double) -> Void)?
  var onVisibilityChange: (() -> Void)?
  private var observers: [NSObjectProtocol] = []
  private var trackingArea: NSTrackingArea?

  var isVisibleOnScreen: Bool {
    guard let window, !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else { return false }
    #if DEBUG
      // Snapshot runs start from a shell; their window may never report itself visible.
      if DebugSnapshot.isActive { return !window.isMiniaturized }
    #endif
    return window.occlusionState.contains(.visible) && !window.isMiniaturized
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers = []
    if let window {
      observe(NSWindow.didChangeOcclusionStateNotification, of: window)
      observe(NSWindow.didMiniaturizeNotification, of: window)
      observe(NSWindow.didDeminiaturizeNotification, of: window)
    }
    if let clip = enclosingScrollView?.contentView {
      clip.postsBoundsChangedNotifications = true
      observe(NSView.boundsDidChangeNotification, of: clip)
    }
    onVisibilityChange?()
  }

  override func viewDidHide() {
    super.viewDidHide()
    onVisibilityChange?()
  }

  override func viewDidUnhide() {
    super.viewDidUnhide()
    onVisibilityChange?()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    onVisibilityChange?()
  }

  private var lastVisible: Bool?

  private func observe(_ name: Notification.Name, of object: AnyObject) {
    observers.append(
      NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          // Scrolling posts many bounds changes; only a change in visibility matters.
          let visible = self.isVisibleOnScreen
          guard visible != self.lastVisible else { return }
          self.lastVisible = visible
          self.onVisibilityChange?()
        }
      })
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  // MARK: - Pointer

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
      owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseMoved(with event: NSEvent) {
    guard bounds.width > 0 else { return }
    let point = convert(event.locationInWindow, from: nil)
    onPointer?(Double(point.x / bounds.width) - 0.5)
  }

  override func mouseExited(with event: NSEvent) {
    onPointer?(0)
  }
}
