import Foundation

/// Paths a traversal must never descend into, and the canonical form used for de-duplication.
public enum SystemPathGuard {
  private static let skippedRoots = [
    "/System/Volumes/Data", "/Volumes", "/.nofollow", "/private/var/vm", "/home",
  ]
  private static let dataVolumePrefix = "/System/Volumes/Data/"

  public static func shouldSkip(_ path: String) -> Bool {
    skippedRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
  }

  public static func canonical(_ path: String) -> String {
    guard path.hasPrefix(dataVolumePrefix) else { return path }
    return "/" + path.dropFirst(dataVolumePrefix.count)
  }
}
