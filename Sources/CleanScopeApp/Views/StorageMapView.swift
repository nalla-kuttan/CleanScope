import AppKit
import CleanScopeCore
import SwiftUI

/// Treemap of the latest scan. Click a folder to drill in; the breadcrumb or ⌘[ goes back up.
struct StorageMapView: View {
  @EnvironmentObject private var model: AppModel
  @State private var trail: [String] = []
  @State private var focusedID: String?
  @State private var cache = StorageMapCache()
  @State private var showsList = false
  @State private var review: ReviewRequest?
  /// Tiles shrinking away after a cleanup, and how far (0…1) they have gone.
  @State private var collapsingIDs: Set<String> = []
  @State private var collapseProgress = 0.0
  @EnvironmentObject private var motion: MotionPolicy

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
            message: "This folder has no measurable contents.",
            icon: .map
          )
        } else if showsList {
          tileList(tiles.filter { !$0.isFree })
        } else {
          treemap(tiles)
        }
      } else {
        EmptyStateView(
          title: model.isScanning ? "Mapping your folders" : "Run a scan to see the map.",
          systemImage: "square.grid.3x3.square",
          message: model.isScanning
            ? "The map appears when the scan finishes."
            : "The Storage Map shows the folders from your latest scan, sized by how much space they use.",
          icon: .map,
          commandLabel: model.isScanning ? nil : "Start Scan"
        ) {
          Task {
            await model.startScan(mode: model.settings.scanDeveloperFolders ? .developer : .limited)
          }
        }
      }
    }
    .padding(24)
    .background(BrandTheme.surface)
    .onChange(of: model.session?.id) { trail = [] }
    .harvestBasketToolbar { review = ReviewRequest(items: $0) }
    .sheet(item: $review) { request in
      CleanupReviewSheet(items: request.items) { reviewed in
        Task { await cleanUp(reviewed) }
      }
    }
    #if DEBUG
      .onReceive(model.$debugCollapseRequest) { request in
        guard let request else { return }
        model.debugCollapseRequest = nil
        Task { await debugCollapse(request) }
      }
    #endif
  }

  // MARK: - Scan sweep and collapse

  /// The share of the map the scan has measured: its progress while scanning, else everything
  /// (a cancelled scan keeps all the tiles it found).
  private var revealFraction: Double { model.isScanning ? model.scanProgress : 1 }

  /// Ids of the tiles in the current folder that stand for `resultIDs`.
  private func tileIDs(forResults resultIDs: Set<String>) -> [String: String] {
    guard let current else { return [:] }
    var map: [String: String] = [:]
    for tile in makeTiles(for: current) {
      if let id = tile.result?.id, resultIDs.contains(id) { map[id] = tile.id }
    }
    return map
  }

  /// Cleans up exactly the reviewed items, shrinks the tiles that were trashed, then opens the
  /// report. Reduce Motion skips the shrinking.
  private func cleanUp(_ reviewed: [ScanResult]) async {
    let tileForResult = tileIDs(forResults: Set(reviewed.map(\.id)))
    // Hold the tiles in place while the cleanup runs, so none vanishes before its animation.
    collapsingIDs = Set(tileForResult.values)
    let previous = model.cleanupSession?.id
    await model.cleanup(reviewed, navigatesToReport: false)
    guard model.cleanupSession?.id != previous else {
      collapsingIDs = []
      return
    }
    let deleted = Set(model.cleanupSession?.deletedItems.map(\.scanResultId) ?? [])
    collapsingIDs = Set(tileForResult.filter { deleted.contains($0.key) }.map(\.value))
    let played = await collapse()
    if played { try? await Task.sleep(nanoseconds: 500_000_000) }
    if model.destination == .storageMap { model.destination = .lastCleanup }
  }

  /// Shrinks `collapsingIDs` over `collapseDuration`, then drops them so the layout settles.
  /// Returns whether it animated.
  @discardableResult
  private func collapse() async -> Bool {
    let animates = motion.allowsTransitions && !collapsingIDs.isEmpty
    if animates {
      let start = Date()
      while true {
        let elapsed = Date().timeIntervalSince(start)
        collapseProgress = MapTileStyle.collapseProgress(after: elapsed)
        if elapsed >= MapTileStyle.collapseDuration { break }
        try? await Task.sleep(nanoseconds: 16_000_000)
      }
    }
    collapsingIDs = []
    collapseProgress = 0
    return animates
  }

  #if DEBUG
    /// `--snapshot-collapse`: collapses the tiles for `resultIDs` as if they were just trashed,
    /// without touching the file system.
    private func debugCollapse(_ resultIDs: Set<String>) async {
      collapsingIDs = Set(tileIDs(forResults: resultIDs).values)
      model.debugMarkTrashed(resultIDs)
      await collapse()
    }
  #endif

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .center, spacing: 14) {
      ModuleIcon(key: .map, size: 64)
      VStack(alignment: .leading, spacing: 3) {
        Text("Storage Map")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(BrandTheme.textPrimary)
        Text("Larger tiles use more space. Click a folder to look inside.")
          .font(.system(.subheadline, design: .rounded))
          .foregroundStyle(BrandTheme.textSecondary)
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
        .foregroundStyle(trail.isEmpty ? BrandTheme.textPrimary : BrandTheme.accentText)
      ForEach(Array(trail.enumerated()), id: \.offset) { index, path in
        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(BrandTheme.textSecondary)
        Button(URL(fileURLWithPath: path).lastPathComponent) {
          navigate(to: Array(trail.prefix(index + 1)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(index == trail.count - 1 ? BrandTheme.textPrimary : BrandTheme.accentText)
      }
      Spacer()
      Text(ByteCount.string(current.sizeBytes))
        .font(.system(.subheadline, design: .rounded).monospacedDigit())
        .foregroundStyle(BrandTheme.textSecondary)
    }
    .font(.system(.subheadline, design: .rounded))
    .lineLimit(1)
  }

  // MARK: - Tiles

  struct Tile: Identifiable {
    var node: ScanNode
    var result: ScanResult?
    /// The classifier's category, shown in the list view.
    var category: SafetyCategory
    /// The map colour: the result's category, or the dominant one among its descendants.
    var tone: MapTone
    var id: String { node.id }
    var isFree: Bool { node.id == StorageMapPresentation.freeItemId }
    var canDrill: Bool { !isFree && !node.isOtherItems && !node.children.isEmpty }
    var isSelectable: Bool { result.map { !ResultSelection.eligible([$0]).isEmpty } ?? false }
  }

  /// Tiles for `node`, rebuilt only when the node, the results or the free space change. Free
  /// space joins only at the top of a whole-volume scan.
  private func makeTiles(for node: ScanNode) -> [Tile] {
    let showsFree = model.session.map {
      StorageMapPresentation.showsFreeSpace(scanMode: $0.scanMode, isTopLevel: trail.isEmpty)
    } ?? false
    let freeBytes = showsFree ? (model.disk?.availableBytes ?? 0) : 0
    let key = StorageMapCache.Key(
      sessionID: model.session?.id, nodeID: node.id, nodeBytes: node.sizeBytes,
      results: model.streamedResults, freeBytes: freeBytes,
      trashedIDs: model.trashedResultIDs, collapsingIDs: collapsingIDs)
    return cache.tiles(for: key) {
      buildTiles(for: node, showsFree: showsFree, freeBytes: freeBytes)
    }
  }

  private func buildTiles(for node: ScanNode, showsFree: Bool, freeBytes: Int64) -> [Tile] {
    let byID = Dictionary(
      model.streamedResults.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let children = Dictionary(
      node.displayChildren().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let items = StorageMapPresentation.items(
      for: node, isVolumeRoot: showsFree, freeBytes: freeBytes)
    return items.compactMap { item -> Tile? in
      if item.id == StorageMapPresentation.freeItemId {
        let free = ScanNode(
          path: item.id, name: "Free space", sizeBytes: item.size, itemType: .folder)
        return Tile(node: free, result: nil, category: .safeToDelete, tone: .free)
      }
      guard let child = children[item.id] else { return nil }
      // A trashed item's tile stays only while it shrinks away.
      if let resultId = child.resultId, model.trashedResultIDs.contains(resultId),
        !collapsingIDs.contains(child.id)
      {
        return nil
      }
      let result = child.resultId.flatMap { byID[$0] }
      let category =
        result?.category
        ?? (child.isOtherItems
          ? .doNotBulkDelete
          : classifier.classify(
            ClassifiedItemInput(
              path: child.path, sizeBytes: child.sizeBytes, itemType: child.itemType)
          ).category)
      return Tile(
        node: child, result: result, category: category,
        tone: StorageMapPresentation.tone(for: child, results: byID))
    }
  }

  private func treemap(_ tiles: [Tile]) -> some View {
    StorageMapArea(
      tiles: tiles, cache: cache, focusedID: $focusedID,
      onOpen: { navigate(to: trail + [$0.node.path]) },
      revealFraction: revealFraction, collapsing: collapsingIDs,
      collapseProgress: collapseProgress)
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
          .flightSource(result.id)
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
    focusedID = nil
    trail = newTrail
  }

  /// Goes up one level and keeps keyboard focus on the folder just left.
  private func goUp() {
    guard let left = trail.last else { return }
    navigate(to: Array(trail.dropLast()))
    focusedID = left
  }
}
