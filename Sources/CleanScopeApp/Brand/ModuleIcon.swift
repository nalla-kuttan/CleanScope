import AppKit
import CleanScopeCore
import SwiftUI

/// Loaded module icon images, cached so scrolling and re-rendering never re-read files.
@MainActor
private enum ModuleIconImages {
  static let frameCount = 18
  private static var cache: [String: NSImage] = [:]

  static func still(_ key: ModuleIconKey, pixels: CGFloat) -> NSImage? {
    let suffix = pixels <= 64 ? "@1x" : pixels <= 128 ? "@2x" : "@3x"
    return image(named: "\(key.rawValue)\(suffix)")
  }

  static func frame(_ key: ModuleIconKey, index: Int) -> NSImage? {
    let clamped = min(max(index, 0), frameCount - 1)
    return image(named: "\(key.rawValue)-hover-" + String(format: "%02d", clamped))
  }

  private static func image(named name: String) -> NSImage? {
    if let cached = cache[name] { return cached }
    guard let url = Bundle.cleanScope.url(forResource: name, withExtension: "png"),
      let image = NSImage(contentsOf: url)
    else { return nil }
    cache[name] = image
    return image
  }
}

/// One of the twelve 3D module icons. On hover it plays its 18-frame animation once at 30 fps,
/// rests on the last frame while hovered, and tilts up to 10° toward the pointer. Both are off
/// unless `MotionPolicy.allowsTransitions`. Decorative: hidden from accessibility.
struct ModuleIcon: View {
  var key: ModuleIconKey
  var size: CGFloat = 64

  @EnvironmentObject private var motion: MotionPolicy
  @Environment(\.displayScale) private var displayScale
  @State private var hoverStart: Date?
  @State private var playbackDone = false
  @State private var tilt = CGSize.zero

  private static let framesPerSecond = 30.0
  private static let maxTilt = 10.0

  var body: some View {
    content
      .frame(width: size, height: size)
      .rotation3DEffect(
        .degrees(tilt.width * Self.maxTilt), axis: (x: 0, y: 1, z: 0), perspective: 0.6
      )
      .rotation3DEffect(
        .degrees(-tilt.height * Self.maxTilt), axis: (x: 1, y: 0, z: 0), perspective: 0.6
      )
      .animation(motion.animation(.easeOut(duration: 0.15)), value: tilt)
      .contentShape(Rectangle())
      .onContinuousHover { phase in
        switch phase {
        case .active(let location):
          guard motion.allowsTransitions else { return }
          if hoverStart == nil {
            playbackDone = false
            hoverStart = Date()
          }
          tilt = CGSize(
            width: min(max((location.x / size - 0.5) * 2, -1), 1),
            height: min(max((location.y / size - 0.5) * 2, -1), 1))
        case .ended:
          hoverStart = nil
          playbackDone = false
          tilt = .zero
        }
      }
      .task(id: hoverStart) {
        guard hoverStart != nil else { return }
        let duration = Double(ModuleIconImages.frameCount) / Self.framesPerSecond
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        if !Task.isCancelled { playbackDone = true }
      }
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private var content: some View {
    if let start = hoverStart, motion.allowsTransitions {
      if playbackDone {
        frameView(ModuleIconImages.frameCount - 1)
      } else {
        TimelineView(.animation) { context in
          frameView(Int(context.date.timeIntervalSince(start) * Self.framesPerSecond))
        }
      }
    } else {
      render(ModuleIconImages.still(key, pixels: size * displayScale))
    }
  }

  private func frameView(_ index: Int) -> some View {
    render(ModuleIconImages.frame(key, index: index))
  }

  @ViewBuilder
  private func render(_ image: NSImage?) -> some View {
    if let image {
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
    } else {
      Color.clear
    }
  }
}
