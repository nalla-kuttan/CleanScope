import CleanScopeCore
import SwiftUI

/// The storage map drawn in one `Canvas`. Selected tiles lift with a shadow and a check badge.
/// Pointer: hover highlights, click focuses and drills. Keyboard: arrows move focus in reading
/// order, Space toggles selection, Return drills in. VoiceOver sees one button per tile.
struct MapCanvas: View {
  var tiles: [MapTile]
  /// Ids of the tiles that are selected.
  var selection: Set<String>
  @Binding var focusedID: String?
  var onToggle: (String) -> Void
  var onDrill: (String) -> Void
  /// Reports the tile under the pointer, for the parent's details bar and context menu.
  var onHover: (String?) -> Void = { _ in }

  @State private var hoveredID: String?
  @FocusState private var isFocused: Bool
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var contrast

  private var colors: MapColors {
    MapColors(isDark: colorScheme == .dark, isIncreased: contrast == .increased)
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      MapTileLayer(tiles: tiles, selection: selection, colors: colors) { tile in
        if tile.isSelectable { onToggle(tile.id) } else { onDrill(tile.id) }
      }
      .equatable()
      highlights
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    .contentShape(Rectangle())
    .onContinuousHover { phase in
      switch phase {
      case .active(let point): setHovered(tile(at: point)?.id)
      case .ended: setHovered(nil)
      }
    }
    .gesture(
      SpatialTapGesture().onEnded { value in
        guard let tile = tile(at: value.location) else { return }
        focusedID = tile.id
        isFocused = true
        onDrill(tile.id)
      }
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

  private func setHovered(_ id: String?) {
    guard id != hoveredID else { return }
    hoveredID = id
    onHover(id)
  }

  private func tile(at point: CGPoint) -> MapTile? {
    tiles.first { $0.rect.contains(point) }
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
