#if DEBUG
  import AppKit
  import CleanScopeCore
  import SceneKit
  import SwiftUI

  /// Debug-only visual verification: `CleanScopeApp --snapshot-dir <dir> [--dark-preview]`
  /// visits every destination, writes a PNG of the window for each, and quits. Add
  /// `--snapshot-empty` to start without the saved scan. Add `--snapshot-scan-progress <0…1>`
  /// to capture a simulated mid-scan state built from the saved scan. It never scans or cleans.
  /// `--snapshot-scan-cancelled` makes that scan a cancelled one. `--snapshot-collapse` also
  /// collapses a few selected Storage Map tiles as if they were trashed, without touching files.
  /// `--map-fixture <N>` swaps in a synthetic N-item tree; `--map-benchmark` then times the map.
  /// `--snapshot-cleanup` seeds an in-memory cleanup of the largest quick wins before Last
  /// Cleanup (no files are touched) and also captures its terrarium mid-compost.
  /// `--snapshot-select one|all` selects the largest eligible item, or every eligible item, before
  /// the tour so the toolbar basket shows a selection (nothing is cleaned). `--snapshot-flight`
  /// also selects one Ready to Delete item and captures the basket flight mid-air.
  @MainActor
  enum DebugSnapshot {
    static var directory: URL? {
      let args = ProcessInfo.processInfo.arguments
      guard let index = args.firstIndex(of: "--snapshot-dir"), index + 1 < args.count else {
        return nil
      }
      return URL(fileURLWithPath: args[index + 1])
    }

    /// True while a snapshot run is in progress; views skip work that could raise a permission prompt.
    static var isActive: Bool { directory != nil }

    static var startsEmpty: Bool {
      ProcessInfo.processInfo.arguments.contains("--snapshot-empty")
    }

    /// The simulated mid-scan progress (0…1) requested by `--snapshot-scan-progress`, if any.
    static var simulatedScanProgress: Double? {
      let args = ProcessInfo.processInfo.arguments
      guard let index = args.firstIndex(of: "--snapshot-scan-progress"), index + 1 < args.count,
        let value = Double(args[index + 1])
      else { return nil }
      return min(max(value, 0), 1)
    }

    static var simulatesCancelledScan: Bool {
      ProcessInfo.processInfo.arguments.contains("--snapshot-scan-cancelled")
    }

    static var simulatesCollapse: Bool {
      ProcessInfo.processInfo.arguments.contains("--snapshot-collapse")
    }

    /// `--snapshot-select`'s value: "one" or "all".
    static var preselection: String? {
      let args = ProcessInfo.processInfo.arguments
      guard let index = args.firstIndex(of: "--snapshot-select"), index + 1 < args.count else {
        return nil
      }
      return args[index + 1]
    }

    static var capturesFlight: Bool {
      ProcessInfo.processInfo.arguments.contains("--snapshot-flight")
    }

    static var seedsCleanup: Bool {
      ProcessInfo.processInfo.arguments.contains("--snapshot-cleanup")
    }

    /// `--terrarium-cpu-check <seconds>`: instead of capturing, idles on the Dashboard with the
    /// window shown, then minimised, for `seconds` each and prints this process's CPU use
    /// (user + system time over wall time) for both phases.
    static var terrariumCPUCheckSeconds: Double? {
      let args = ProcessInfo.processInfo.arguments
      guard let index = args.firstIndex(of: "--terrarium-cpu-check"), index + 1 < args.count
      else { return nil }
      return Double(args[index + 1])
    }

    private static func runTerrariumCPUCheck(seconds: Double) async {
      func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ time: timeval) -> Double {
          Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
        }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
      }
      func measure(_ phase: String) async {
        let wallStart = Date()
        let cpuStart = cpuSeconds()
        print("terrarium-cpu: \(phase) start")
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        let percent = (cpuSeconds() - cpuStart) / Date().timeIntervalSince(wallStart) * 100
        print(String(format: "terrarium-cpu: %@ %.1f%% of one core", phase, percent))
      }
      guard let window = NSApp.windows.first(where: \.isVisible) else { return }
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      await measure("visible")
      window.miniaturize(nil)
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      print("terrarium-cpu: miniaturized=\(window.isMiniaturized)")
      await measure("minimised")
    }

    static func run(model: AppModel) async {
      if let count = MapFixture.requestedCount {
        let fixture = MapFixture.make(count: count)
        model.debugLoadMapFixture(fixture.session, selection: fixture.selection)
        if MapFixture.isBenchmarking {
          try? await Task.sleep(nanoseconds: 500_000_000)
          MapFixture.runBenchmark(model: model)
          NSApp.terminate(nil)
          return
        }
      }
      guard let directory else { return }
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let appearance =
        ProcessInfo.processInfo.arguments.contains("--dark-preview") ? "dark" : "light"
      let prefix = startsEmpty ? "empty-" : ""
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      if let progress = simulatedScanProgress {
        model.debugSimulateScan(progress: progress, cancelled: simulatesCancelledScan)
      }
      NSApp.windows.first(where: \.isVisible)?.setContentSize(NSSize(width: 1180, height: 760))

      let eligible = ResultSelection.eligible(model.streamedResults)
      switch preselection {
      case "one":
        if let largest = eligible.max(by: { $0.sizeBytes < $1.sizeBytes }) {
          model.setSelection(true, for: largest)
        }
      case "all":
        model.setSelection(true, for: eligible)
      default:
        break
      }
      let reviewed = model.selectedResults()
      print(
        "basket-check: \(reviewed.count) selected, review sheet total "
          + ByteCount.string(SelectionSummary(items: reviewed).totalBytes))

      if let seconds = terrariumCPUCheckSeconds {
        await runTerrariumCPUCheck(seconds: seconds)
        NSApp.terminate(nil)
        return
      }

      captureSidebar(directory.appendingPathComponent("\(prefix)sidebar-\(appearance).png"))
      if let thumbnail = model.terrariumSnapshot?.cgImage(
        forProposedRect: nil, context: nil, hints: nil)
      {
        let name = "\(prefix)menubar-terrarium-\(appearance).png"
        try? NSBitmapImageRep(cgImage: thumbnail).representation(using: .png, properties: [:])?
          .write(to: directory.appendingPathComponent(name))
      }

      for destination in AppModel.Destination.allCases {
        if destination == .lastCleanup, seedsCleanup, model.cleanupSession == nil {
          model.debugSeedCleanup()
          model.destination = destination
          // The terrarium holds the old state for 0.4 s, then composts over 1.6 s.
          try? await Task.sleep(nanoseconds: 1_200_000_000)
          capture(directory.appendingPathComponent("\(prefix)lastCleanup-mid-\(appearance).png"))
          try? await Task.sleep(nanoseconds: 1_800_000_000)
          capture(directory.appendingPathComponent("\(prefix)lastCleanup-\(appearance).png"))
          continue
        }
        model.destination = destination
        try? await Task.sleep(nanoseconds: 900_000_000)
        capture(directory.appendingPathComponent("\(prefix)\(destination.rawValue)-\(appearance).png"))
      }

      if simulatesCollapse {
        let trashed = Set(model.selectedResults().prefix(4).map(\.id))
        model.destination = .storageMap
        try? await Task.sleep(nanoseconds: 900_000_000)
        model.debugCollapseRequest = trashed
        try? await Task.sleep(nanoseconds: 350_000_000)
        capture(directory.appendingPathComponent("\(prefix)collapse-mid-\(appearance).png"))
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        capture(directory.appendingPathComponent("\(prefix)collapse-after-\(appearance).png"))
      }

      if capturesFlight, let item = ResultSelection.eligible(model.results(for: .readyToDelete)).max(by: { $0.sizeBytes < $1.sizeBytes }) {
        model.clearSelection()
        model.destination = .readyToDelete
        try? await Task.sleep(nanoseconds: 900_000_000)
        model.setSelection(true, for: item)
        try? await Task.sleep(nanoseconds: 150_000_000)
        capture(directory.appendingPathComponent("\(prefix)flight-early-\(appearance).png"))
        try? await Task.sleep(nanoseconds: 150_000_000)
        capture(directory.appendingPathComponent("\(prefix)flight-mid-\(appearance).png"))
        try? await Task.sleep(nanoseconds: 700_000_000)
        capture(directory.appendingPathComponent("\(prefix)flight-after-\(appearance).png"))
      }

      if !startsEmpty, let item = model.results(for: .readyToDelete).first {
        model.destination = .readyToDelete
        model.debugDetail = item
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        capture(directory.appendingPathComponent("detail-\(appearance).png"), sheet: true)
        model.debugDetail = nil
      }

      NSApp.windows.first(where: \.isVisible)?.setContentSize(NSSize(width: 820, height: 560))
      model.destination = .readyToDelete
      try? await Task.sleep(nanoseconds: 900_000_000)
      capture(directory.appendingPathComponent("\(prefix)minimum-\(appearance).png"))
      NSApp.terminate(nil)
    }

    /// The sidebar's material can't be drawn in-process, so capture its list view alone.
    private static func captureSidebar(_ url: URL) {
      guard let root = NSApp.windows.first(where: \.isVisible)?.contentView,
        let list = firstTable(in: root)
      else { return }
      for row in 0..<list.numberOfRows {
        if let cell = list.view(atColumn: 0, row: row, makeIfNecessary: true) {
          print("sidebar row \(row): \(texts(in: cell).joined(separator: " | "))")
        }
      }
      let view = list.enclosingScrollView ?? list
      guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
      view.cacheDisplay(in: view.bounds, to: rep)
      try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func texts(in view: NSView) -> [String] {
      var found: [String] = []
      if let field = view as? NSTextField, !field.stringValue.isEmpty { found.append(field.stringValue) }
      if let label = view.accessibilityLabel(), !label.isEmpty, !(view is NSTextField) {
        found.append(label)
      }
      for subview in view.subviews { found += texts(in: subview) }
      return found
    }

    private static func firstTable(in view: NSView) -> NSTableView? {
      if let table = view as? NSTableView { return table }
      for subview in view.subviews {
        if let table = firstTable(in: subview) { return table }
      }
      return nil
    }

    private static func capture(_ url: URL, sheet: Bool = false) {
      guard let main = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil }) else {
        return
      }
      let window = sheet ? (main.attachedSheet ?? main) : main
      guard let view = window.contentView?.superview ?? window.contentView,
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
      else { return }
      view.cacheDisplay(in: view.bounds, to: rep)
      drawSceneViews(in: view, onto: rep)
      try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// `cacheDisplay` can't read Metal-backed SceneKit views, so draw each one's own snapshot
    /// over its frame (clipped to the part that is scrolled into view).
    private static func drawSceneViews(in root: NSView, onto rep: NSBitmapImageRep) {
      let sceneViews = descendants(of: root).compactMap { $0 as? SCNView }
      guard !sceneViews.isEmpty, let context = NSGraphicsContext(bitmapImageRep: rep) else {
        return
      }
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = context
      for sceneView in sceneViews where !sceneView.isHiddenOrHasHiddenAncestor {
        let visible = sceneView.visibleRect
        guard !visible.isEmpty else { continue }
        var frame = sceneView.convert(sceneView.bounds, to: root)
        var clip = sceneView.convert(visible, to: root)
        if root.isFlipped {
          frame.origin.y = root.bounds.height - frame.maxY
          clip.origin.y = root.bounds.height - clip.maxY
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: clip).addClip()
        sceneView.snapshot().draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()
      }
      NSGraphicsContext.restoreGraphicsState()
    }

    private static func descendants(of view: NSView) -> [NSView] {
      view.subviews + view.subviews.flatMap(descendants(of:))
    }
  }

  /// Debug-only Storage Map fixture and benchmark. `--map-fixture <N>` replaces the session with
  /// N sibling items (mixed categories, a few preselected). `--map-benchmark` renders all N as
  /// one `MapCanvas` offscreen 300 times at 1180 × 700, prints the mean, and quits. With no
  /// pointer or focus the lens is drawn at its fixed resting centre on every frame.
  @MainActor
  enum MapFixture {
    static var requestedCount: Int? {
      let args = ProcessInfo.processInfo.arguments
      guard let index = args.firstIndex(of: "--map-fixture"), index + 1 < args.count,
        let count = Int(args[index + 1]), count > 0
      else { return nil }
      return count
    }

    static var isBenchmarking: Bool {
      ProcessInfo.processInfo.arguments.contains("--map-benchmark")
    }

    private static let names = [
      "Caches", "DerivedData", "node_modules", "Downloads", "Simulator Runtimes", "Mail Downloads",
      "Xcode Archives", "Photos Library", "Logs", "Docker", "Homebrew", "Movies",
    ]

    /// The first 48 items are each over 1% of the total so the map shows them as tiles; the rest
    /// are small and fold into "Other items" in the app (the benchmark draws every item).
    static func make(count: Int) -> (session: ScanSession, selection: Set<String>) {
      let unit: Double = 4_000_000_000
      var children: [ScanNode] = []
      var results: [ScanResult] = []
      var selection = Set<String>()
      for index in 0..<count {
        let weight =
          index < 48
          ? 2.0 - 0.02 * Double(index)
          : 26.6 / Double(max(count - 48, 1)) * (0.5 + Double((index * 37) % 100) / 100)
        let size = Int64(unit * weight)
        let name = "\(names[index % names.count]) \(index + 1)"
        let path = "/fixture/\(name)"
        let categories: [SafetyCategory?] = [
          .safeToDelete, .probablyUnused, .deleteIfAppUnused, .doNotBulkDelete, nil,
        ]
        var resultID: String?
        if let category = categories[index % categories.count] {
          let id = "fixture-\(index)"
          let canDelete = category != .doNotBulkDelete
          results.append(
            ScanResult(
              id: id, name: name, path: path, normalizedPath: path, sizeBytes: size,
              itemType: .folder, category: category, confidence: .high, reason: "Map fixture",
              riskNote: "", recommendedAction: "", isHidden: false, isProtected: false,
              isSynced: false, isExcluded: false, canDelete: canDelete,
              deletionMethod: canDelete ? .trash : .notAllowed))
          resultID = id
          if category == .safeToDelete, index % 10 == 0 { selection.insert(id) }
        }
        children.append(
          ScanNode(path: path, name: name, sizeBytes: size, itemType: .folder, resultId: resultID))
      }
      let total = children.reduce(0) { $0 + $1.sizeBytes }
      var session = ScanSession(
        status: .completed, scanMode: .full, diskTotalBytes: total * 2, diskUsedBytes: total,
        diskAvailableBytes: total, scannedPaths: ["/fixture"], skippedPaths: [], results: results)
      session.tree = ScanNode(
        path: "scan://fixture", name: "Map fixture", sizeBytes: total, itemType: .folder,
        children: children)
      return (session, selection)
    }

    static func runBenchmark(model: AppModel) {
      guard let tree = model.session?.tree else {
        print("map-benchmark: no fixture loaded")
        return
      }
      let size = CGSize(width: 1180, height: 700)
      let byID = Dictionary(
        model.streamedResults.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      let nodes = Dictionary(
        tree.children.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      let bounds = CGRect(
        x: 0, y: MapTileStyle.lift, width: size.width, height: size.height - MapTileStyle.lift)
      let tiles = TreemapLayout.squarify(
        items: tree.children.map { ($0.id, $0.sizeBytes) }, in: bounds
      ).compactMap { placed -> MapTile? in
        guard let node = nodes[placed.id] else { return nil }
        let result = node.resultId.flatMap { byID[$0] }
        return MapTile(
          id: node.id, name: node.name, bytes: node.sizeBytes,
          tone: StorageMapPresentation.tone(for: node, results: byID), rect: placed.rect,
          isSelectable: result.map { !ResultSelection.eligible([$0]).isEmpty } ?? false)
      }
      let selected = Set(
        tiles.filter { tile in nodes[tile.id]?.resultId.map(model.selection.contains) ?? false }
          .map(\.id))

      func renderer() -> ImageRenderer<some View> {
        let canvas = MapCanvas(
          tiles: tiles, selection: selected, focusedID: .constant(nil),
          onToggle: { _ in }, onDrill: { _ in }
        )
        .frame(width: size.width, height: size.height)
        .environmentObject(model.motion)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        return renderer
      }
      func render() -> Bool { renderer().cgImage != nil }

      // Warm-up, not timed. With `--snapshot-dir`, it also saves the frame for inspection.
      if let directory = DebugSnapshot.directory, let image = renderer().cgImage {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?
          .write(to: directory.appendingPathComponent("map-benchmark.png"))
        saveLensAlignmentCheck(tiles: tiles, selection: selected, size: size, to: directory)
      } else {
        _ = render()
      }
      let frames = 300
      var durations: [Double] = []
      var rendered = 0
      for _ in 0..<frames {
        let start = DispatchTime.now().uptimeNanoseconds
        if render() { rendered += 1 }
        durations.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
      }
      let mean = durations.reduce(0, +) / Double(frames)
      let sorted = durations.sorted()
      let p95 = sorted[Int(Double(frames) * 0.95) - 1]
      print("map-benchmark: \(tiles.count) tiles, \(selected.count) selected")
      if let rest = LensGeometry.restingTile(in: tiles) {
        let radius = LensGeometry.radius(forWidth: size.width)
        let frame = MapTileStyle.frame(of: rest, selected: selected.contains(rest.id))
        let center = LensGeometry.clamp(
          CGPoint(x: frame.midX, y: frame.midY), radius: radius, in: size)
        print(
          String(
            format: "map-benchmark: lens on at (%.0f, %.0f), radius %.0f, shader %@",
            center.x, center.y, radius, LensShader.isAvailable ? "on" : "off (SwiftUI glass)"))
      } else {
        print("map-benchmark: lens off (no tiles)")
      }
      print("map-benchmark: \(rendered)/\(frames) frames rendered")
      print(String(format: "map-benchmark: p95 %.2f ms, max %.2f ms", p95, sorted.last ?? 0))
      print(String(format: "map-benchmark: mean %.2f ms/frame", mean))
    }

    /// Saves `map-lens-check.png`: the lens pinned on the corner of the resting tile, where
    /// tile edges cross, so the magnified content can be checked against the ring's centre.
    private static func saveLensAlignmentCheck(
      tiles: [MapTile], selection: Set<String>, size: CGSize, to directory: URL
    ) {
      guard let rest = LensGeometry.restingTile(in: tiles) else { return }
      let colors = MapColors(isDark: false, isIncreased: false)
      let radius = LensGeometry.radius(forWidth: size.width)
      let corner = LensGeometry.clamp(
        CGPoint(x: rest.rect.maxX, y: rest.rect.maxY), radius: radius, in: size)
      let view = ZStack(alignment: .topLeading) {
        MapTileLayer(tiles: tiles, selection: selection, colors: colors)
        LensOverlay(
          center: corner, radius: radius, tile: rest, tiles: tiles, selection: selection,
          colors: colors)
      }
      .frame(width: size.width, height: size.height)
      let renderer = ImageRenderer(content: view)
      renderer.scale = 2
      guard let image = renderer.cgImage else { return }
      try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
        .write(to: directory.appendingPathComponent("map-lens-check.png"))
      print(String(format: "map-benchmark: lens check at (%.0f, %.0f)", corner.x, corner.y))
    }
  }
#endif
