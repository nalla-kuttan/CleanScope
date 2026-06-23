#!/usr/bin/env swift

import AppKit
import Foundation

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let outputDirectory = root.appendingPathComponent("Assets/Brand", isDirectory: true)
private let iconsetDirectory = outputDirectory.appendingPathComponent(
  "CleanScope.iconset", isDirectory: true)

private let forest = NSColor(
  calibratedRed: 23.0 / 255.0, green: 111.0 / 255.0, blue: 93.0 / 255.0, alpha: 1)
private let leaf = NSColor(
  calibratedRed: 80.0 / 255.0, green: 183.0 / 255.0, blue: 122.0 / 255.0, alpha: 1)
private let mint = NSColor(
  calibratedRed: 223.0 / 255.0, green: 242.0 / 255.0, blue: 232.0 / 255.0, alpha: 1)
private let ink = NSColor(
  calibratedRed: 23.0 / 255.0, green: 35.0 / 255.0, blue: 31.0 / 255.0, alpha: 1)

private struct IconOutput {
  let filename: String
  let pixels: Int
}

private let outputs = [
  IconOutput(filename: "icon_16x16.png", pixels: 16),
  IconOutput(filename: "icon_16x16@2x.png", pixels: 32),
  IconOutput(filename: "icon_32x32.png", pixels: 32),
  IconOutput(filename: "icon_32x32@2x.png", pixels: 64),
  IconOutput(filename: "icon_128x128.png", pixels: 128),
  IconOutput(filename: "icon_128x128@2x.png", pixels: 256),
  IconOutput(filename: "icon_256x256.png", pixels: 256),
  IconOutput(filename: "icon_256x256@2x.png", pixels: 512),
  IconOutput(filename: "icon_512x512.png", pixels: 512),
  IconOutput(filename: "icon_512x512@2x.png", pixels: 1024),
]

private func leafPath(center: CGPoint, width: CGFloat, height: CGFloat, leaningRight: Bool)
  -> NSBezierPath
{
  let path = NSBezierPath()
  let direction: CGFloat = leaningRight ? 1 : -1
  let base = CGPoint(x: center.x - direction * width * 0.42, y: center.y - height * 0.4)
  let tip = CGPoint(x: center.x + direction * width * 0.48, y: center.y + height * 0.42)
  path.move(to: base)
  path.curve(
    to: tip,
    controlPoint1: CGPoint(x: center.x - direction * width * 0.05, y: center.y + height * 0.5),
    controlPoint2: CGPoint(x: center.x + direction * width * 0.4, y: center.y + height * 0.52)
  )
  path.curve(
    to: base,
    controlPoint1: CGPoint(x: center.x + direction * width * 0.48, y: center.y - height * 0.08),
    controlPoint2: CGPoint(x: center.x + direction * width * 0.02, y: center.y - height * 0.46)
  )
  path.close()
  return path
}

private func drawSproutLens(in rect: CGRect) {
  let scale = rect.width / 1024
  let lensCenter = CGPoint(x: rect.minX + 448 * scale, y: rect.minY + 530 * scale)
  let lensRadius = 242 * scale

  forest.setStroke()
  let lens = NSBezierPath(
    ovalIn: CGRect(
      x: lensCenter.x - lensRadius,
      y: lensCenter.y - lensRadius,
      width: lensRadius * 2,
      height: lensRadius * 2
    ))
  lens.lineWidth = 72 * scale
  lens.stroke()

  let handle = NSBezierPath()
  handle.move(
    to: CGPoint(x: lensCenter.x + 168 * scale, y: lensCenter.y - 172 * scale))
  handle.line(
    to: CGPoint(x: lensCenter.x + 348 * scale, y: lensCenter.y - 352 * scale))
  handle.lineWidth = 88 * scale
  handle.lineCapStyle = .round
  handle.stroke()

  let stem = NSBezierPath()
  stem.move(to: CGPoint(x: lensCenter.x, y: lensCenter.y - 134 * scale))
  stem.curve(
    to: CGPoint(x: lensCenter.x, y: lensCenter.y + 110 * scale),
    controlPoint1: CGPoint(x: lensCenter.x - 10 * scale, y: lensCenter.y - 20 * scale),
    controlPoint2: CGPoint(x: lensCenter.x + 10 * scale, y: lensCenter.y + 38 * scale)
  )
  stem.lineWidth = 38 * scale
  stem.lineCapStyle = .round
  stem.stroke()

  leaf.setFill()
  leafPath(
    center: CGPoint(x: lensCenter.x - 92 * scale, y: lensCenter.y + 82 * scale),
    width: 178 * scale,
    height: 138 * scale,
    leaningRight: false
  ).fill()
  leafPath(
    center: CGPoint(x: lensCenter.x + 96 * scale, y: lensCenter.y + 130 * scale),
    width: 184 * scale,
    height: 146 * scale,
    leaningRight: true
  ).fill()
}

private func renderIcon(pixels: Int, to url: URL) throws {
  guard
    let representation = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixels,
      pixelsHigh: pixels,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: representation)
  else {
    throw CocoaError(.fileWriteUnknown)
  }

  let size = NSSize(width: pixels, height: pixels)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  defer { NSGraphicsContext.restoreGraphicsState() }
  context.imageInterpolation = .high
  let scale = CGFloat(pixels) / 1024
  let field = CGRect(
    x: 54 * scale, y: 54 * scale, width: 916 * scale, height: 916 * scale)

  NSColor.clear.setFill()
  NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow()
  shadow.shadowBlurRadius = 28 * scale
  shadow.shadowOffset = NSSize(width: 0, height: -16 * scale)
  shadow.shadowColor = ink.withAlphaComponent(0.18)
  shadow.set()
  mint.setFill()
  NSBezierPath(roundedRect: field, xRadius: 210 * scale, yRadius: 210 * scale).fill()
  NSGraphicsContext.restoreGraphicsState()

  drawSproutLens(in: CGRect(origin: .zero, size: size))

  context.flushGraphics()
  guard let png = representation.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }
  try png.write(to: url)
}

try FileManager.default.createDirectory(
  at: outputDirectory, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetDirectory)
try FileManager.default.createDirectory(
  at: iconsetDirectory, withIntermediateDirectories: true)

for output in outputs {
  try renderIcon(pixels: output.pixels, to: iconsetDirectory.appendingPathComponent(output.filename))
}

try renderIcon(
  pixels: 1024, to: outputDirectory.appendingPathComponent("AppIcon-1024.png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
  "-c", "icns", iconsetDirectory.path, "-o",
  outputDirectory.appendingPathComponent("CleanScope.icns").path,
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
  throw NSError(
    domain: "CleanScopeBrandAssets", code: Int(process.terminationStatus),
    userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

print("Generated CleanScope brand assets in \(outputDirectory.path)")
