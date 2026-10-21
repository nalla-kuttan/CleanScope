import AppKit

/// The menu bar sprout: a magnifying lens that grows a stem and leaves as caches build up.
/// Template images (no colour), 18 × 18 pt, drawn at whatever scale the screen asks for.
@MainActor
enum SproutTemplateImage {
  static let stageCount = 3
  private static let size = NSSize(width: 18, height: 18)
  private static let cache: [NSImage] = (0..<stageCount).map(makeImage)

  /// The cached template image for a stage (clamped to 0…2).
  static func image(stage: Int) -> NSImage {
    cache[min(max(stage, 0), stageCount - 1)]
  }

  private static func makeImage(stage: Int) -> NSImage {
    // The drawing handler is flipped so the coordinates match the 18 × 18 design (y down).
    let image = NSImage(size: size, flipped: true) { _ in
      draw(stage: stage)
      return true
    }
    image.isTemplate = true
    return image
  }

  private static func draw(stage: Int) {
    NSColor.black.setStroke()
    NSColor.black.setFill()

    let ring = NSBezierPath(ovalIn: NSRect(x: 8 - 5.2, y: 8 - 5.2, width: 10.4, height: 10.4))
    ring.lineWidth = 1.8
    ring.stroke()

    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: 11.8, y: 11.8))
    handle.line(to: NSPoint(x: 15.8, y: 15.8))
    handle.lineWidth = 2
    handle.lineCapStyle = .round
    handle.stroke()

    guard stage >= 1 else { return }

    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: 8, y: 10.5))
    stem.line(to: NSPoint(x: 8, y: 6.4))
    stem.lineWidth = 1.4
    stem.lineCapStyle = .round
    stem.stroke()

    // Left leaf.
    let left = NSBezierPath()
    left.move(to: NSPoint(x: 8, y: 8.6))
    left.curve(
      to: NSPoint(x: 5.4, y: 7.4), controlPoint1: NSPoint(x: 6, y: 8.8),
      controlPoint2: NSPoint(x: 5.4, y: 7.4))
    left.curve(
      to: NSPoint(x: 8, y: 8.6), controlPoint1: NSPoint(x: 5.4, y: 7.4),
      controlPoint2: NSPoint(x: 7.1, y: 6.5))
    left.close()
    left.fill()

    guard stage >= 2 else { return }

    // Right leaf.
    let right = NSBezierPath()
    right.move(to: NSPoint(x: 8, y: 7.6))
    right.curve(
      to: NSPoint(x: 10.5, y: 6.3), controlPoint1: NSPoint(x: 10, y: 7.7),
      controlPoint2: NSPoint(x: 10.5, y: 6.3))
    right.curve(
      to: NSPoint(x: 8, y: 7.6), controlPoint1: NSPoint(x: 10.5, y: 6.3),
      controlPoint2: NSPoint(x: 8.7, y: 5.6))
    right.close()
    right.fill()
  }
}
