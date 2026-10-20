import Foundation

/// Last line of defense before anything is removed: never the filesystem root, a top-level
/// folder, a mounted drive's root, the home folder, or its key folders, whatever a rule says.
public enum RemovalGuard {
  public static func isRemovable(_ path: String, homeDirectory: String = NSHomeDirectory())
    -> Bool
  {
    guard !path.isEmpty else { return false }
    let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
    let components = URL(fileURLWithPath: standardized).pathComponents.filter { $0 != "/" }
    guard components.count >= 2 else { return false }
    if components.first == "private", components.count < 3 { return false }
    if components.first == "Volumes", components.count < 3 { return false }

    let home = URL(fileURLWithPath: homeDirectory).standardizedFileURL.path
    let protectedHomeFolders = [
      "", "/Library", "/Documents", "/Desktop", "/Downloads", "/Pictures", "/Movies", "/Music",
      "/Applications", "/Library/Application Support", "/Library/Containers",
      "/Library/Mobile Documents",
    ].map { home + $0 }
    return !protectedHomeFolders.contains(standardized)
  }
}
