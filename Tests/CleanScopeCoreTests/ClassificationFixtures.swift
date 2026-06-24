import Foundation

@testable import CleanScopeCore

struct ClassificationFixture: Sendable {
  var label: String
  var input: ClassifiedItemInput
  var expectedCategory: SafetyCategory
}

enum ClassificationFixtures {
  static let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
  static let day: TimeInterval = 86_400

  static func date(daysAgo: Double) -> Date {
    referenceDate.addingTimeInterval(-daysAgo * day)
  }

  static let requiredFamilies: [ClassificationFixture] = [
    ClassificationFixture(
      label: "safe cache",
      input: ClassifiedItemInput(
        path: "/Users/me/Library/Caches/com.example.app",
        sizeBytes: 2_000,
        itemType: .folder
      ),
      expectedCategory: .safeToDelete
    ),
    ClassificationFixture(
      label: "old download",
      input: ClassifiedItemInput(
        path: "/Users/me/Downloads/installer.dmg",
        sizeBytes: 4_000,
        itemType: .file,
        lastModified: date(daysAgo: 120)
      ),
      expectedCategory: .probablyUnused
    ),
    ClassificationFixture(
      label: "Docker volume",
      input: ClassifiedItemInput(
        path: "/Users/me/.docker/volumes/postgres_data/_data",
        sizeBytes: 8_000,
        itemType: .folder
      ),
      expectedCategory: .deleteIfAppUnused
    ),
    ClassificationFixture(
      label: "unknown Application Support",
      input: ClassifiedItemInput(
        path: "/Users/me/Library/Application Support/MysteryApp",
        sizeBytes: 1_000,
        itemType: .folder
      ),
      expectedCategory: .deleteIfAppUnused
    ),
    ClassificationFixture(
      label: "cloud-synced generated folder",
      input: ClassifiedItemInput(
        path: "/Users/me/Dropbox/project/.next",
        sizeBytes: 5_000,
        itemType: .folder
      ),
      expectedCategory: .doNotBulkDelete
    ),
    ClassificationFixture(
      label: "source directory",
      input: ClassifiedItemInput(
        path: "/Users/me/project/Sources",
        sizeBytes: 6_000,
        itemType: .folder
      ),
      expectedCategory: .doNotBulkDelete
    ),
    ClassificationFixture(
      label: "generated source descendant",
      input: ClassifiedItemInput(
        path: "/Users/me/project/.next",
        sizeBytes: 7_000,
        itemType: .folder
      ),
      expectedCategory: .safeToDelete
    ),
  ]
}
