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

  private let now: @Sendable () -> Date

  public init(now: @escaping @Sendable () -> Date = { Date() }) {
    self.now = now
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
    let selected = Self.builtInRules
      .filter { matches($0.matcher, context: context) }
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
    let canMoveToTrash = category == .safeToDelete || category == .probablyUnused
    let unavailable = input.isProtected || input.isExcluded
    let deletionMethod: DeletionMethod =
      unavailable ? .notAllowed : (canMoveToTrash ? .trash : .manualReview)

    return ScanResult(
      name: context.name,
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
      ownerApp: selected?.ownerApp,
      ownerTool: selected?.ownerTool ?? inferredOwnerTool(for: context),
      fileExtension: context.fileExtension,
      isHidden: context.name.hasPrefix("."),
      isProtected: input.isProtected,
      isSynced: isSynced(context),
      isExcluded: input.isExcluded,
      canDelete: canMoveToTrash && !unavailable,
      deletionMethod: deletionMethod
    )
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
    case .all(let matchers):
      return matchers.allSatisfy { matches($0, context: context) }
    case .any(let matchers):
      return matchers.contains { matches($0, context: context) }
    }
  }

  private func isSynced(_ context: Context) -> Bool {
    guard let rule = Self.builtInRules.first(where: { $0.id == "protect.cloud-synced" }) else {
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
