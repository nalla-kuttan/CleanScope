import CleanScopeCore
import Metal
import SwiftUI

/// Sizes and placement rules for the Sprout Lens, shared by the map and the debug benchmark.
enum LensGeometry {
  static let zoom: CGFloat = 2.6
  static let ringWidth: CGFloat = 7
  static let handleWidth: CGFloat = 11
  /// The handle runs at 45° from `handleStart` to `handleEnd` times the radius on each axis.
  static let handleStart: CGFloat = 0.72
  static let handleEnd: CGFloat = 1.25

  static func radius(forWidth width: CGFloat) -> CGFloat {
    min(78, max(46, width * 0.075))
  }

  /// Keeps the ring and the handle inside the map.
  static func clamp(_ point: CGPoint, radius: CGFloat, in size: CGSize) -> CGPoint {
    let low = radius + ringWidth / 2 + 2.5
    let reach = radius * handleEnd + handleWidth / 2 + 1.5
    return CGPoint(
      x: min(max(point.x, low), max(low, size.width - reach)),
      y: min(max(point.y, low), max(low, size.height - reach)))
  }

  /// Where the lens rests with no pointer and no keyboard focus: the largest selectable tile,
  /// else the largest tile. It stays there; the lens never roams on its own.
  static func restingTile(in tiles: [MapTile]) -> MapTile? {
    tiles.lazy.filter(\.isSelectable).max { $0.bytes < $1.bytes }
      ?? tiles.max { $0.bytes < $1.bytes }
  }
}

/// The lens's Metal shader from the app bundle's `default.metallib`. When the library or the
/// function is missing (for example a build made without the Metal toolchain), the lens draws
/// its glass in SwiftUI instead.
enum LensShader {
  static let isAvailable: Bool = {
    guard let device = MTLCreateSystemDefaultDevice(),
      let library = try? device.makeDefaultLibrary(bundle: .cleanScope)
    else { return false }
    return library.functionNames.contains("lens")
  }()

  static func shader(center: CGPoint, radius: CGFloat, zoom: CGFloat) -> Shader {
    ShaderLibrary.bundle(.cleanScope).lens(
      .float2(center), .float(Float(radius)), .float(Float(zoom)))
  }
}

/// The Sprout Lens: the map's own tile layer drawn again under a circular mask, magnified by
/// `zoom` around `center`, with a 7 pt accent ring, a handle at 45° and a label bubble naming
/// `tile`. It fills the map's frame and never takes hits or accessibility focus.
struct LensOverlay: View, Animatable {
  var center: CGPoint
  var radius: CGFloat
  var zoom: CGFloat = 2.6
  var tile: MapTile?
  /// The base layer's inputs; the lens draws the same `MapTileLayer`, transformed.
  var tiles: [MapTile] = []
  var selection: Set<String> = []
  var colors = MapColors(isDark: false, isIncreased: false)
  var revealX: CGFloat = .infinity
  var collapsing: Set<String> = []
  var collapseProgress: Double = 0

  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { AnimatablePair(center.x, center.y) }
    set { center = CGPoint(x: newValue.first, y: newValue.second) }
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      glass
        .offset(x: center.x - radius, y: center.y - radius)
      frame
      BubblePlacement(center: center, radius: radius) {
        if let tile { bubble(for: tile) }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  // MARK: - Glass

  /// Base coordinates map to lens coordinates as `radius + (p - center) * zoom`.
  private var transform: CGAffineTransform {
    CGAffineTransform(translationX: radius - center.x * zoom, y: radius - center.y * zoom)
      .scaledBy(x: zoom, y: zoom)
  }

  /// Only tiles that can reach the lens (with room for the lifted shadow) are drawn again.
  private var visibleTiles: [MapTile] {
    let reach = radius / zoom
    let source = CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2)
      .insetBy(dx: -24, dy: -24)
    return tiles.filter { $0.rect.intersects(source) }
  }

  private var glass: some View {
    ZStack(alignment: .topLeading) {
      colors.color(BrandPalette.surface)
      MapTileLayer(
        tiles: visibleTiles, selection: selection, colors: colors, revealX: revealX,
        collapsing: collapsing, collapseProgress: collapseProgress, transform: transform)
    }
    .frame(width: radius * 2, height: radius * 2)
    .modifier(LensGlass(radius: radius, zoom: zoom))
    .clipShape(Circle())
  }

  // MARK: - Ring and handle

  private var frame: some View {
    let accent = colors.color(BrandPalette.accent)
    return ZStack(alignment: .topLeading) {
      // Specular arc along the upper left, as in the concept board.
      Circle()
        .trim(from: 0.55, to: 0.725)
        .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .frame(width: (radius - 6) * 2, height: (radius - 6) * 2)
        .offset(x: center.x - radius + 6, y: center.y - radius + 6)
      Circle()
        .stroke(accent, lineWidth: LensGeometry.ringWidth)
        .frame(width: radius * 2, height: radius * 2)
        .offset(x: center.x - radius, y: center.y - radius)
      Path { path in
        path.move(
          to: CGPoint(
            x: center.x + radius * LensGeometry.handleStart,
            y: center.y + radius * LensGeometry.handleStart))
        path.addLine(
          to: CGPoint(
            x: center.x + radius * LensGeometry.handleEnd,
            y: center.y + radius * LensGeometry.handleEnd))
      }
      .stroke(accent, style: StrokeStyle(lineWidth: LensGeometry.handleWidth, lineCap: .round))
    }
  }

  // MARK: - Label bubble

  private func bubble(for tile: MapTile) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(tile.name) · \(ByteCount.string(tile.bytes))")
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(colors.color(BrandPalette.textPrimary))
      Text(MapTileStyle.safetyLabel(for: tile.tone))
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(colors.color(Self.labelToken(for: tile.tone)))
    }
    .lineLimit(1)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(colors.color(BrandPalette.surface))
        .shadow(color: .black.opacity(colors.isDark ? 0.45 : 0.18), radius: 6, y: 2)
    )
  }

  /// The safety label's text colour: the category's text-grade tint, else secondary text.
  static func labelToken(for tone: MapTone) -> PaletteColor {
    switch tone {
    case .category(.safeToDelete): return BrandPalette.safe
    case .category(.probablyUnused): return BrandPalette.review
    case .category(.deleteIfAppUnused): return BrandPalette.destructive
    case .category(.doNotBulkDelete), .unclassified, .free: return BrandPalette.textSecondary
    }
  }
}

/// Bends and shades the magnified layer with the Metal shader, or draws the same glass shading
/// as gradients when the shader is unavailable.
private struct LensGlass: ViewModifier {
  var radius: CGFloat
  var zoom: CGFloat

  func body(content: Content) -> some View {
    if LensShader.isAvailable {
      content.layerEffect(
        LensShader.shader(center: CGPoint(x: radius, y: radius), radius: radius, zoom: zoom),
        maxSampleOffset: CGSize(width: radius, height: radius))
    } else {
      content.overlay {
        ZStack {
          RadialGradient(
            colors: [.white.opacity(0.28), .white.opacity(0)],
            center: UnitPoint(x: 0.5 - 0.35 / 2, y: 0.5 - 0.4 / 2),
            startRadius: radius * 0.1, endRadius: radius * 0.6)
          RadialGradient(
            stops: [
              .init(color: .black.opacity(0), location: 0.6),
              .init(color: .black.opacity(0.12), location: 1),
            ],
            center: .center, startRadius: 0, endRadius: radius)
        }
      }
    }
  }
}

/// Places the bubble above the lens, or below it when the lens is within 50 pt of the top,
/// and keeps it 6 pt inside the map on every side.
private struct BubblePlacement: Layout {
  var center: CGPoint
  var radius: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard let bubble = subviews.first else { return }
    let margin: CGFloat = 6
    let ideal = bubble.sizeThatFits(.unspecified)
    let width = min(ideal.width, max(0, bounds.width - margin * 2))
    let size = bubble.sizeThatFits(ProposedViewSize(width: width, height: nil))
    let above = center.y - radius - 10 - size.height
    var y = center.y - radius < 50 || above < margin ? center.y + radius + 12 : above
    y = max(margin, min(y, bounds.height - size.height - margin))
    let x = max(margin, min(center.x - size.width / 2, bounds.width - size.width - margin))
    bubble.place(
      at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
      proposal: ProposedViewSize(size))
  }
}
