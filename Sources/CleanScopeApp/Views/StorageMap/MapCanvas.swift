import CleanScopeCore
import SwiftUI

/// The storage map drawn in one `Canvas`. Selected tiles lift with a shadow and a check badge.
/// Pointer: hover highlights; a click focuses the tile and toggles its selection (a tile that
/// can't be selected opens instead); a double-click opens a folder. Keyboard: arrows move focus
/// in reading order, Space toggles selection, Return drills in. VoiceOver sees one button per
/// tile.
/// The Sprout Lens magnifies the tile under the pointer, else the focused tile, else it rests on
/// the largest selectable tile.
///
/// While a scan runs, `revealFraction` (the scan's progress) draws tiles right of that fraction of
/// the width as outlines, with a light band at the edge. Tiles in `collapsing` shrink away as
/// `collapseProgress` runs from 0 to 1.
struct MapCanvas: View {
  var tiles: [MapTile]
  /// Ids of the tiles that are selected.
  var selection: Set<String>
  @Binding var focusedID: String?
  var onToggle: (String) -> Void
  var onDrill: (String) -> Void
  /// Reports the tile under the pointer, for the parent's details bar and context menu.
  var onHover: (String?) -> Void = { _ in }
  /// How much of the width the scan has revealed: 1 once the scan has finished or stopped.
  var revealFraction: Double = 1
  /// Ids of tiles shrinking away after a cleanup, and how far (0…1) they have gone.
  var collapsing: Set<String> = []
  var collapseProgress: Double = 0

  @State private var hoveredID: String?
  @State private var pointer: CGPoint?
  @FocusState private var isFocused: Bool
  @EnvironmentObject private var motion: MotionPolicy
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var contrast

  private var colors: MapColors {
    MapColors(isDark: colorScheme == .dark, isIncreased: contrast == .increased)
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      GeometryReader { proxy in
        MapTileLayer(
          tiles: tiles, selection: selection, colors: colors,
          revealX: revealX(in: proxy.size.width), collapsing: collapsing,
          collapseProgress: collapseProgress,
          onActivate: activate,
          onOpen: { onDrill($0.id) }
        )
        .equatable()
      }
      sweepBand
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      highlights
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      GeometryReader { proxy in lens(in: proxy.size) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    .contentShape(Rectangle())
    .onContinuousHover { phase in
      switch phase {
      case .active(let point):
        pointer = point
        setHovered(tile(at: point)?.id)
      case .ended:
        pointer = nil
        setHovered(nil)
      }
    }
    // A double-click opens a folder; a single click toggles a selectable tile and opens a
    // folder that can't be selected. The exclusive pair waits out the double-click interval
    // before a single click lands, a short delay accepted so one click never does both.
    .gesture(
      SpatialTapGesture(count: 2).onEnded { value in
        guard let tile = focusTile(at: value.location) else { return }
        if tile.isDrillable { onDrill(tile.id) } else { activate(tile) }
      }
      .exclusively(
        before: SpatialTapGesture(count: 1).onEnded { value in
          guard let tile = focusTile(at: value.location) else { return }
          activate(tile)
        })
    )
    .focusable()
    .focused($isFocused)
    .focusEffectDisabled()
    .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .space, .return]) { press in
      handle(press.key)
    }
    .onChange(of: tiles) {
      if let focusedID, !tiles.contains(where: { $0.id == focusedID }) { self.focusedID = nil }
      if let hoveredID, !tiles.contains(where: { $0.id == hoveredID }) { setHovered(nil) }
    }
  }

  // MARK: - Scan sweep

  private var isSweeping: Bool { revealFraction < 1 }

  private func revealX(in width: CGFloat) -> CGFloat {
    isSweeping ? CGFloat(min(max(revealFraction, 0), 1)) * width : .infinity
  }

  /// A light band behind the reveal edge, drawn only while the scan runs and ambient motion is
  /// allowed. Reduce Motion still gets the outlines, without the band.
  @ViewBuilder
  private var sweepBand: some View {
    if isSweeping, motion.allowsAmbientMotion {
      GeometryReader { proxy in
        let edge = revealX(in: proxy.size.width)
        LinearGradient(
          colors: [
            colors.color(BrandPalette.accentText).opacity(0),
            colors.color(BrandPalette.accentText).opacity(0.35),
          ],
          startPoint: .leading, endPoint: .trailing
        )
        .frame(width: Self.bandWidth)
        .frame(maxHeight: .infinity)
        .offset(x: edge - Self.bandWidth)
        .animation(motion.animation(.linear(duration: 0.4)), value: edge)
      }
      .clipped()
    }
  }

  static let bandWidth: CGFloat = 90

  // MARK: - Hover and focus

  /// Only the hovered and focused tiles redraw as the pointer or focus moves.
  private var highlights: some View {
    ZStack(alignment: .topLeading) {
      if let tile = tiles.first(where: { $0.id == hoveredID }) {
        let frame = MapTileStyle.frame(of: tile, selected: selection.contains(tile.id))
        // An outline only: a wash over the tile would lower its label's contrast.
        MapTileStyle.path(for: frame.insetBy(dx: 1, dy: 1))
          .stroke(colors.color(BrandPalette.textPrimary).opacity(0.6), lineWidth: 2)
      }
      if isFocused, let tile = tiles.first(where: { $0.id == focusedID }) {
        let frame = MapTileStyle.frame(of: tile, selected: selection.contains(tile.id))
        MapTileStyle.path(for: frame.insetBy(dx: -1.5, dy: -1.5))
          .stroke(colors.color(BrandPalette.accentText), lineWidth: 2.5)
      }
    }
  }

  /// A click or VoiceOver's default action: toggles a selectable tile, else opens it.
  private func activate(_ tile: MapTile) {
    if tile.isSelectable { onToggle(tile.id) } else { onDrill(tile.id) }
  }

  /// The tile under a click, which also takes keyboard focus.
  private func focusTile(at point: CGPoint) -> MapTile? {
    guard let tile = tile(at: point) else { return nil }
    focusedID = tile.id
    isFocused = true
    return tile
  }

  private func setHovered(_ id: String?) {
    guard id != hoveredID else { return }
    hoveredID = id
    onHover(id)
  }

  /// Selected tiles are drawn 4 pt higher, so their lifted frame wins over the tile they
  /// overlap; anything else falls back to the laid-out rects.
  private func tile(at point: CGPoint) -> MapTile? {
    if !selection.isEmpty,
      let lifted = tiles.first(where: {
        selection.contains($0.id) && MapTileStyle.frame(of: $0, selected: true).contains(point)
      })
    {
      return lifted
    }
    return tiles.first { $0.rect.contains(point) }
  }

  // MARK: - Lens

  /// The lens follows the pointer, else the keyboard-focused tile, else rests on the largest
  /// selectable tile. It eases to its target unless Reduce Motion is on.
  @ViewBuilder
  private func lens(in size: CGSize) -> some View {
    if let target = lensTarget, size.width > 0, size.height > 0 {
      let radius = LensGeometry.radius(forWidth: size.width)
      let center = LensGeometry.clamp(target, radius: radius, in: size)
      LensOverlay(
        center: center, radius: radius, zoom: LensGeometry.zoom, tile: tile(at: center),
        tiles: tiles, selection: selection, colors: colors,
        revealX: revealX(in: size.width), collapsing: collapsing,
        collapseProgress: collapseProgress
      )
      .animation(motion.animation(.easeOut(duration: 0.12)), value: center)
    }
  }

  private var lensTarget: CGPoint? {
    if let pointer { return pointer }
    let focused = isFocused ? tiles.first(where: { $0.id == focusedID }) : nil
    guard let tile = focused ?? LensGeometry.restingTile(in: tiles) else { return nil }
    let frame = MapTileStyle.frame(of: tile, selected: selection.contains(tile.id))
    return CGPoint(x: frame.midX, y: frame.midY)
  }

  // MARK: - Keyboard

  private func handle(_ key: KeyEquivalent) -> KeyPress.Result {
    switch key {
    case .space:
      guard let tile = tiles.first(where: { $0.id == focusedID }), tile.isSelectable else {
        return .ignored
      }
      onToggle(tile.id)
      return .handled
    case .return:
      guard let focusedID else { return .ignored }
      onDrill(focusedID)
      return .handled
    case .leftArrow, .upArrow:
      return moveFocus(by: -1)
    default:
      return moveFocus(by: 1)
    }
  }

  /// Moves focus through the tiles sorted top to bottom, then left to right.
  private func moveFocus(by step: Int) -> KeyPress.Result {
    let order = tiles.sorted {
      $0.rect.minY != $1.rect.minY ? $0.rect.minY < $1.rect.minY : $0.rect.minX < $1.rect.minX
    }
    guard !order.isEmpty else { return .ignored }
    guard let current = order.firstIndex(where: { $0.id == focusedID }) else {
      focusedID = (step > 0 ? order.first : order.last)?.id
      return .handled
    }
    let next = min(max(current + step, 0), order.count - 1)
    focusedID = order[next].id
    return .handled
  }
}
