import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct FileSystemHelpersTests {
  @Test func regularFileHasNoSpecialFlags() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([1, 2, 3]).write(to: url)
    let flags = try #require(FileFlags.read(path: url.path))
    #expect(!flags.isDataless)
    #expect(!flags.isRestricted)
  }

  @Test func missingPathHasNoFlags() {
    #expect(FileFlags.read(path: "/nonexistent/\(UUID().uuidString)") == nil)
  }

  @Test func flagBitsDecode() {
    #expect(FileFlags(rawFlags: 0x4000_0000).isDataless)
    #expect(FileFlags(rawFlags: 0x0008_0000).isRestricted)
    #expect(!FileFlags(rawFlags: 0).isDataless)
  }

  @Test func guardSkipsSystemPaths() {
    for path in [
      "/System/Volumes/Data", "/System/Volumes/Data/Users", "/Volumes", "/Volumes/Backup/a",
      "/.nofollow", "/private/var/vm", "/private/var/vm/sleepimage", "/home",
    ] {
      #expect(SystemPathGuard.shouldSkip(path), Comment(rawValue: path))
    }
    for path in ["/Users/me", "/Volumesque", "/homework", "/private/var/log"] {
      #expect(!SystemPathGuard.shouldSkip(path), Comment(rawValue: path))
    }
  }

  @Test func guardCanonicalizesDataVolumePaths() {
    #expect(SystemPathGuard.canonical("/System/Volumes/Data/Users/me") == "/Users/me")
    #expect(SystemPathGuard.canonical("/Users/me") == "/Users/me")
  }
}
