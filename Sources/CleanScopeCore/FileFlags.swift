import Darwin
import Foundation

/// BSD file flags read with `lstat`, for cloud placeholders and SIP-protected items.
public struct FileFlags: Equatable, Sendable {
  /// `SF_DATALESS`: a cloud placeholder whose content is not on disk.
  public static let datalessMask: UInt32 = 0x4000_0000
  /// `SF_RESTRICTED`: protected by System Integrity Protection.
  public static let restrictedMask: UInt32 = 0x0008_0000

  public var isDataless: Bool
  public var isRestricted: Bool

  public init(rawFlags: UInt32) {
    isDataless = rawFlags & Self.datalessMask != 0
    isRestricted = rawFlags & Self.restrictedMask != 0
  }

  public static func read(path: String) -> FileFlags? {
    var info = stat()
    guard lstat(path, &info) == 0 else { return nil }
    return FileFlags(rawFlags: info.st_flags)
  }
}

/// Directory listing helpers that see what Foundation hides.
public enum PosixDirectory {
  /// `._*` AppleDouble files in `path` with their allocated sizes. Foundation's directory
  /// enumeration hides these files, so they are read with `readdir`.
  public static func appleDoubleFiles(in path: String) -> [(path: String, bytes: Int64)] {
    guard let directory = opendir(path) else { return [] }
    defer { closedir(directory) }
    var found: [(path: String, bytes: Int64)] = []
    while let entry = readdir(directory) {
      let name = withUnsafePointer(to: entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
      }
      guard name.hasPrefix("._"), name.count > 2 else { continue }
      let full = (path as NSString).appendingPathComponent(name)
      var info = stat()
      guard lstat(full, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { continue }
      found.append((full, Int64(info.st_blocks) * 512))
    }
    return found
  }
}
