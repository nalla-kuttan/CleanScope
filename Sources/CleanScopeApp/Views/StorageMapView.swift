import AppKit
import CleanScopeCore
import SwiftUI

/// Treemap of the latest scan. Click a folder to drill in; the breadcrumb or ⌘[ goes back up.
struct StorageMapView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var trail: [String] = []
  @State private var hoveredID: String?
  @State private var showsList = false

  private let classifier = ClassificationService()

  private var root: ScanNode? { model.session?.tree }

  private var current: ScanNode? {
    guard let root else { return nil }
    guard let path = trail.last else { return root }
    return root.node(at: path) ?? root
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header

      if let current {
        breadcrumb(current)
        let tiles = makeTiles(for: current)
        if tiles.isEmpty {
          EmptyStateView(
            title: "Nothing to map here",
            systemImage: "square.grid.3x3",
            message: "This folder has no measurable contents."
          )
        } else if showsList {
          tileList(tiles)
        } else {
          treemap(tiles)
          hoverBar(tiles)
        }
      } else {
        EmptyStateView(
          title: model.isScanning ? "Mapping your folders" : "Run a scan to see the map.",
          systemImage: "square.grid.3x3.square",
          message: model.isScanning
            ? "The map appears when the scan finishes."
            : "The Storage Map shows the folders from your latest scan, sized by how much space they use.",
          commandLabel: model.isScanning ? nil : "Start Scan"
        ) {
          Task {
            await model.startScan(mode: model.settings.scanDeveloperFolders ? .developer : .limited)
          }
        }
      }
    }
    .padding(24)
    .background(BrandTheme.cream)
    .onChange(of: model.session?.id) { _ in trail = [] }
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Storage Map")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(BrandTheme.bark)
        Text("Larger tiles use more space. Click a folder to look inside.")
          .font(.system(.subheadline, design: .rounded))
          .foregroundStyle(BrandTheme.warmGray)
      }
      Spacer()
      Toggle("Show as list", isOn: $showsList)
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(root == nil)
    }
  }

  private func breadcrumb(_ current: ScanNode) -> some View {
    HStack(spacing: 4) {
      Button {
        goUp()
      } label: {
        Image(systemName: "chevron.left")
      }
      .keyboardShortcut("[", modifiers: .command)
      .disabled(trail.isEmpty)
      .help("Back (⌘[)")
      .accessibilityLabel("Back")

      Button(root?.name ?? "Scanned locations") { navigate(to: []) }
        .buttonStyle(.plain)
        .foregroundStyle(trail.isEmpty ? BrandTheme.bark : BrandTheme.sage)
      ForEach(Array(trail.enumerated()), id: \.offset) { index, path in
        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(BrandTheme.warmGray)
        Button(URL(fileURLWithPath: path).lastPathComponent) {
          navigate(to: Array(trail.prefix(index + 1)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(index == trail.count - 1 ? BrandTheme.bark : BrandTheme.sage)
      }
      Spacer()
      Text(ByteCount.string(current.sizeBytes))
        .font(.system(.subheadline, design: .rounded).monospacedDigit())
        .foregroundStyle(BrandTheme.warmGray)
    }
    .font(.system(.subheadline, design: .rounded))
    .lineLimit(1)
  }

  // MARK: - Tiles

  struct Tile: Identifiable {
    var node: ScanNode
    var result: ScanResult?
    var category: SafetyCategory
    var rect: CGRect = .zero
    var id: String { node.id }
    var canDrill: Bool { !node.isOtherItems && !node.children.isEmpty }
  }

  private func makeTiles(for node: ScanNode) -> [Tile] {
    let byID = Dictionary(
      model.streamedResults.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return node.displayChildren().map { child in
      let result = child.resultId.flatMap { byID[$0] }
      let category =
        result?.category
        ?? (child.isOtherItems
          ? .doNotBulkDelete
          : classifier.classify(
            ClassifiedItemInput(
              path: child.path, sizeBytes: child.sizeBytes, itemType: child.itemType)
          ).category)
      return Tile(node: child, result: result, category: category)
    }
  }

  private func treemap(_ tiles: [Tile]) -> some View {
    GeometryReader { proxy in
      let bounds = CGRect(origin: .zero, size: proxy.size)
      let layout = TreemapLayout.squarify(
        items: tiles.map { ($0.id, $0.node.sizeBytes) }, in: bounds)
      let rects = Dictionary(layout.map { ($0.id, $0.rect) }, uniquingKeysWith: { first, _ in first })
      ZStack(alignment: .topLeading) {
        ForEach(tiles) { tile in
          if let rect = rects[tile.id] {
            tileView(tile, rect: rect)
          }
        }
      }
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: trail)
    }
    .frame(minHeight: 360)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Storage map")
  }

  private func tileView(_ tile: Tile, rect: CGRect) -> some View {
    let tint = tile.node.isOtherItems ? BrandTheme.warmGray : tile.category.tintColor
    let isSelected = tile.result.map { model.selection.contains($0.id) } ?? false
    let showsLabel = rect.width >= 60 && rect.height >= 28
    return ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(tint.opacity(hoveredID == tile.id ? 0.32 : 0.2))
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(isSelected ? BrandTheme.sage : tint.opacity(0.55), lineWidth: isSelected ? 2.5 : 1)
      if showsLabel {
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 4) {
            Image(systemName: tile.node.isOtherItems ? "ellipsis.circle" : tile.category.symbolName)
              .foregroundStyle(tint)
            Text(tile.node.name)
              .foregroundStyle(BrandTheme.bark)
              .lineLimit(1)
          }
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          Text(ByteCount.string(tile.node.sizeBytes))
            .font(.system(size: 10, design: .rounded).monospacedDigit())
            .foregroundStyle(BrandTheme.warmGray)
        }
        .padding(6)
      }
    }
    .frame(width: max(0, rect.width - 2), height: max(0, rect.height - 2))
    .position(x: rect.midX, y: rect.midY)
    .contentShape(Rectangle())
    .onHover { hoveredID = $0 ? tile.id : (hoveredID == tile.id ? nil : hoveredID) }
    .onTapGesture { if tile.canDrill { navigate(to: trail + [tile.node.path]) } }
    .contextMenu { tileMenu(tile) }
    .help(tooltip(for: tile))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(tile.node.name), \(ByteCount.string(tile.node.sizeBytes)), \(tile.node.isOtherItems ? "Grouped small items" : tile.category.label)"
    )
    .accessibilityAddTraits(tile.canDrill ? .isButton : [])
    .accessibilityAction { if tile.canDrill { navigate(to: trail + [tile.node.path]) } }
  }

  @ViewBuilder
  private func tileMenu(_ tile: Tile) -> some View {
    if tile.canDrill {
      Button("Open") { navigate(to: trail + [tile.node.path]) }
    }
    if let result = tile.result, result.canDelete, !result.isExcluded {
      let selected = model.selection.contains(result.id)
      Button(selected ? "Deselect for Cleanup" : "Select for Cleanup") {
        model.setSelection(!selected, for: result)
      }
    }
    if !tile.node.isOtherItems {
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tile.node.path)])
      }
    }
  }

  private func selectedBytes(under node: ScanNode) -> Int64 {
    guard !node.isOtherItems else { return 0 }
    return model.selectedResults()
      .filter { $0.path == node.path || $0.path.hasPrefix(node.path + "/") }
      .reduce(0) { $0 + $1.sizeBytes }
  }

  private func tooltip(for tile: Tile) -> String {
    var lines = [tile.node.name, ByteCount.string(tile.node.sizeBytes)]
    if let modified = tile.node.lastModified {
      lines.append("Modified \(modified.formatted(date: .abbreviated, time: .omitted))")
    }
    lines.append(tile.node.isOtherItems ? "Grouped small items" : tile.category.label)
    let selected = selectedBytes(under: tile.node)
    if selected > 0 { lines.append("Selected: \(ByteCount.string(selected))") }
    return lines.joined(separator: "\n")
  }

  private func hoverBar(_ tiles: [Tile]) -> some View {
    let tile = tiles.first { $0.id == hoveredID }
    return HStack(spacing: 12) {
      if let tile {
        Text(tile.node.name).fontWeight(.semibold).lineLimit(1)
        Text(ByteCount.string(tile.node.sizeBytes)).monospacedDigit()
        if let modified = tile.node.lastModified {
          Text("Modified \(modified.formatted(date: .abbreviated, time: .omitted))")
        }
        if tile.node.isOtherItems {
          Text("Grouped small items")
        } else {
          SafetyLabel(category: tile.category)
        }
        let selected = selectedBytes(under: tile.node)
        if selected > 0 { Text("Selected \(ByteCount.string(selected))") }
      } else {
        Text("Hover over a tile for details. Right-click to select it for cleanup.")
      }
      Spacer()
    }
    .font(.system(.caption, design: .rounded))
    .foregroundStyle(BrandTheme.warmGray)
    .frame(height: 18)
  }

  private func tileList(_ tiles: [Tile]) -> some View {
    List(tiles) { tile in
      HStack(spacing: 10) {
        if let result = tile.result {
          SelectionCheckbox(
            state: model.selection.contains(result.id) ? .on : .off,
            isEnabled: result.canDelete && !result.isExcluded,
            accessibilityLabel: "Select \(tile.node.name)"
          ) { _ in model.toggleSelection(result) }
        } else {
          Color.clear.frame(width: 20, height: 20)
        }
        Image(systemName: tile.node.itemType == .folder ? "folder.fill" : "doc.fill")
          .foregroundStyle(tile.category.tintColor)
        Text(tile.node.name).lineLimit(1)
        Spacer()
        Text(ByteCount.string(tile.node.sizeBytes)).monospacedDigit()
        if tile.node.isOtherItems {
          Text("Grouped").foregroundStyle(.secondary)
        } else {
          SafetyLabel(category: tile.category).frame(width: 130, alignment: .leading)
        }
        if tile.canDrill {
          Button {
            navigate(to: trail + [tile.node.path])
          } label: {
            Image(systemName: "chevron.right")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Open \(tile.node.name)")
        }
      }
    }
    .listStyle(.inset)
  }

  // MARK: - Navigation

  private func navigate(to newTrail: [String]) {
    hoveredID = nil
    trail = newTrail
  }

  private func goUp() {
    guard !trail.isEmpty else { return }
    navigate(to: Array(trail.dropLast()))
  }
}
