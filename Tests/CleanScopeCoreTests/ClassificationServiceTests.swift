import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct ClassificationServiceTests {
  let service = ClassificationService(now: { ClassificationFixtures.referenceDate })

  @Test func requiredFixtureFamiliesFollowDocumentedCategories() {
    for fixture in ClassificationFixtures.requiredFamilies {
      let result = service.classify(fixture.input)
      #expect(
        result.category == fixture.expectedCategory,
        Comment(rawValue: fixture.label)
      )
    }
  }

  @Test func documentsNeverBecomeSafeBecauseOfSize() {
    let item = ClassifiedItemInput(
      path: "/Users/me/Documents/Huge.mov", sizeBytes: 12_000_000_000, itemType: .file)
    let result = service.classify(item)

    #expect(result.category == .doNotBulkDelete)
    #expect(!result.canDelete)
    #expect(result.deletionMethod == .manualReview)
  }

  @Test func cloudFolderWinsOverGeneratedFolderName() {
    let item = ClassifiedItemInput(
      path: "/Users/me/Dropbox/project/.next", sizeBytes: 1_000, itemType: .folder)
    let result = service.classify(item)

    #expect(result.category == .doNotBulkDelete)
    #expect(result.isSynced)
  }

  @Test func dockerVolumeRequiresToolDependentWarning() {
    let item = ClassifiedItemInput(
      path: "/Users/me/.docker/volumes/postgres_data", sizeBytes: 900, itemType: .folder)
    let result = service.classify(item)

    #expect(result.category == .deleteIfAppUnused)
    #expect(result.confidence == .high)
    #expect(result.ownerTool == "Docker")
    #expect(result.riskNote.localizedCaseInsensitiveContains("persistent"))
    #expect(!result.canDelete)
  }

  @Test func unknownApplicationSupportIsNotSafe() {
    let item = ClassifiedItemInput(
      path: "/Users/me/Library/Application Support/MysteryApp", sizeBytes: 900, itemType: .folder)
    let result = service.classify(item)

    #expect(result.category == .deleteIfAppUnused)
    #expect(!result.canDelete)
  }

  @Test func generatedDeveloperFoldersAreSafe() {
    let paths = [
      "/Users/me/Library/Developer/Xcode/DerivedData/App",
      "/Users/me/project/.next",
      "/Users/me/project/build",
      "/Users/me/project/target",
      "/Users/me/project/__pycache__",
      "/Users/me/project/.dart_tool",
    ]

    for path in paths {
      let result = service.classify(
        ClassifiedItemInput(path: path, sizeBytes: 100, itemType: .folder))
      #expect(result.category == .safeToDelete, Comment(rawValue: path))
    }
  }

  @Test func downloadsBecomeProbablyUnusedAtNinetyDays() {
    let beforeBoundary = service.classify(
      ClassifiedItemInput(
        path: "/Users/me/Downloads/archive.zip",
        sizeBytes: 100,
        itemType: .file,
        lastModified: ClassificationFixtures.date(daysAgo: 89.99)
      ))
    let atBoundary = service.classify(
      ClassifiedItemInput(
        path: "/Users/me/Downloads/archive.zip",
        sizeBytes: 100,
        itemType: .file,
        lastModified: ClassificationFixtures.date(daysAgo: 90)
      ))
    let afterBoundary = service.classify(
      ClassifiedItemInput(
        path: "/Users/me/Downloads/archive.zip",
        sizeBytes: 100,
        itemType: .file,
        lastModified: ClassificationFixtures.date(daysAgo: 91)
      ))

    #expect(beforeBoundary.category == .doNotBulkDelete)
    #expect(atBoundary.category == .probablyUnused)
    #expect(afterBoundary.category == .probablyUnused)
  }

  @Test func recentDownloadInstallerIsNotProbablyUnusedBasedOnTypeAlone() {
    let result = service.classify(
      ClassifiedItemInput(
        path: "/Users/me/Downloads/new-installer.dmg",
        sizeBytes: 100,
        itemType: .file,
        lastModified: ClassificationFixtures.date(daysAgo: 2)
      ))

    #expect(result.category == .doNotBulkDelete)
  }

  @Test func missingDownloadDateRemainsConservative() {
    let result = service.classify(
      ClassifiedItemInput(
        path: "/Users/me/Downloads/unknown-age.zip",
        sizeBytes: 100,
        itemType: .file
      ))

    #expect(result.category == .doNotBulkDelete)
  }

  @Test func builtInRulesAreTypedAndInspectable() {
    let rules = ClassificationService.builtInRules

    #expect(!rules.isEmpty)
    #expect(Set(rules.map(\.id)).count == rules.count)
    for rule in rules {
      #expect(!rule.id.isEmpty)
      #expect(!rule.name.isEmpty)
      #expect(!rule.reason.isEmpty)
      #expect(!rule.riskNote.isEmpty)
      #expect(rule.specificity > 0)
    }
  }

  @Test func appCriticalApplicationSupportWinsOverGenericAppSupport() {
    let result = service.classify(
      ClassifiedItemInput(
        path: "/Users/me/Library/Application Support/Google/Chrome/Default",
        sizeBytes: 100,
        itemType: .folder
      ))

    #expect(result.category == .doNotBulkDelete)
    #expect(result.confidence == .high)
  }

  @Test func sourceRepositoriesAreDoNotBulkDelete() {
    let result = service.classify(
      ClassifiedItemInput(path: "/Users/me/project/.git", sizeBytes: 100, itemType: .folder))

    #expect(result.category == .doNotBulkDelete)
  }

  @Test func ageDoesNotOverridePersonalLocationSafety() {
    let oldDate = Date(timeIntervalSince1970: 0)
    let result = service.classify(
      ClassifiedItemInput(
        path: "/Users/me/Documents/archive.zip",
        sizeBytes: 10_000_000_000,
        itemType: .file,
        lastModified: oldDate
      ))

    #expect(result.category == .doNotBulkDelete)
    #expect(!result.canDelete)
  }

  @Test func sizeAloneDoesNotMakeUnknownItemSafe() {
    let result = service.classify(
      ClassifiedItemInput(
        path: "/Users/me/Unclassified/huge.data",
        sizeBytes: 100_000_000_000,
        itemType: .file
      ))

    #expect(result.category == .doNotBulkDelete)
  }

  @Test func protectedCacheCannotBeDeleted() {
    let result = service.classify(
      ClassifiedItemInput(
        path: "/Users/me/Library/Caches/App",
        sizeBytes: 100,
        itemType: .folder,
        isProtected: true
      ))

    #expect(result.category == .safeToDelete)
    #expect(!result.canDelete)
    #expect(result.deletionMethod == .notAllowed)
  }

  @Test func excludedCacheCannotBeDeleted() {
    let result = service.classify(
      ClassifiedItemInput(
        path: "/Users/me/Library/Caches/App",
        sizeBytes: 100,
        itemType: .folder,
        isExcluded: true
      ))

    #expect(result.category == .safeToDelete)
    #expect(!result.canDelete)
    #expect(result.deletionMethod == .notAllowed)
  }
}
