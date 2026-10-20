import AppKit
import CleanScopeCore
import SwiftUI

/// Memoises the storage map's tiles and layout so tones and the treemap are computed once per
/// drilled node, results change or size change, never per hover or per frame.
final class StorageMapCache {
  struct Key: Equatable {
    var sessionID: String?
    var nodeID: String
    var nodeBytes: Int64
    var results: [ScanResult]
    var freeBytes: Int64
  }

  private var key: Key?
  private var tiles: [StorageMapView.Tile] = []
  private var byID: [String: StorageMapView.Tile] = [:]
  private var generation = 0
  private var layoutGeneration = -1
  private var layoutSize: CGSize = .zero
  private var layout: [MapTile] = []

  func tiles(for key: Key, build: () -> [StorageMapView.Tile]) -> [StorageMapView.Tile] {
    if key != self.key {
      self.key = key
      tiles = build()
      byID = Dictionary(tiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      generation += 1
    }
    return tiles
  }

  func tile(_ id: String) -> StorageMapView.Tile? { byID[id] }

  /// Laid-out map tiles for the current tiles in `size`. The top `MapTileStyle.lift` points are
  /// left free so a lifted tile in the first row is not clipped.
  func mapTiles(in size: CGSize) -> [MapTile] {
    guard layoutGeneration != generation || layoutSize != size else { return layout }
    layoutGeneration = generation
    layoutSize = size
    let lift = MapTileStyle.lift
    let bounds = CGRect(
      x: 0, y: lift, width: size.width, height: max(0, size.height - lift))
    layout = TreemapLayout.squarify(items: tiles.map { ($0.id, $0.node.sizeBytes) }, in: bounds)
      .compactMap { placed in
        guard let tile = byID[placed.id] else { return nil }
        return MapTile(
          id: tile.id, name: tile.node.name, bytes: tile.node.sizeBytes, tone: tile.tone,
          rect: placed.rect, isSelectable: tile.isSelectable, isDrillable: tile.canDrill)
      }
    return layout
  }
}

/// The map canvas with its details bar and context menu. Hover state lives here so moving the
/// pointer never rebuilds the parent's tiles.
struct StorageMapArea: View {
  @EnvironmentObject private var model: AppModel
  var tiles: [StorageMapView.Tile]
  var cache: StorageMapCache
  @Binding var focusedID: String?
  var onOpen: (StorageMapView.Tile) -> Void

  @State private var hoveredID: String?

  /// The tile the details bar and context menu describe: the hovered one, else the focused one.
  private var target: StorageMapView.Tile? {
    (hoveredID ?? focusedID).flatMap { cache.tile($0) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      GeometryReader { proxy in
        MapCanvas(
          tiles: cache.mapTiles(in: proxy.size),
          selection: selectedTileIDs,
          focusedID: $focusedID,
          onToggle: toggle,
          onDrill: drill,
          onHover: { hoveredID = $0 }
        )
        .contextMenu { if let target { tileMenu(target) } }
        .help(target.map(tooltip) ?? "")
      }
      .frame(minHeight: 360)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Storage map")
      hoverBar
    }
  }

  private var selectedTileIDs: Set<String> {
    Set(tiles.lazy.filter { $0.result.map { model.selection.contains($0.id) } ?? false }.map(\.id))
  }

  private func toggle(_ id: String) {
    guard let tile = cache.tile(id), tile.isSelectable, let result = tile.result else { return }
    model.toggleSelection(result)
  }

  private func drill(_ id: String) {
    guard let tile = cache.tile(id), tile.canDrill else { return }
    hoveredID = nil
    onOpen(tile)
  }

  @ViewBuilder
  private func tileMenu(_ tile: StorageMapView.Tile) -> some View {
    if tile.canDrill {
      Button("Open") { drill(tile.id) }
    }
    if let result = tile.result, result.canDelete, !result.isExcluded {
      let selected = model.selection.contains(result.id)
      Button(selected ? "Deselect for Cleanup" : "Select for Cleanup") {
        model.setSelection(!selected, for: result)
      }
    }
    if !tile.node.isOtherItems, !tile.isFree {
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tile.node.path)])
      }
    }
  }

  private func selectedBytes(under node: ScanNode) -> Int64 {
    guard !node.isOtherItems, node.id != StorageMapPresentation.freeItemId else { return 0 }
    return model.selectedResults()
      .filter { $0.path == node.path || $0.path.hasPrefix(node.path + "/") }
      .reduce(0) { $0 + $1.sizeBytes }
  }

  private func safetyText(_ tile: StorageMapView.Tile) -> String {
    tile.node.isOtherItems ? "Grouped small items" : MapTileStyle.safetyLabel(for: tile.tone)
  }

  private func tooltip(for tile: StorageMapView.Tile) -> String {
    var lines = [tile.node.name, ByteCount.string(tile.node.sizeBytes)]
    if let modified = tile.node.lastModified {
      lines.append("Modified \(modified.formatted(date: .abbreviated, time: .omitted))")
    }
    lines.append(safetyText(tile))
    let selected = selectedBytes(under: tile.node)
    if selected > 0 { lines.append("Selected: \(ByteCount.string(selected))") }
    return lines.joined(separator: "\n")
  }

  private var hoverBar: some View {
    HStack(spacing: 12) {
      if let tile = target {
        Text(tile.node.name).fontWeight(.semibold).lineLimit(1)
        Text(ByteCount.string(tile.node.sizeBytes)).monospacedDigit()
        if let modified = tile.node.lastModified {
          Text("Modified \(modified.formatted(date: .abbreviated, time: .omitted))")
        }
        if case .category(let category) = tile.tone, !tile.node.isOtherItems {
          SafetyLabel(category: category)
        } else {
          Text(safetyText(tile))
        }
        let selected = selectedBytes(under: tile.node)
        if selected > 0 { Text("Selected \(ByteCount.string(selected))") }
      } else {
        Text("Hover over a tile for details. Right-click to select it for cleanup.")
      }
      Spacer()
    }
    .font(.system(.caption, design: .rounded))
    .foregroundStyle(BrandTheme.textSecondary)
    .frame(height: 18)
  }
}
