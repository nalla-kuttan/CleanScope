import Testing

@testable import CleanScopeCore

@Suite struct SafetyInvariantTests {
  @Test func neverSafePaths() {
    let service = ClassificationService()
    let paths = [
      "/Users/me/Documents/report.pdf",
      "/Users/me/Desktop/photo.jpg",
      "/Users/me/Pictures/Photos Library.photoslibrary",
      "/Users/me/Music/Music Library",
      "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/file.txt",
      "/Users/me/Google Drive/file.txt",
      "/Users/me/Dropbox/file.txt",
      "/Users/me/OneDrive/file.txt",
      "/Users/me/Library/Application Support/Google/Chrome/Default",
      "/Users/me/Library/Application Support/1Password",
      "/Users/me/Library/Messages/chat.db",
      "/Users/me/project/.git",
      "/Users/me/Virtual Machines/Linux.vmwarevm",
      "/Users/me/.docker/volumes/postgres/_data",
    ]

    for path in paths {
      let result = service.classify(
        ClassifiedItemInput(path: path, sizeBytes: 10_000_000_000, itemType: .folder))
      #expect(result.category != .safeToDelete, Comment(rawValue: path))
    }
  }

  @Test func everyResultHasPlainLanguageExplanation() {
    let service = ClassificationService()
    let result = service.classify(
      ClassifiedItemInput(path: "/Users/me/Library/Caches/App", sizeBytes: 100, itemType: .folder))

    #expect(!result.reason.isEmpty)
    #expect(!result.riskNote.isEmpty)
    #expect(!result.recommendedAction.isEmpty)
  }
}
