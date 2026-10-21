import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct JunkRuleTests {
  let service = ClassificationService(appName: { $0 == "com.apple.mail" ? "Mail" : nil })

  private func classify(_ path: String, _ type: ItemType = .folder) -> ScanResult {
    service.classify(ClassifiedItemInput(path: path, sizeBytes: 100, itemType: type))
  }

  @Test func chromiumCacheFoldersAreSafeWithOwner() {
    for name in ["Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache"] {
      let result = classify("/Users/me/Library/Application Support/Slack/\(name)")
      #expect(result.category == .safeToDelete, Comment(rawValue: name))
      #expect(result.ownerApp == "Slack", Comment(rawValue: name))
      #expect(result.ruleId == "safe.chromium-caches")
    }
  }

  @Test func chromiumUserStateIsNeverSafe() {
    let paths = [
      "/Users/me/Library/Application Support/Slack/IndexedDB",
      "/Users/me/Library/Application Support/Slack/Local Storage",
      "/Users/me/Library/Application Support/Slack/Service Worker/CacheStorage/Cache",
      "/Users/me/Library/Application Support/Slack/databases/Cache",
      "/Users/me/Library/Application Support/Google/Chrome/Default/Cache",
    ]
    for path in paths {
      #expect(classify(path).category != .safeToDelete, Comment(rawValue: path))
    }
    #expect(
      classify("/Users/me/Library/Application Support/Google/Chrome/Default/Cache").category
        == .doNotBulkDelete)
  }

  @Test func sandboxedChromiumCacheIsSafe() {
    let result = classify(
      "/Users/me/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/Cache"
    )
    #expect(result.category == .safeToDelete)
  }

  @Test func knownAppMediaCaches() {
    let spotify = classify(
      "/Users/me/Library/Application Support/Spotify/PersistentCache/Storage")
    #expect(spotify.category == .safeToDelete)
    #expect(spotify.ownerApp == "Spotify")

    let adobe = classify(
      "/Users/me/Library/Application Support/Adobe/Common/Media Cache Files")
    #expect(adobe.category == .safeToDelete)
    #expect(adobe.ownerApp == "Adobe")

    let telegram = classify(
      "/Users/me/Library/Application Support/Telegram Desktop/tdata/user_data")
    #expect(telegram.category == .probablyUnused)
    #expect(telegram.confidence == .medium)
    #expect(telegram.ownerApp == "Telegram")
  }

  @Test func containerCacheFolderIsSafeAndNamedAfterApp() {
    let mail = classify("/Users/me/Library/Containers/com.apple.mail/Data/Library/Caches")
    #expect(mail.category == .safeToDelete)
    #expect(mail.name == "Mail cache (com.apple.mail)")
    #expect(mail.ownerApp == "Mail")

    let unknown = classify("/Users/me/Library/Containers/x/Data/Library/Caches")
    #expect(unknown.category == .safeToDelete)
    #expect(unknown.ownerApp == "x")
    #expect(unknown.name == "x cache (x)")
  }

  @Test func containerUserDataIsNeverSafe() {
    #expect(
      classify("/Users/me/Library/Containers/x/Data/Documents/file", .file).category
        != .safeToDelete)
    #expect(
      classify("/Users/me/Library/Containers/x/Data/Library/Application Support/db", .file)
        .category != .safeToDelete)
  }

  @Test func systemLogs() {
    #expect(classify("/private/var/log/system.log.0.gz", .file).category == .safeToDelete)
    #expect(classify("/private/var/log/wifi.log.3.bz2", .file).category == .safeToDelete)
    let live = classify("/private/var/log/system.log", .file)
    #expect(live.category == .probablyUnused)
    #expect(live.confidence == .low)
    #expect(
      classify("/Users/me/Library/Logs/DiagnosticReports/a.ips", .file).category
        == .safeToDelete)
    #expect(classify("/Library/Logs/DiagnosticReports", .folder).category == .safeToDelete)
  }

  @Test func temporaryFoldersMatchAfterPathNormalization() {
    #expect(
      classify("/private/var/folders/ab/xyz/C/com.example").category == .safeToDelete)
  }

  @Test func onlyCacheAndTempFoldersUnderVarFoldersAreSafe() {
    #expect(classify("/private/var/folders/ab/xyz/T/com.example").category == .safeToDelete)
    #expect(classify("/var/folders/ab/xyz/C/com.example").category == .safeToDelete)
    // `0` holds live per-user databases, such as Notification Center's.
    let userData = classify("/private/var/folders/ab/xyz/0/com.apple.notificationcenter")
    #expect(userData.category != .safeToDelete)
  }

  @Test func onlyTheSystemTmpFolderIsTemporary() {
    #expect(classify("/private/tmp/build-123").category == .safeToDelete)
    #expect(classify("/tmp/build-123").category == .safeToDelete)
    for path in ["/Users/me/tmp/thesis-drafts", "/Users/me/Downloads/project/tmp"] {
      #expect(classify(path).category != .safeToDelete, Comment(rawValue: path))
    }
  }

  @Test func toolInstallsInCachesAreNotReadyToDelete() {
    let paths = [
      "/Users/me/Library/Caches/ms-playwright",
      "/Users/me/Library/Caches/ms-playwright/chromium-1140",
      "/Users/me/Library/Caches/Cypress",
      "/Users/me/Library/Caches/pypoetry/virtualenvs/app-x1y2-py3.12",
    ]
    for path in paths {
      let result = classify(path)
      #expect(result.category == .deleteIfAppUnused, Comment(rawValue: path))
      #expect(!ResultPresentation.isReadyToDeleteCache(result), Comment(rawValue: path))
    }
    // Poetry's download cache, beside its virtualenvs, is still an ordinary cache.
    let cache = classify("/Users/me/Library/Caches/pypoetry/cache")
    #expect(ResultPresentation.isReadyToDeleteCache(cache))
  }

  @Test func appStoreCachesAreNamed() {
    for name in ["com.apple.appstoreagent", "com.apple.appstorecomponentsd"] {
      let result = classify("/private/var/folders/d2/abc/C/\(name)")
      #expect(result.category == .safeToDelete, Comment(rawValue: name))
      #expect(result.ruleId == "safe.appstore-downloads", Comment(rawValue: name))
      #expect(result.ownerApp == "App Store")
    }
  }
}
