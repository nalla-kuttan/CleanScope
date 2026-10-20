#if DEBUG
  import AppKit
  import CleanScopeCore
  import SwiftUI

  /// Debug-only visual verification: `CleanScopeApp --snapshot-dir <dir> [--dark-preview]`
  /// visits every destination, writes a PNG of the window for each, and quits. Add
  /// `--snapshot-empty` to start without the saved scan. Add `--snapshot-scan-progress <0…1>`
  /// to capture a simulated mid-scan state built from the saved scan. It never scans or cleans.
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

    static func run(model: AppModel) async {
      guard let directory else { return }
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let appearance =
        ProcessInfo.processInfo.arguments.contains("--dark-preview") ? "dark" : "light"
      let prefix = startsEmpty ? "empty-" : ""
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      if let progress = simulatedScanProgress { model.debugSimulateScan(progress: progress) }
      NSApp.windows.first(where: \.isVisible)?.setContentSize(NSSize(width: 1180, height: 760))

      captureSidebar(directory.appendingPathComponent("\(prefix)sidebar-\(appearance).png"))

      for destination in AppModel.Destination.allCases {
        model.destination = destination
        try? await Task.sleep(nanoseconds: 900_000_000)
        capture(directory.appendingPathComponent("\(prefix)\(destination.rawValue)-\(appearance).png"))
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
      try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
  }
#endif
