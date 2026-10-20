import Foundation

public enum ItemType: String, Codable, CaseIterable, Sendable {
  case file
  case folder
  case symlink
}

public enum SafetyCategory: String, Codable, CaseIterable, Comparable, Sendable {
  case safeToDelete = "safe_to_delete"
  case probablyUnused = "probably_unused"
  case deleteIfAppUnused = "delete_if_app_unused"
  case doNotBulkDelete = "do_not_bulk_delete"

  private var cautionRank: Int {
    switch self {
    case .doNotBulkDelete: return 4
    case .deleteIfAppUnused: return 3
    case .probablyUnused: return 2
    case .safeToDelete: return 1
    }
  }

  public static func < (lhs: SafetyCategory, rhs: SafetyCategory) -> Bool {
    lhs.cautionRank < rhs.cautionRank
  }

  public static func mostCautious(_ categories: [SafetyCategory]) -> SafetyCategory {
    categories.max() ?? .doNotBulkDelete
  }
}

public enum Confidence: String, Codable, CaseIterable, Sendable {
  case high
  case medium
  case low
}

public enum DeletionMethod: String, Codable, CaseIterable, Sendable {
  case trash
  case permanent
  case manualReview = "manual_review"
  case notAllowed = "not_allowed"
}

public struct ScanResult: Identifiable, Codable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var path: String
  public var normalizedPath: String
  public var sizeBytes: Int64
  public var itemType: ItemType
  public var category: SafetyCategory
  public var confidence: Confidence
  public var reason: String
  public var riskNote: String
  public var recommendedAction: String
  public var lastModified: Date?
  public var ownerApp: String?
  public var ownerTool: String?
  public var fileExtension: String?
  public var isHidden: Bool
  public var isProtected: Bool
  public var isSynced: Bool
  public var isExcluded: Bool
  public var canDelete: Bool
  public var deletionMethod: DeletionMethod

  public init(
    id: String = UUID().uuidString,
    name: String,
    path: String,
    normalizedPath: String,
    sizeBytes: Int64,
    itemType: ItemType,
    category: SafetyCategory,
    confidence: Confidence,
    reason: String,
    riskNote: String,
    recommendedAction: String,
    lastModified: Date? = nil,
    ownerApp: String? = nil,
    ownerTool: String? = nil,
    fileExtension: String? = nil,
    isHidden: Bool,
    isProtected: Bool,
    isSynced: Bool,
    isExcluded: Bool,
    canDelete: Bool,
    deletionMethod: DeletionMethod
  ) {
    self.id = id
    self.name = name
    self.path = path
    self.normalizedPath = normalizedPath
    self.sizeBytes = sizeBytes
    self.itemType = itemType
    self.category = category
    self.confidence = confidence
    self.reason = reason
    self.riskNote = riskNote
    self.recommendedAction = recommendedAction
    self.lastModified = lastModified
    self.ownerApp = ownerApp
    self.ownerTool = ownerTool
    self.fileExtension = fileExtension
    self.isHidden = isHidden
    self.isProtected = isProtected
    self.isSynced = isSynced
    self.isExcluded = isExcluded
    self.canDelete = canDelete
    self.deletionMethod = deletionMethod
  }
}

public enum ScanStatus: String, Codable, Sendable {
  case idle
  case scanning
  case completed
  case cancelled
  case failed
}

public enum ScanMode: String, Codable, CaseIterable, Sendable {
  case limited
  case full
  case developer
}

public enum SkippedPathReason: String, Codable, Sendable {
  case permissionDenied = "permission_denied"
  case protectedByMacOS = "protected_by_macos"
  case excludedByUser = "excluded_by_user"
  case externalDriveUnavailable = "external_drive_unavailable"
  case symlinkLoop = "symlink_loop"
  case unknownError = "unknown_error"
}

public struct SkippedPath: Identifiable, Codable, Equatable, Sendable {
  public var id: String { path + reason.rawValue }
  public var path: String
  public var reason: SkippedPathReason
  public var message: String

  public init(path: String, reason: SkippedPathReason, message: String) {
    self.path = path
    self.reason = reason
    self.message = message
  }
}

public struct ScanSummary: Codable, Equatable, Sendable {
  public var totalResults: Int
  public var totalCleanableBytes: Int64
  public var safeToDeleteBytes: Int64
  public var probablyUnusedBytes: Int64
  public var deleteIfAppUnusedBytes: Int64
  public var doNotBulkDeleteBytes: Int64
  public var protectedBytes: Int64
  public var syncedBytes: Int64
  public var largestItems: [String]
  public var largestHiddenFolders: [String]

  public init(results: [ScanResult] = []) {
    totalResults = results.count
    // Nested folders are reported separately; count each byte once per category.
    func bytes(_ include: (ScanResult) -> Bool) -> Int64 {
      ResultPresentation.totalBytes(results.filter(include))
    }
    safeToDeleteBytes = bytes { $0.category == .safeToDelete }
    probablyUnusedBytes = bytes { $0.category == .probablyUnused }
    deleteIfAppUnusedBytes = bytes { $0.category == .deleteIfAppUnused }
    doNotBulkDeleteBytes = bytes { $0.category == .doNotBulkDelete }
    protectedBytes = bytes(\.isProtected)
    syncedBytes = bytes(\.isSynced)
    totalCleanableBytes = safeToDeleteBytes + probablyUnusedBytes + deleteIfAppUnusedBytes
    largestItems = results.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(10).map(\.id)
    largestHiddenFolders =
      results
      .filter { $0.isHidden && $0.itemType == .folder }
      .sorted { $0.sizeBytes > $1.sizeBytes }
      .prefix(10)
      .map(\.id)
  }
}

public struct ScanSession: Identifiable, Codable, Equatable, Sendable {
  public var id: String
  public var startedAt: Date
  public var completedAt: Date?
  public var status: ScanStatus
  public var scanMode: ScanMode
  public var diskTotalBytes: Int64
  public var diskUsedBytes: Int64
  public var diskAvailableBytes: Int64
  public var scannedPaths: [String]
  public var skippedPaths: [SkippedPath]
  public var results: [ScanResult]
  public var summary: ScanSummary

  public init(
    id: String = UUID().uuidString,
    startedAt: Date = Date(),
    completedAt: Date? = nil,
    status: ScanStatus,
    scanMode: ScanMode,
    diskTotalBytes: Int64,
    diskUsedBytes: Int64,
    diskAvailableBytes: Int64,
    scannedPaths: [String],
    skippedPaths: [SkippedPath],
    results: [ScanResult]
  ) {
    self.id = id
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.status = status
    self.scanMode = scanMode
    self.diskTotalBytes = diskTotalBytes
    self.diskUsedBytes = diskUsedBytes
    self.diskAvailableBytes = diskAvailableBytes
    self.scannedPaths = scannedPaths
    self.skippedPaths = skippedPaths
    self.results = results
    self.summary = ScanSummary(results: results)
  }
}

public enum CleanupStatus: String, Codable, Sendable {
  case deleted
  case skipped
  case blocked
  case failed
}

public struct CleanupItemResult: Identifiable, Codable, Equatable, Sendable {
  public var id: String { scanResultId + status.rawValue }
  public var scanResultId: String
  public var path: String
  public var sizeBytes: Int64
  public var status: CleanupStatus
  public var message: String

  public init(
    scanResultId: String, path: String, sizeBytes: Int64, status: CleanupStatus, message: String
  ) {
    self.scanResultId = scanResultId
    self.path = path
    self.sizeBytes = sizeBytes
    self.status = status
    self.message = message
  }
}

public struct CleanupSession: Identifiable, Codable, Equatable, Sendable {
  public var id: String
  public var startedAt: Date
  public var completedAt: Date?
  public var diskSpaceBeforeBytes: Int64
  public var diskSpaceAfterBytes: Int64?
  public var selectedItemIds: [String]
  public var deletedItems: [CleanupItemResult]
  public var skippedItems: [CleanupItemResult]
  public var blockedItems: [CleanupItemResult]
  public var failedItems: [CleanupItemResult]
  public var recoveredBytes: Int64

  public init(
    id: String = UUID().uuidString,
    startedAt: Date = Date(),
    completedAt: Date? = nil,
    diskSpaceBeforeBytes: Int64,
    diskSpaceAfterBytes: Int64? = nil,
    selectedItemIds: [String],
    deletedItems: [CleanupItemResult],
    skippedItems: [CleanupItemResult],
    blockedItems: [CleanupItemResult],
    failedItems: [CleanupItemResult]
  ) {
    self.id = id
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.diskSpaceBeforeBytes = diskSpaceBeforeBytes
    self.diskSpaceAfterBytes = diskSpaceAfterBytes
    self.selectedItemIds = selectedItemIds
    self.deletedItems = deletedItems
    self.skippedItems = skippedItems
    self.blockedItems = blockedItems
    self.failedItems = failedItems
    self.recoveredBytes = deletedItems.map(\.sizeBytes).reduce(0, +)
  }
}

public enum ExclusionRuleType: String, Codable, CaseIterable, Sendable {
  case exactPath = "exact_path"
  case folderRecursive = "folder_recursive"
  case pattern
  case category
}

public struct ExclusionRule: Identifiable, Codable, Equatable, Sendable {
  public var id: String
  public var path: String
  public var ruleType: ExclusionRuleType
  public var createdAt: Date
  public var reason: String?

  public init(
    id: String = UUID().uuidString, path: String, ruleType: ExclusionRuleType,
    createdAt: Date = Date(), reason: String? = nil
  ) {
    self.id = id
    self.path = path
    self.ruleType = ruleType
    self.createdAt = createdAt
    self.reason = reason
  }
}

public struct ClassificationRule: Identifiable, Codable, Equatable, Sendable {
  public indirect enum Matcher: Codable, Equatable, Sendable {
    case pathContains(String)
    case pathComponent(String)
    case nameEquals(String)
    case extensionIn([String])
    case itemType(ItemType)
    case modifiedAtLeastDaysAgo(Int)
    case all([Matcher])
    case any([Matcher])
  }

  public var id: String
  public var name: String
  public var matcher: Matcher
  public var category: SafetyCategory
  public var confidence: Confidence
  public var specificity: Int
  public var reason: String
  public var riskNote: String
  public var ownerApp: String?
  public var ownerTool: String?

  public init(
    id: String,
    name: String,
    matcher: Matcher,
    category: SafetyCategory,
    confidence: Confidence,
    specificity: Int,
    reason: String,
    riskNote: String,
    ownerApp: String? = nil,
    ownerTool: String? = nil
  ) {
    self.id = id
    self.name = name
    self.matcher = matcher
    self.category = category
    self.confidence = confidence
    self.specificity = specificity
    self.reason = reason
    self.riskNote = riskNote
    self.ownerApp = ownerApp
    self.ownerTool = ownerTool
  }
}

public struct Settings: Codable, Equatable, Sendable {
  public var scanHiddenFolders: Bool
  public var scanDeveloperFolders: Bool
  public var scanDownloads: Bool
  public var scanAppSupport: Bool
  public var defaultDeletionMethod: DeletionMethod
  public var showAdvancedCategories: Bool
  public var saveScanHistory: Bool
  public var largeFileThresholdBytes: Int64

  public static let `default` = Settings(
    scanHiddenFolders: true,
    scanDeveloperFolders: true,
    scanDownloads: true,
    scanAppSupport: true,
    defaultDeletionMethod: .trash,
    showAdvancedCategories: false,
    saveScanHistory: true,
    largeFileThresholdBytes: 500_000_000
  )
}

extension ScanResult {
  public static func fixture(path: String, sizeBytes: Int64, category: SafetyCategory) -> ScanResult
  {
    let isTrashable = category == .safeToDelete || category == .probablyUnused
    return ScanResult(
      name: URL(fileURLWithPath: path).lastPathComponent,
      path: path,
      normalizedPath: URL(fileURLWithPath: path).standardizedFileURL.path,
      sizeBytes: sizeBytes,
      itemType: .folder,
      category: category,
      confidence: .medium,
      reason: "Fixture",
      riskNote: "Fixture",
      recommendedAction: category == .doNotBulkDelete
        ? "Review manually in Finder" : "Move to Trash",
      isHidden: URL(fileURLWithPath: path).lastPathComponent.hasPrefix("."),
      isProtected: false,
      isSynced: false,
      isExcluded: false,
      canDelete: isTrashable,
      deletionMethod: isTrashable ? .trash : .manualReview
    )
  }
}
