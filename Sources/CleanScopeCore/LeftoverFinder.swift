import Foundation

#if canImport(AppKit)
  import AppKit
#endif

public struct TrashedApp: Equatable, Sendable {
  public var bundleID: String
  public var name: String
  public var path: String
}

/// Finds files left behind by apps the user moved to the Trash. Only exact bundle-id and app-name
/// matches in well-known locations are reported, and never anything a `protect.*` rule covers.
public struct LeftoverFinder: Sendable {
  public static let ruleID = "leftover.trashed-app"

  private let homeDirectory: String
  private let isInstalledElsewhere: @Sendable (String) -> Bool
  private let classifier: ClassificationService

  public init(
    homeDirectory: String = NSHomeDirectory(),
    isInstalledElsewhere: @escaping @Sendable (String) -> Bool = LeftoverFinder.installedOutsideTrash,
    classifier: ClassificationService = ClassificationService()
  ) {
    self.homeDirectory = homeDirectory
    self.isInstalledElsewhere = isInstalledElsewhere
    self.classifier = classifier
  }

  public static let installedOutsideTrash: @Sendable (String) -> Bool = { bundleID in
    #if canImport(AppKit)
      return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
        .contains { !$0.path.contains("/.Trash/") }
    #else
      return false
    #endif
  }

  public func trashedApps() -> [TrashedApp] {
    let trash = URL(fileURLWithPath: homeDirectory).appendingPathComponent(".Trash")
    let entries =
      (try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil))
      ?? []
    return entries.filter { $0.pathExtension == "app" }.compactMap { app in
      let info = app.appendingPathComponent("Contents/Info.plist")
      guard let data = try? Data(contentsOf: info),
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
          as? [String: Any],
        let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty
      else { return nil }
      let name =
        (plist["CFBundleName"] as? String) ?? app.deletingPathExtension().lastPathComponent
      return TrashedApp(bundleID: bundleID, name: name, path: app.path)
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func candidatePaths(for app: TrashedApp) -> [String] {
    let library = URL(fileURLWithPath: homeDirectory).appendingPathComponent("Library").path
    let id = app.bundleID
    return [
      "\(library)/Application Support/\(id)",
      "\(library)/Application Support/\(app.name)",
      "\(library)/Caches/\(id)",
      "\(library)/Containers/\(id)",
      "\(library)/Preferences/\(id).plist",
      "\(library)/Saved Application State/\(id).savedState",
      "\(library)/Logs/\(app.name)",
      "\(library)/HTTPStorages/\(id)",
      "\(library)/WebKit/\(id)",
    ]
  }

  public func leftovers(for app: TrashedApp) -> [ScanResult] {
    guard !isInstalledElsewhere(app.bundleID) else { return [] }
    var seen = Set<String>()
    return candidatePaths(for: app).compactMap { path in
      var isDirectory: ObjCBool = false
      guard seen.insert(path).inserted,
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
      else { return nil }
      let itemType: ItemType = isDirectory.boolValue ? .folder : .file
      let size = Self.allocatedSize(of: URL(fileURLWithPath: path))
      let classified = classifier.classify(
        ClassifiedItemInput(path: path, sizeBytes: size, itemType: itemType))
      if classified.ruleId?.hasPrefix("protect.") == true { return nil }

      var result = classified
      result.category = .probablyUnused
      result.confidence = .medium
      result.reason = "Left behind by \(app.name), which is in the Trash"
      result.riskNote =
        "\(app.name) is in the Trash and no other copy is installed. Review this before removing it, in case you plan to reinstall."
      result.recommendedAction = "Move to Trash"
      result.ownerApp = app.name
      result.ruleId = Self.ruleID
      result.canDelete = !classified.isProtected
      result.deletionMethod = classified.isProtected ? .notAllowed : .trash
      return result
    }
  }

  public func allLeftovers() -> [ScanResult] {
    trashedApps().flatMap(leftovers(for:))
  }

  static func allocatedSize(of url: URL) -> Int64 {
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey]
    guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
    guard values.isDirectory == true else {
      return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }
    var total: Int64 = 0
    let enumerator = FileManager.default.enumerator(
      at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
    while let child = enumerator?.nextObject() as? URL {
      let childValues = try? child.resourceValues(forKeys: keys)
      total += Int64(childValues?.totalFileAllocatedSize ?? childValues?.fileSize ?? 0)
    }
    return total
  }
}
