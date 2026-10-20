import CleanScopeCore
import SwiftUI

/// One tile on the storage map, already laid out.
struct MapTile: Identifiable, Equatable {
  let id: String
  let name: String
  let bytes: Int64
  let tone: MapTone
  let rect: CGRect
  let isSelectable: Bool
  /// Whether the tile opens to show its contents ("Open" in VoiceOver for selectable tiles).
  var isDrillable = false
}

/// Drawing values shared by the tile layer and the hover/focus overlay.
enum MapTileStyle {
  static let cornerRadius: CGFloat = 6
  static let gap: CGFloat = 2
  static let lift: CGFloat = 4
  static let labelMinimum = CGSize(width: 70, height: 34)
  static let badgeDiameter: CGFloat = 16

  /// The tile's drawn frame: inset for the gap and raised when selected.
  static func frame(of tile: MapTile, selected: Bool) -> CGRect {
    let inset = tile.rect.insetBy(dx: gap / 2, dy: gap / 2)
    return selected ? inset.offsetBy(dx: 0, dy: -lift) : inset
  }

  static func path(for frame: CGRect) -> Path {
    let radius = min(cornerRadius, min(frame.width, frame.height) / 2)
    return Path(roundedRect: frame, cornerRadius: radius, style: .continuous)
  }

  static func fill(for tone: MapTone) -> PaletteColor {
    switch tone {
    case .category(.safeToDelete): return BrandPalette.safeFill
    case .category(.probablyUnused): return BrandPalette.reviewFill
    case .category(.deleteIfAppUnused): return BrandPalette.appFill
    case .category(.doNotBulkDelete): return BrandPalette.keepFill
    case .unclassified: return BrandPalette.unclassifiedFill
    case .free: return BrandPalette.freeFill
    }
  }

  /// Spoken safety label: the category's label, otherwise "Free space" or "Unclassified".
  static func safetyLabel(for tone: MapTone) -> String {
    switch tone {
    case .category(let category): return category.label
    case .free: return "Free space"
    case .unclassified: return "Unclassified"
    }
  }
}

/// Resolves palette tokens to static sRGB colours for one appearance, so the canvas never
/// resolves dynamic colours per tile.
struct MapColors: Equatable {
  var isDark: Bool
  var isIncreased: Bool

  func hex(_ token: PaletteColor) -> UInt32 {
    switch (isDark, isIncreased) {
    case (false, false): return token.light
    case (true, false): return token.dark
    case (false, true): return token.increasedLight
    case (true, true): return token.increasedDark
    }
  }

  func color(_ token: PaletteColor) -> Color {
    let c = BrandPalette.components(hex(token))
    return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
  }
}

/// The static base layer: every tile, its label, and the selection lift. It is `Equatable` so
/// hover and focus changes in the parent never redraw it.
struct MapTileLayer: View, Equatable {
  let tiles: [MapTile]
  let selection: Set<String>
  let colors: MapColors
  /// Maps tile coordinates into the canvas. The lens passes a magnifying transform.
  var transform: CGAffineTransform = .identity
  /// VoiceOver's action for a tile. Not compared: it only forwards to the parent's handlers.
  var onActivate: (MapTile) -> Void = { _ in }
  /// VoiceOver's "Open" action for selectable tiles that can be drilled into.
  var onOpen: (MapTile) -> Void = { _ in }

  static func == (lhs: MapTileLayer, rhs: MapTileLayer) -> Bool {
    lhs.colors == rhs.colors && lhs.transform == rhs.transform
      && lhs.selection == rhs.selection && lhs.tiles == rhs.tiles
  }

  var body: some View {
    Canvas { context, _ in
      context.concatenate(transform)
      draw(in: &context)
    }
    .drawingGroup()
    .accessibilityRepresentation {
      VStack {
        ForEach(tiles) { tile in
          // A selectable tile's button toggles it, so opening it is a named action.
          if tile.isSelectable && tile.isDrillable {
            tileButton(tile).accessibilityAction(named: "Open") { onOpen(tile) }
          } else {
            tileButton(tile)
          }
        }
      }
    }
  }

  private func tileButton(_ tile: MapTile) -> some View {
    Button(accessibilityLabel(for: tile)) { onActivate(tile) }
  }

  /// "Name, 1.2 GB, Safe to delete, selected"; selectable tiles also say whether they are selected.
  func accessibilityLabel(for tile: MapTile) -> String {
    var parts = [tile.name, ByteCount.string(tile.bytes), MapTileStyle.safetyLabel(for: tile.tone)]
    if tile.isSelectable { parts.append(selection.contains(tile.id) ? "selected" : "not selected") }
    return parts.joined(separator: ", ")
  }

  private func draw(in context: inout GraphicsContext) {
    let tones: [MapTone] = SafetyCategory.allCases.map { .category($0) } + [.unclassified, .free]
    var resting: [MapTone: Path] = [:]
    var lifted: [MapTone: Path] = [:]
    var raised: [MapTile] = []

    for tile in tiles {
      let isSelected = selection.contains(tile.id)
      let frame = MapTileStyle.frame(of: tile, selected: isSelected)
      guard frame.width > 0, frame.height > 0 else { continue }
      if isSelected {
        lifted[tile.tone, default: Path()].addPath(MapTileStyle.path(for: frame))
        raised.append(tile)
      } else {
        resting[tile.tone, default: Path()].addPath(MapTileStyle.path(for: frame))
      }
    }

    // One fill per tone keeps thousands of tiles to a handful of draw calls.
    for tone in tones {
      if let path = resting[tone] { context.fill(path, with: shading(for: tone)) }
    }

    if !raised.isEmpty {
      context.drawLayer { layer in
        let shadow = Color.black.opacity(colors.isDark ? 0.5 : 0.22)
        layer.addFilter(.shadow(color: shadow, radius: 14, x: 0, y: 6))
        for tone in tones {
          if let path = lifted[tone] { layer.fill(path, with: shading(for: tone)) }
        }
      }
      var outlines = Path()
      for tile in raised {
        outlines.addPath(MapTileStyle.path(for: MapTileStyle.frame(of: tile, selected: true)))
      }
      context.stroke(outlines, with: .color(colors.color(BrandPalette.accentText)), lineWidth: 1.5)
    }

    for tile in tiles {
      let isSelected = selection.contains(tile.id)
      let frame = MapTileStyle.frame(of: tile, selected: isSelected)
      let hasBadge = isSelected && frame.width >= 30 && frame.height >= 24
      if tile.rect.width >= MapTileStyle.labelMinimum.width,
        tile.rect.height >= MapTileStyle.labelMinimum.height
      {
        drawLabel(tile, in: frame, leavingRoomForBadge: hasBadge, context: &context)
      }
      if hasBadge { drawBadge(in: frame, context: &context) }
    }
  }

  private func drawLabel(
    _ tile: MapTile, in frame: CGRect, leavingRoomForBadge: Bool, context: inout GraphicsContext
  ) {
    let label = colors.color(BrandPalette.labelColor(onFill: MapTileStyle.fill(for: tile.tone)))
    let width = frame.width - 12 - (leavingRoomForBadge ? MapTileStyle.badgeDiameter + 4 : 0)
    guard width > 0 else { return }
    let name = Text(tile.name)
      .font(.system(size: 11, weight: .semibold, design: .rounded))
      .foregroundColor(label)
    let size = Text(ByteCount.string(tile.bytes))
      .font(.system(size: 10, design: .rounded).monospacedDigit())
      .foregroundColor(label)
    let x = frame.minX + 6
    context.draw(name, in: CGRect(x: x, y: frame.minY + 5, width: width, height: 14))
    context.draw(size, in: CGRect(x: x, y: frame.minY + 19, width: frame.width - 12, height: 13))
  }

  private func shading(for tone: MapTone) -> GraphicsContext.Shading {
    .color(colors.color(MapTileStyle.fill(for: tone)))
  }

  /// A filled accent circle with a white check in the tile's top-right corner.
  private func drawBadge(in frame: CGRect, context: inout GraphicsContext) {
    let d = MapTileStyle.badgeDiameter
    let circle = CGRect(x: frame.maxX - d - 5, y: frame.minY + 5, width: d, height: d)
    let ring = Path(ellipseIn: circle.insetBy(dx: -1.5, dy: -1.5))
    context.fill(ring, with: .color(colors.color(BrandPalette.surface)))
    context.fill(Path(ellipseIn: circle), with: .color(colors.color(BrandPalette.accent)))
    var check = Path()
    check.move(to: CGPoint(x: circle.minX + d * 0.28, y: circle.minY + d * 0.52))
    check.addLine(to: CGPoint(x: circle.minX + d * 0.44, y: circle.minY + d * 0.68))
    check.addLine(to: CGPoint(x: circle.minX + d * 0.73, y: circle.minY + d * 0.35))
    context.stroke(
      check, with: .color(.white),
      style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
  }
}
