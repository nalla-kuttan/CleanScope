import Foundation

public struct ClassifiedItemInput: Sendable {
  public var path: String
  public var sizeBytes: Int64
  public var itemType: ItemType
  public var lastModified: Date?
  public var isProtected: Bool
  public var isExcluded: Bool

  public init(
    path: String,
    sizeBytes: Int64,
    itemType: ItemType,
    lastModified: Date? = nil,
    isProtected: Bool = false,
    isExcluded: Bool = false
  ) {
    self.path = path
    self.sizeBytes = sizeBytes
    self.itemType = itemType
    self.lastModified = lastModified
    self.isProtected = isProtected
    self.isExcluded = isExcluded
  }
}

public struct ClassificationService: Sendable {
  public init() {}

  public func classify(_ input: ClassifiedItemInput) -> ScanResult {
    let normalized = URL(fileURLWithPath: input.path).standardizedFileURL.path
    let name = URL(fileURLWithPath: normalized).lastPathComponent
    let lower = normalized.lowercased()
    let isHidden = name.hasPrefix(".")
    let isSynced = containsAny(
      lower,
      [
        "/icloud drive/",
        "/mobile documents/",
        "/google drive/",
        "/dropbox/",
        "/onedrive/",
        "/box/",
        "/creative cloud files/",
      ])

    typealias Match = (
      category: SafetyCategory,
      confidence: Confidence,
      reason: String,
      risk: String,
      ownerApp: String?,
      ownerTool: String?
    )
    var matches: [Match] = []

    if isSynced {
      matches.append(
        (
          .doNotBulkDelete,
          .high,
          "Cloud-synced location",
          "Deleting synced files can remove them from other devices.",
          nil,
          nil
        ))
    }

    if containsAny(
      lower,
      [
        "/documents", "/desktop", "photos library.photoslibrary", "music library",
        "/mail/", "/messages/", "/notes/", "1password", "bitwarden",
        "/application support/google/chrome", "/application support/firefox",
        ".vmwarevm", ".pvm", ".vbox", ".xcodeproj", ".xcworkspace", "/.git",
      ])
    {
      matches.append(
        (
          .doNotBulkDelete,
          .high,
          "Personal, synced, source, or app-critical data",
          "These files may contain personal or app-critical data. Review manually in Finder.",
          nil,
          nil
        ))
    }

    let generatedFolderNames = [
      "__pycache__", ".next", ".dart_tool", "deriveddata", "target", "build", "dist", ".turbo",
      ".vite",
    ]
    if containsAny(
      lower,
      [
        "/library/caches/", "/library/logs/", "/tmp/", "/private/var/folders/",
        "/library/developer/xcode/deriveddata/",
      ])
      || generatedFolderNames.contains(name.lowercased())
    {
      matches.append(
        (
          .safeToDelete,
          .high,
          "Temporary, cache, log, or generated build data",
          "These files are usually temporary or generated. The related app may rebuild them later.",
          nil,
          ownerTool(for: lower)
        ))
    }

    if lower.contains("/downloads/"),
      ["dmg", "zip", "pkg", "iso"].contains(
        URL(fileURLWithPath: normalized).pathExtension.lowercased())
    {
      matches.append(
        (
          .probablyUnused,
          .medium,
          "Installer or archive in Downloads",
          "These files look unused based on type, age, or location. Review them before deleting.",
          nil,
          nil
        ))
    }

    if lower.contains("/.trash/") {
      matches.append(
        (
          .safeToDelete,
          .high,
          "Trash contents",
          "Trash contents are usually safe to remove after review.",
          nil,
          nil
        ))
    }

    if lower.contains("/.docker/volumes") {
      matches.append(
        (
          .deleteIfAppUnused,
          .high,
          "Docker volume",
          "Docker volumes may contain persistent databases or application data.",
          nil,
          "Docker"
        ))
    } else if containsAny(
      lower,
      [
        "/.docker", "/library/developer/coresimulator", "/android/sdk", "/.gradle",
        "/.m2", "/.npm", "/.yarn", "/.pnpm-store", "/.cargo", "/.pub-cache",
        "/library/application support/",
      ])
    {
      matches.append(
        (
          .deleteIfAppUnused,
          .medium,
          "App or developer tool storage",
          "These files belong to a specific app or tool. Delete them only if you understand the consequence.",
          nil,
          ownerTool(for: lower)
        ))
    }

    let selected =
      matches.max { $0.category < $1.category } ?? (
        .doNotBulkDelete,
        .low,
        "Unknown item",
        "Unknown files are not labeled as junk. Review manually in Finder.",
        nil,
        nil
      )
    let canDelete = selected.category == .safeToDelete || selected.category == .probablyUnused
    let method: DeletionMethod = canDelete ? .trash : .manualReview
    let isUnavailable = input.isProtected || input.isExcluded

    return ScanResult(
      name: name,
      path: input.path,
      normalizedPath: normalized,
      sizeBytes: input.sizeBytes,
      itemType: input.itemType,
      category: selected.category,
      confidence: selected.confidence,
      reason: selected.reason,
      riskNote: selected.risk,
      recommendedAction: method == .trash ? "Move to Trash" : "Review manually in Finder",
      lastModified: input.lastModified,
      ownerApp: selected.ownerApp,
      ownerTool: selected.ownerTool,
      fileExtension: URL(fileURLWithPath: normalized).pathExtension.isEmpty
        ? nil
        : URL(fileURLWithPath: normalized).pathExtension,
      isHidden: isHidden,
      isProtected: input.isProtected,
      isSynced: isSynced,
      isExcluded: input.isExcluded,
      canDelete: canDelete && !isUnavailable,
      deletionMethod: isUnavailable ? .notAllowed : method
    )
  }

  private func containsAny(_ text: String, _ needles: [String]) -> Bool {
    needles.contains { text.contains($0.lowercased()) }
  }

  private func ownerTool(for lowerPath: String) -> String? {
    if lowerPath.contains("xcode") || lowerPath.contains("deriveddata")
      || lowerPath.contains("coresimulator")
    {
      return "Xcode"
    }
    if lowerPath.contains(".docker") { return "Docker" }
    if lowerPath.contains(".gradle") || lowerPath.contains("android") { return "Android" }
    if lowerPath.contains(".npm") || lowerPath.contains(".yarn")
      || lowerPath.contains(".pnpm-store") || lowerPath.contains(".next")
    {
      return "Node.js"
    }
    if lowerPath.contains("__pycache__") || lowerPath.contains("pip") || lowerPath.contains(".venv")
    {
      return "Python"
    }
    if lowerPath.contains(".dart_tool") || lowerPath.contains(".pub-cache") {
      return "Flutter/Dart"
    }
    if lowerPath.contains(".cargo") || lowerPath.contains("/target") { return "Rust" }
    return nil
  }
}
