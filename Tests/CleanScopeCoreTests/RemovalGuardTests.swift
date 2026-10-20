import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct RemovalGuardTests {
  @Test func refusesRootsAndKeyFolders() {
    for path in [
      "/", "/System", "/Library", "/Applications", "/Users", "/private/var", "/var", "/usr",
      "/Users/me", "/Users/me/Library", "/Users/me/Documents", "/Users/me/Desktop",
      "/Users/me/Library/Caches/../..", "/Volumes/Drive", "",
    ] {
      #expect(!RemovalGuard.isRemovable(path, homeDirectory: "/Users/me"), Comment(rawValue: path))
    }
  }

  @Test func allowsOrdinaryItems() {
    for path in [
      "/Users/me/Library/Caches/com.example", "/Applications/Shady.app",
      "/private/var/log/system.log.0.gz", "/Volumes/Drive/.Trashes/501",
    ] {
      #expect(RemovalGuard.isRemovable(path, homeDirectory: "/Users/me"), Comment(rawValue: path))
    }
  }

  @Test func deletionBlocksGuardedPaths() async {
    var home = ScanResult.fixture(path: NSHomeDirectory(), sizeBytes: 1, category: .safeToDelete)
    home.canDelete = true
    let service = DeletionService(
      fileMover: { _ in
        Issue.record("Guarded path reached the mover")
        return true
      }, diskSnapshot: { 1 })
    let session = await service.cleanup(selected: [home])
    #expect(session.blockedItems.count == 1)
  }
}
