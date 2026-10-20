import Foundation

#if canImport(AppKit)
  import AppKit
#endif

public struct ClassifiedItemInput: Sendable {
  public var path: String
  public var sizeBytes: Int64
  public var itemType: ItemType
  public var lastModified: Date?
  public var isProtected: Bool
  public var isExcluded: Bool
  public var isCloudOnly: Bool
  public var cloudOnlyBytes: Int64
  public var requiresAdmin: Bool

  public init(
    path: String,
    sizeBytes: Int64,
    itemType: ItemType,
    lastModified: Date? = nil,
    isProtected: Bool = false,
    isExcluded: Bool = false,
    isCloudOnly: Bool = false,
    cloudOnlyBytes: Int64 = 0,
    requiresAdmin: Bool = false
  ) {
    self.path = path
    self.sizeBytes = sizeBytes
    self.itemType = itemType
    self.lastModified = lastModified
    self.isProtected = isProtected
    self.isExcluded = isExcluded
    self.isCloudOnly = isCloudOnly
    self.cloudOnlyBytes = cloudOnlyBytes
    self.requiresAdmin = requiresAdmin
  }
}

public struct ClassificationService: Sendable {
  private struct Context {
    var normalizedPath: String
    var lowerPath: String
    var pathComponents: Set<String>
    var name: String
    var lowerName: String
    var fileExtension: String?
    var itemType: ItemType
    var lastModified: Date?
    var now: Date
  }

  /// Turns a bundle identifier into a display name, or nil when the app is unknown.
  public typealias AppNameResolver = @Sendable (_ bundleIdentifier: String) -> String?

  private let now: @Sendable () -> Date
  private let appName: AppNameResolver
  public let rules: [ClassificationRule]

  public init(
    rules: [ClassificationRule] = ClassificationService.builtInRules,
    appName: @escaping AppNameResolver = ClassificationService.installedAppName,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.rules = rules
    self.appName = appName
    self.now = now
  }

  public static let installedAppName: AppNameResolver = { bundleIdentifier in
    #if canImport(AppKit)
      guard
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
        let bundle = Bundle(url: url)
      else { return nil }
      return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? url.deletingPathExtension().lastPathComponent
    #else
      return nil
    #endif
  }

  /// Rules whose owner app is the folder directly inside Application Support.
  private static let applicationSupportOwnerRules: Set<String> = ["safe.chromium-caches"]

  /// Folder names Chromium and Electron apps use for regenerable caches.
  public static let chromiumCacheNames = [
    "cache", "code cache", "gpucache", "dawncache", "dawngraphitecache",
  ]

  /// Chromium folders that hold user state and must never be treated as cache.
  private static let chromiumUserState = [
    "local storage", "indexeddb", "session storage", "service worker", "cookies", "databases",
  ]

  private static let systemLogPrefix: ClassificationRule.Matcher = .any([
    .pathPrefix("/private/var/log/"), .pathPrefix("/var/log/"),
  ])
  private static let rotatedLogName: ClassificationRule.Matcher = .nameMatches(
    #"\.\d+\.(gz|bz2)$"#)

  /// Rule ids that other rules may override. Everything else, and `protect.*` above all, is fixed.
  public static let overridableRuleIDs: Set<String> = [
    "tool.application-support", "tool.developer-storage",
  ]

  /// Returns one message per invalid `overrides` entry; empty when the rule set is valid.
  public static func validateOverrides(_ rules: [ClassificationRule]) -> [String] {
    rules.flatMap { rule in
      rule.overrides.compactMap { target -> String? in
        if target.hasPrefix("protect.") {
          return "\(rule.id) may not override protected rule \(target)"
        }
        if !overridableRuleIDs.contains(target) {
          return "\(rule.id) overrides \(target), which is not overridable"
        }
        return nil
      }
    }
  }

  public static let builtInRules: [ClassificationRule] = [
    ClassificationRule(
      id: "protect.cloud-synced",
      name: "Cloud-synced folder",
      matcher: .any([
        .pathContains("/library/mobile documents/"),
        .pathComponent("icloud drive"),
        .pathComponent("google drive"),
        .pathComponent("dropbox"),
        .pathComponent("onedrive"),
        .pathComponent("box"),
        .pathComponent("creative cloud files"),
      ]),
      category: .doNotBulkDelete,
      confidence: .high,
      specificity: 100,
      reason: "Cloud-synced location",
      riskNote: "Deleting synced files can remove them from other devices."
    ),
    ClassificationRule(
      id: "protect.personal-folders",
      name: "Personal folder",
      matcher: .any([
        .pathComponent("desktop"),
        .pathComponent("documents"),
        .pathContains("photos library.photoslibrary"),
        .pathContains("/music/music library"),
      ]),
      category: .doNotBulkDelete,
      confidence: .high,
      specificity: 95,
      reason: "Personal files",
      riskNote: "These files may contain personal data. Review them manually in Finder."
    ),
    ClassificationRule(
      id: "protect.app-critical-data",
      name: "App-critical data",
      matcher: .any([
        .pathContains("/library/mail/"),
        .pathContains("/library/messages/"),
        .pathContains("/library/notes/"),
        .pathContains("/application support/google/chrome"),
        .pathContains("/application support/firefox"),
        .pathContains("/application support/1password"),
        .pathContains("/application support/bitwarden"),
        .pathComponent("1password"),
        .pathComponent("bitwarden"),
      ]),
      category: .doNotBulkDelete,
      confidence: .high,
      specificity: 100,
      reason: "App-critical profile or database",
      riskNote: "This location may contain profiles, settings, credentials, or message history."
    ),
    ClassificationRule(
      id: "protect.source-code",
      name: "Source code",
      matcher: .any([
        .pathComponent(".git"),
        .pathComponent(".svn"),
        .pathComponent("src"),
        .pathComponent("source"),
        .pathComponent("sources"),
        .extensionIn([
          "c", "cc", "cpp", "cs", "go", "h", "hpp", "java", "js", "jsx", "kt", "kts", "m",
          "mm", "php", "py", "rb", "rs", "scala", "swift", "ts", "tsx", "xcodeproj",
          "xcworkspace",
        ]),
      ]),
      category: .doNotBulkDelete,
      confidence: .high,
      specificity: 90,
      reason: "Source code or repository data",
      riskNote: "Source files must not be removed through bulk cleanup."
    ),
    ClassificationRule(
      id: "protect.virtual-machines",
      name: "Virtual machine",
      matcher: .extensionIn(["pvm", "vbox", "vdi", "vhd", "vhdx", "vmdk", "vmwarevm"]),
      category: .doNotBulkDelete,
      confidence: .high,
      specificity: 95,
      reason: "Virtual machine data",
      riskNote:
        "Virtual machine bundles and disks may contain complete operating systems and files."
    ),
    ClassificationRule(
      id: "safe.known-caches",
      name: "Known cache or temporary data",
      matcher: .any([
        .pathContains("/library/caches/"),
        .pathContains("/library/logs/"),
        .pathContains("/private/var/folders/"),
        .pathPrefix("/var/folders/"),
        .pathComponent("tmp"),
        .pathContains("/library/developer/xcode/deriveddata/"),
      ]),
      category: .safeToDelete,
      confidence: .high,
      specificity: 70,
      reason: "Known cache, log, or temporary data",
      riskNote: "These files are temporary and the related app may rebuild them later."
    ),
    ClassificationRule(
      id: "safe.generated-folders",
      name: "Generated developer folder",
      matcher: .all([
        .itemType(.folder),
        .any([
          .nameEquals("__pycache__"),
          .nameEquals(".next"),
          .nameEquals(".dart_tool"),
          .nameEquals(".turbo"),
          .nameEquals(".vite"),
          .nameEquals("deriveddata"),
          .nameEquals("target"),
          .nameEquals("build"),
          .nameEquals("dist"),
        ]),
      ]),
      category: .safeToDelete,
      confidence: .high,
      specificity: 75,
      reason: "Generated build data",
      riskNote: "This folder is generated by a development tool and may be rebuilt later."
    ),
    ClassificationRule(
      id: "safe.package-caches",
      name: "Package manager cache",
      matcher: .any([
        .pathComponent(".npm"),
        .pathComponent(".yarn"),
        .pathComponent(".pnpm-store"),
        .pathContains("/library/caches/pip"),
        .pathContains("/.cache/pip"),
      ]),
      category: .safeToDelete,
      confidence: .high,
      specificity: 75,
      reason: "Package manager cache",
      riskNote: "Downloaded packages may need to be fetched again after deletion."
    ),
    ClassificationRule(
      id: "safe.trash",
      name: "Trash contents",
      matcher: .pathComponent(".trash"),
      category: .safeToDelete,
      confidence: .high,
      specificity: 80,
      reason: "Trash contents",
      riskNote: "Trash contents are safe to remove after confirmation."
    ),
    ClassificationRule(
      id: "safe.container-caches",
      name: "Sandboxed app cache",
      matcher: .all([
        .pathContains("/library/containers/"),
        .itemType(.folder),
        .nameEquals("caches"),
        .pathContains("/data/library/caches"),
      ]),
      category: .safeToDelete,
      confidence: .high,
      specificity: 80,
      reason: "Sandboxed app cache",
      riskNote: "The app rebuilds this cache. It may start a little slower the first time."
    ),
    ClassificationRule(
      id: "safe.chromium-caches",
      name: "Chromium app cache",
      matcher: .all([
        .pathContains("/library/application support/"),
        .itemType(.folder),
        .any(chromiumCacheNames.map { .nameEquals($0) }),
        .not(.any(chromiumUserState.map { .pathComponent($0) })),
      ]),
      category: .safeToDelete,
      confidence: .high,
      specificity: 85,
      reason: "Chromium app cache",
      riskNote: "The app rebuilds this cache. It may start a little slower the first time.",
      overrides: ["tool.application-support"]
    ),
    ClassificationRule(
      id: "safe.spotify-cache",
      name: "Spotify cache",
      matcher: .all([
        .pathContains("/library/application support/spotify/persistentcache/"),
        .nameEquals("storage"),
      ]),
      category: .safeToDelete,
      confidence: .high,
      specificity: 88,
      reason: "Spotify streaming cache",
      riskNote: "Spotify downloads songs again as you play them. Downloaded playlists are kept.",
      ownerApp: "Spotify",
      overrides: ["tool.application-support"]
    ),
    ClassificationRule(
      id: "safe.adobe-media-cache",
      name: "Adobe media cache",
      matcher: .all([
        .pathContains("/library/application support/adobe/common/"),
        .nameEquals("media cache files"),
      ]),
      category: .safeToDelete,
      confidence: .high,
      specificity: 88,
      reason: "Adobe media cache",
      riskNote: "Adobe apps rebuild these files when you open a project again.",
      ownerApp: "Adobe",
      overrides: ["tool.application-support"]
    ),
    ClassificationRule(
      id: "review.telegram-media",
      name: "Telegram downloaded media",
      matcher: .all([
        .pathContains("/library/application support/telegram desktop/tdata/"),
        .nameEquals("user_data"),
      ]),
      category: .probablyUnused,
      confidence: .medium,
      specificity: 88,
      reason: "Telegram downloaded media",
      riskNote: "Some media may no longer be available on Telegram's servers. Review it first.",
      ownerApp: "Telegram",
      overrides: ["tool.application-support"]
    ),
    ClassificationRule(
      id: "safe.rotated-logs",
      name: "Rotated system log",
      matcher: .all([systemLogPrefix, .itemType(.file), rotatedLogName]),
      category: .safeToDelete,
      confidence: .high,
      specificity: 80,
      reason: "Old compressed system log",
      riskNote: "macOS no longer writes to this log. Removing it needs an administrator."
    ),
    ClassificationRule(
      id: "review.live-system-logs",
      name: "Active system log",
      matcher: .all([systemLogPrefix, .itemType(.file), .not(rotatedLogName)]),
      category: .probablyUnused,
      confidence: .low,
      specificity: 60,
      reason: "System log that may still be in use",
      riskNote: "A system process may still be writing to this log. Review it before removing."
    ),
    ClassificationRule(
      id: "safe.diagnostic-reports",
      name: "Diagnostic reports",
      matcher: .pathComponent("diagnosticreports"),
      category: .safeToDelete,
      confidence: .high,
      specificity: 80,
      reason: "Crash and diagnostic reports",
      riskNote: "These reports are only needed if you plan to send them to a developer."
    ),
    ClassificationRule(
      id: "review.old-downloads",
      name: "Old Downloads item",
      matcher: .all([
        .pathComponent("downloads"),
        .modifiedAtLeastDaysAgo(90),
      ]),
      category: .probablyUnused,
      confidence: .medium,
      specificity: 60,
      reason: "Item in Downloads is at least 90 days old",
      riskNote: "This item looks unused based on age and location. Review it before deleting."
    ),
    ClassificationRule(
      id: "tool.docker-volumes",
      name: "Docker volume",
      matcher: .pathContains("/.docker/volumes/"),
      category: .deleteIfAppUnused,
      confidence: .high,
      specificity: 100,
      reason: "Docker volume",
      riskNote: "Docker volumes may contain persistent databases or application data.",
      ownerTool: "Docker"
    ),
    ClassificationRule(
      id: "tool.developer-storage",
      name: "Developer tool storage",
      matcher: .any([
        .pathComponent(".docker"),
        .pathContains("/library/developer/coresimulator"),
        .pathContains("/android/sdk"),
        .pathComponent(".gradle"),
        .pathComponent(".m2"),
        .pathComponent(".cargo"),
        .pathComponent(".pub-cache"),
      ]),
      category: .deleteIfAppUnused,
      confidence: .medium,
      specificity: 50,
      reason: "Developer tool storage",
      riskNote: "Delete this data only if you understand how the related tool uses it."
    ),
    ClassificationRule(
      id: "tool.application-support",
      name: "Application Support folder",
      matcher: .pathContains("/library/application support/"),
      category: .deleteIfAppUnused,
      confidence: .medium,
      specificity: 40,
      reason: "Application Support data",
      riskNote: "This folder may contain settings, databases, sessions, or user-created app data."
    ),
  ]

  public func classify(_ input: ClassifiedItemInput) -> ScanResult {
    let context = makeContext(for: input)
    let matching = rules.filter { matches($0.matcher, context: context) }
    let overridden = Set(
      matching.flatMap(\.overrides).filter { Self.overridableRuleIDs.contains($0) })
    let selected =
      matching
      .filter { !overridden.contains($0.id) }
      .max { lhs, rhs in
        if lhs.category != rhs.category { return lhs.category < rhs.category }
        if lhs.confidence != rhs.confidence {
          return confidenceRank(lhs.confidence) < confidenceRank(rhs.confidence)
        }
        return lhs.specificity < rhs.specificity
      }

    let category = selected?.category ?? .doNotBulkDelete
    let confidence = selected?.confidence ?? .low
    let reason = selected?.reason ?? "Unknown item"
    let riskNote =
      selected?.riskNote
      ?? "Unknown files are not labeled as junk. Review this item manually in Finder."
    let canMoveToTrash =
      (category == .safeToDelete || category == .probablyUnused) && !input.isCloudOnly
    let unavailable = input.isProtected || input.isExcluded
    let deletionMethod: DeletionMethod =
      unavailable ? .notAllowed : (canMoveToTrash ? .trash : .manualReview)

    let containerIdentifier = containerCacheIdentifier(context)
    let resolvedContainerApp = containerIdentifier.flatMap(appName)
    let displayName =
      containerIdentifier.map { "\(resolvedContainerApp ?? $0) cache (\($0))" } ?? context.name
    let ownerApp =
      selected?.ownerApp
      ?? containerIdentifier.map { resolvedContainerApp ?? $0 }
      ?? applicationSupportOwner(rule: selected, path: context.normalizedPath)

    return ScanResult(
      name: displayName,
      path: input.path,
      normalizedPath: context.normalizedPath,
      sizeBytes: input.sizeBytes,
      itemType: input.itemType,
      category: category,
      confidence: confidence,
      reason: reason,
      riskNote: riskNote,
      recommendedAction: recommendedAction(for: deletionMethod),
      lastModified: input.lastModified,
      ownerApp: ownerApp,
      ownerTool: selected?.ownerTool ?? inferredOwnerTool(for: context),
      fileExtension: context.fileExtension,
      isHidden: context.name.hasPrefix("."),
      isProtected: input.isProtected,
      isSynced: isSynced(context),
      isExcluded: input.isExcluded,
      canDelete: canMoveToTrash && !unavailable,
      deletionMethod: deletionMethod,
      isCloudOnly: input.isCloudOnly,
      cloudOnlyBytes: input.cloudOnlyBytes,
      requiresAdmin: input.requiresAdmin,
      ruleId: selected?.id
    )
  }

  /// The bundle identifier for a container's `Data/Library/Caches` folder itself, else nil.
  private func containerCacheIdentifier(_ context: Context) -> String? {
    guard context.itemType == .folder, context.lowerName == "caches" else { return nil }
    let components = URL(fileURLWithPath: context.normalizedPath).pathComponents
    guard
      let index = components.lastIndex(where: { $0.lowercased() == "containers" }),
      components.count == index + 5,
      components[index - 1].lowercased() == "library",
      components[index + 2].lowercased() == "data",
      components[index + 3].lowercased() == "library"
    else { return nil }
    let containerURL = URL(fileURLWithPath: components[...(index + 1)].joined(separator: "/"))
    return ScanLocations.containerBundleIdentifier(containerURL: containerURL)
  }

  private func applicationSupportOwner(rule: ClassificationRule?, path: String) -> String? {
    guard let rule, Self.applicationSupportOwnerRules.contains(rule.id) else { return nil }
    let components = URL(fileURLWithPath: path).pathComponents
    guard
      let index = components.lastIndex(where: {
        $0.caseInsensitiveCompare("Application Support") == .orderedSame
      }),
      index + 1 < components.count
    else { return nil }
    return components[index + 1]
  }

  private func makeContext(for input: ClassifiedItemInput) -> Context {
    let normalizedPath = URL(fileURLWithPath: input.path).standardizedFileURL.path
    let url = URL(fileURLWithPath: normalizedPath)
    let fileExtension = url.pathExtension.isEmpty ? nil : url.pathExtension.lowercased()
    return Context(
      normalizedPath: normalizedPath,
      lowerPath: normalizedPath.lowercased(),
      pathComponents: Set(url.pathComponents.map { $0.lowercased() }),
      name: url.lastPathComponent,
      lowerName: url.lastPathComponent.lowercased(),
      fileExtension: fileExtension,
      itemType: input.itemType,
      lastModified: input.lastModified,
      now: now()
    )
  }

  private func matches(_ matcher: ClassificationRule.Matcher, context: Context) -> Bool {
    switch matcher {
    case .pathContains(let value):
      return context.lowerPath.contains(value.lowercased())
    case .pathComponent(let value):
      return context.pathComponents.contains(value.lowercased())
    case .pathPrefix(let value):
      return context.lowerPath.hasPrefix(value.lowercased())
    case .nameEquals(let value):
      return context.lowerName == value.lowercased()
    case .extensionIn(let values):
      guard let fileExtension = context.fileExtension else { return false }
      return values.contains { $0.caseInsensitiveCompare(fileExtension) == .orderedSame }
    case .itemType(let itemType):
      return context.itemType == itemType
    case .modifiedAtLeastDaysAgo(let days):
      guard let lastModified = context.lastModified else { return false }
      return context.now.timeIntervalSince(lastModified) >= Double(days) * 86_400
    case .nameMatches(let pattern):
      return context.name.range(
        of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    case .all(let matchers):
      return matchers.allSatisfy { matches($0, context: context) }
    case .any(let matchers):
      return matchers.contains { matches($0, context: context) }
    case .not(let matcher):
      return !matches(matcher, context: context)
    }
  }

  private func isSynced(_ context: Context) -> Bool {
    guard let rule = rules.first(where: { $0.id == "protect.cloud-synced" }) else {
      return false
    }
    return matches(rule.matcher, context: context)
  }

  private func confidenceRank(_ confidence: Confidence) -> Int {
    switch confidence {
    case .high: return 3
    case .medium: return 2
    case .low: return 1
    }
  }

  private func recommendedAction(for method: DeletionMethod) -> String {
    switch method {
    case .trash: return "Move to Trash"
    case .manualReview: return "Review manually in Finder"
    case .notAllowed: return "Leave in place"
    case .permanent: return "Delete permanently"
    }
  }

  private func inferredOwnerTool(for context: Context) -> String? {
    if context.lowerPath.contains("xcode") || context.pathComponents.contains("deriveddata")
      || context.lowerPath.contains("coresimulator")
    {
      return "Xcode"
    }
    if context.pathComponents.contains(".docker") { return "Docker" }
    if context.pathComponents.contains(".gradle") || context.lowerPath.contains("/android/") {
      return "Android"
    }
    if context.pathComponents.contains(".npm") || context.pathComponents.contains(".yarn")
      || context.pathComponents.contains(".pnpm-store") || context.pathComponents.contains(".next")
    {
      return "Node.js"
    }
    if context.pathComponents.contains("__pycache__") || context.lowerPath.contains("/pip") {
      return "Python"
    }
    if context.pathComponents.contains(".dart_tool")
      || context.pathComponents.contains(".pub-cache")
    {
      return "Flutter/Dart"
    }
    if context.pathComponents.contains(".cargo") || context.pathComponents.contains("target") {
      return "Rust"
    }
    return nil
  }
}
